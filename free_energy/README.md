# free_energy/ —— 步骤 5 自由能（伞形采样 US/SMD + WHAM）模板

算「离子穿过纳米通道孔 / 冠醚孔的 PMF（自由能曲线）」从这里抄。方法完整说明见顶层 `WORKFLOW.md`。

> 这里**只放 4 个可复用子步骤**：`smd → extract → us → pmf`。
> **建模复用 models 的 `0build` / `1model`**——自由能用的 US 建模脚本
> `build_us_system.tcl`（旋转目标孔 + 溶剂化 + 加离子）放在
> `models/<name>/0build/` 里，产物写进 `models/<name>/1model/`，
> 与标准建模共用目录，不另设 `1model_us` 或 `5free`。

## 子步骤与文件

| 目录 | 是什么 | 文件 |
|---|---|---|
| `smd/` | 平衡 + SMD 拉伸：目标离子从管外体相匀速拉过孔 | `eq.conf`（minimize + 1 ns NVT）+ `smd.conf` + `smd.colvars.in` + `run_smd.sh` |
| `extract/` | 从 SMD 轨迹按 z 提取各窗口起始构象 | `extract.tcl` + `run_extract.sh` |
| `us/` | 伞形采样：各窗口固定 z 采样 | `template.conf` + `windows.txt` + `setup_us.sh` + `run_all.sh` |
| `pmf/` | WHAM 拼无偏 PMF + 绘图 | `wham.py` + `run_wham.sh` + `plot_pmf.py` |

> **`us/` 有两份窗口清单，`windows.txt` 是脚本实际读的那份**：
> - `windows.txt` —— **默认，窄量程 ±5 Å**：均匀步长 0.4 Å + 孔心 0.00，27 个窗口，全域 k=50。
>   配 `--zmax 6 --zmin -6`。稳，推荐先用这份。
> - `windows_bulk_to_tube.txt` —— 宽量程 47 窗口（体相 +12 → 管内 −6），孔区 k=250、体相 k=10。
>   需要**绝对** PMF（管外真平台）时才用；用法是 `cp windows_bulk_to_tube.txt windows.txt`。
>   配 `--zmax 12 --zmin -6`。已知脆弱点写在该文件头部。
>
> 无论用哪份，**窗口清单里必须有势垒中心那一个（通常 `z=0.00`）**，
> 否则 WHAM 会在峰顶输出 `NaN` 空洞、势垒高度只能外推。原因见 `windows.txt` 顶部实测教训。

## 完整链（在哪跑）

1. **建模**（在 `models/<name>/`）：先用 `0build/build_cnt_crown.tcl` 生成未溶剂化
   `system_combined.psf/pdb`，再用 `0build/build_us_system.tcl`（`run_build_us.sh`）旋转孔 + 溶剂化 + 加离子。
   产物写进 `1model/`（含 `ion_index.dat`、`ox_indices.dat`、`cell_params.tcl` 等）。
2. `cd smd && ./run_smd.sh` —— **平衡 1 ns + SMD 拉伸 1 ns**（两步走）：
   `eq.conf` 先 `minimize 5000` + 1 ns NVT（目标离子三维钉在放置点），
   `smd.conf` 再用 `bincoordinates/binvelocities/extendedSystem` 从 `eq_output.*` 续跑。
   `eq_output.coor/.vel/.xsc` 三者齐备时自动跳过平衡；`SKIP_EQ=1 ./run_smd.sh` 强制跳过。
3. `cd ../extract && ./run_extract.sh` —— 提取窗口构象到 `../us/win_XX.XX.pdb`。
4. `cd ../us && ./setup_us.sh && ./run_all.sh` —— 伞形采样（`windows.txt` 默认 27 窗口）。
5. `cd ../pmf && ./run_wham.sh` —— WHAM → `pmf.txt`；再 `plot_pmf.py` 出图。

