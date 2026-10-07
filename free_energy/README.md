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
| `smd/` | SMD 拉伸：把 K⁺ 从管外体相匀速拉过孔 | `smd.conf` + `smd.colvars.in` + `run_smd.sh` |
| `extract/` | 从 SMD 轨迹按 z 提取各窗口起始构象 | `extract.tcl` + `run_extract.sh` |
| `us/` | 伞形采样：47 个窗口各自固定 z 采样 | `template.conf` + `windows.txt` + `setup_us.sh` + `run_all.sh` |
| `pmf/` | WHAM 拼无偏 PMF + 绘图 | `wham.py` + `run_wham.sh` + `plot_pmf.py` |

## 完整链（在哪跑）

1. **建模**（在 `models/<name>/`）：先用 `0build/build_cnt_crown.tcl` 生成未溶剂化
   `system_combined.psf/pdb`，再用 `0build/build_us_system.tcl`（`run_build_us.sh`）旋转孔 + 溶剂化 + 加离子。
   产物写进 `1model/`（含 `ion_index.dat`、`ox_indices.dat`、`cell_params.tcl` 等）。
2. `cd smd && ./run_smd.sh` —— SMD 拉伸 1 ns。
3. `cd ../extract && ./run_extract.sh` —— 提取窗口构象到 `../us/win_XX.XX.pdb`。
4. `cd ../us && ./setup_us.sh && ./run_all.sh` —— 47 窗口伞形采样。
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
| `us/windows.txt` | 每行 `窗口中心z 弹簧常数k` | 孔区（势垒处）小间距 + 强弹簧，体相区大间距 + 弱弹簧 |
| `smd/smd.colvars.in` | `forceConstant`、`centers`、`targetCenters` | SMD 拉速与弹簧 |
| `us/template.conf` | `run 2500000` | 每窗口时长（5 ns 默认） |

> **换离子电荷数时反离子个数要跟着变**：Ca²⁺ 要 `--nanion 2`。
> **反应坐标约定**：目标孔被旋转到「孔轴 = +Z、孔心 = 原点」，管外体相为正、管内为负，
> colvars 用 `distanceZ`。
> **⚠️ 覆盖提醒**：US 建模会在 `1model/` 里重新生成 `system_ion.*`（旋转后的孔）等文件，
> 与标准 0–3 的 `system_ion.*` 同名。步骤 4 和 5 是"二选一"；若同一个模型既要跑 4prod
> 又要跑自由能，请用**两个独立项目目录**（`new_project.sh` 各生成一个），避免互相覆盖。

## 说明

- 盒子尺寸、原子序号全部自动探测：建模时自动写进 `1model/`（`cell_params.tcl`、
  `ion_index.dat`、`ox_indices.dat`），后续 smd/us/wham 脚本 source/读取它们，换体系不用改常量。
- WHAM 用自实现 `wham.py`（仅 numpy）；要严格误差棒建议装 PyMBAR
  （`conda install --override-channels -c conda-forge pymbar`）。
- 多窗口并发：`us/run_all.sh` 默认 3 并发 × `+p16`（无绑核）；只有单窗口顺序跑
  （`MAX_JOBS=1`）才用 `+p32 +setcpuaffinity`。详见 `run_all.sh` 头注释与顶层 `WORKFLOW.md`。