```bash
# 用 new_project.sh --with-free-energy 生成项目后，把这些目录拷进项目根（或直接在该项目里跑）
cd <项目>/smd && ./run_smd.sh
cd ../extract && ./run_extract.sh
cd ../us && ./setup_us.sh && ./run_all.sh
cd ../pmf && ./run_wham.sh && python plot_pmf.py
```

## 只要改这几处（其余不用动）

| 改哪里 | 参数 | 说明 |
|---|---|---|
| `models/<name>/0build/run_build_us.sh` 或命令行 | `--ion`（POT/CAL/SOD）、`--anion`、`--nion/--nanion`、`--zmax/--zmin` | 离子种类与反应坐标范围 |
| `us/windows.txt` | 每行 `窗口中心z 弹簧常数k` | 见下面三条规则。**势垒中心窗口（`z=0.00`）绝不可少** |
| `smd/smd.colvars.in` | `forceConstant`、`centers`、`targetCenters` | SMD 拉速与弹簧；`centers/targetCenters` 要覆盖窗口范围 |
| `smd/eq.conf` | `run 500000` | 平衡时长（1 ns）。想跳过平衡：`SKIP_EQ=1 ./run_smd.sh` |
| `us/template.conf` | `run 2500000` | 每窗口时长（5 ns 默认） |

> **窗口清单三条规则**（`us/windows.txt` 顶部有完整版）：
> ① 相邻窗口间距 Δz ≲ σ = √(RT/k)，否则直方图断开 → WHAM 出 `NaN`；
> ② 弹簧常数全域统一最省心；混用强/弱弹簧容易在缝里出现空 bin；
> ③ **清单里必须包含势垒中心**（通常 `z=0.00`）—— 实测把它"优化"掉会导致
> 峰顶 26 个 `NaN`、峰位从 0 偏到 −0.11、势垒只能外推。详见 `us/windows.txt`。

> **换离子电荷数时反离子个数要跟着变**：Ca²⁺ 要 `--nanion 2`。
> **反应坐标约定**：目标孔被旋转到「孔轴 = +Z、孔心 = 原点」，管外体相为正、管内为负，
> colvars 用 `distanceZ`。
> **⚠️ 覆盖提醒**：US 建模会在 `1model/` 里重新生成 `system_ion.*`（旋转后的孔）等文件，
> 与标准 0–3 的 `system_ion.*` 同名。步骤 4 和 5 是"二选一"；若同一个模型既要跑 4prod
> 又要跑自由能，请用**两个独立项目目录**（`new_project.sh` 各生成一个），避免互相覆盖。

## 说明

- 盒子尺寸、原子序号全部自动探测：建模时自动写进 `1model/`（`cell_params.tcl`、
  `ion_index.dat`、`ox_indices.dat`），后续 smd/us/wham 脚本 source/读取它们，换体系不用改常量。
- **`smd/` 的平衡阶段（`eq.conf`）是相对老做法的改进**：老做法把 `minimize 5000`
  写在 `smd.conf` 开头，最小化完立刻以几 Å/ns 往外拉。窄量程（±5 Å）时最外端窗口
  就落在 SMD 起点附近，而它往往正是 PMF 的零点参考，水没松弛会直接污染基线。
  代价很小（2 万原子 1 ns NVT 在 4090 上约 7 分钟），所以默认保留。
- **续跑时的关键约束**：`smd.conf` 用了 `binvelocities`，就**不能再写 `temperature`**
  （NAMD 会 `FATAL ERROR: Cannot specify both an initial temperature and a velocity file`）；
  恒温靠 `langevin` + `langevinTemp`。这是改两步走时必踩的一步，见顶层 `WORKFLOW.md` §8。
- WHAM 用自实现 `wham.py`（仅 numpy）；要严格误差棒建议装 PyMBAR
  （`conda install --override-channels -c conda-forge pymbar`）。
- 多窗口并发：`us/run_all.sh` 默认 3 并发 × `+p16`（无绑核）；只有单窗口顺序跑
  （`MAX_JOBS=1`）才用 `+p32 +setcpuaffinity`。详见 `run_all.sh` 头注释与顶层 `WORKFLOW.md`。
