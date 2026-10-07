# MD 全流程手册（0–6 步骤）

> 从建模到分析，按 **0–6 编号**一步步走。目录索引见 `README.md`，交互协议见 `AGENTS.md`。
> 参考库：本 skill 根目录；示例模型：`models/cnt_crown/`。

---

## 0. 环境（一次性，本机已配好）

| 软件 | 路径 |
|---|---|
| VMD | `/usr/local/bin/vmd`（1.9.4a57，插件在 `/usr/local/lib/vmd/plugins/noarch/tcl/`） |
| NAMD 3.0.1 | `/home/dell/Install/Namd/NAMD_3.0.1_Linux-x86_64-multicore-CUDA/namd3`（**推荐**） |
| NAMD 2.14 | 同目录下 `NAMD_2.14_.../namd2`（备用） |
| conda | `/home/dell/anaconda3`（分析用 `MD` 环境） |

```bash
conda activate MD              # 做分析/绘图用它
```

### NAMD 运行规矩（重要）

- **两个 NAMD 都是 CUDA 编译版**：必须有 GPU 设备节点（`/dev/nvidia*`）才能启动，
  否则 `FATAL ERROR: CUDA error cudaGetDeviceCount` 段错误。
- **标准命令**（本机实测最优，+p40 以上急剧恶化，别开满 52 核）：
  ```bash
  cd 某目录 && namd3 +p32 +setcpuaffinity +devices 0 xxx.conf > xxx.log 2>&1
  ```
- 多进程并发（自由能 US 多窗口）**严禁 `+setcpuaffinity`**（会全钉到 CPU0，吞吐暴跌 50 倍），
  只有单窗口顺序跑才用绑核。见 `free_energy/us/run_all.sh` 头注释。
- **NAMD 3 已弃用 `CUDASOAintegrate`**；检测到 GPU 自动启用 GPU-resident。
  `CUDASOAintegrate on` 只应写在 NAMD 2 配置里。

---

## 1. 目录约定（七文件夹 + 自由能子步骤）

```
新项目/
├── forcefield/   力场 6 文件
├── 0build/       ① 建模脚本
├── 1model/       ② 建模产物（MD 输入全在这里）
├── 2min/         ③ 能量最小化      min.conf
├── 3eq/          ④ NPT 平衡        eq.conf
├── 4prod/        ⑤ 生产模拟        prod.conf + 力脚本        （与自由能二选一）
├── smd/ extract/ us/ pmf/           自由能子步骤            （与 4prod 二选一）
└── analysis/     ⑥ 分析脚本
```

**跨文件夹相对路径**（conf/脚本里就写这些）：

| 文件 | 引用 |
|---|---|
| `2min/min.conf` | `../1model/system_ion.psf/.pdb`、`../1model/cnt_*.pdb`、`../forcefield/*` |
| `3eq/eq.conf` | 续算 `../2min/min`；结构/力场同上 |
| `4prod/prod.conf` | 续算 `../3eq/eq`；力脚本 `../4prod/xxx.tcl` |
| `smd`/`us` conf | `../1model/*`、`../forcefield/*` |
| `analysis/*` | `../4prod/prod.dcd`、`../1model/ion_ids.dat`、`../3eq/eq.restart.xsc` |

---

## 2. 步骤 0build —— 建模

1. 改 `0build/build_cnt_crown.tcl` 头部参数：
   `CNT_N/CNT_M`（手性）、`CNT_LENGTH_NM`（管长）、`PORE_RINGS/PORE_PER_RING`（孔）、
   `ION_CONC`（盐浓度）、`ION_CATION/ION_ANION`。
2. `cd 0build && ./run_build.sh`，产物写 `../1model/`。
3. 用 `make_bfactor_pdbs.tcl` 给体系补 B 字段文件（`cnt_restrain.pdb` / `cnt_langevin.pdb`）。
4. 生成 `1model/ion_ids.dat`（0-based ID + 电荷，用 VMD `$ions get index`）。
5. 记录盒子：`cat 1model/system_solv.log`（`-minmax` 值，填 cellOrigin 用）。

---

## 3. 步骤 1model —— 建模产物

MD 起点都在这里：`system_ion.psf/pdb`（溶剂化+离子）、`cnt_restrain.pdb`、`cnt_langevin.pdb`、`ion_ids.dat`。

---

## 4. 步骤 2min / 3eq —— 最小化 / 平衡

照抄 `models/cnt_crown/` 的 `min.conf` / `eq.conf`，改这几处：

- `structure` / `coordinates` → `../1model/system_ion.psf/.pdb`
- **`cellOrigin` = solvate 盒子中心**（例：minmax z = −10 ~ 89.822，则 cellOrigin z = 39.911）
- `langevinFile` / `consref` / `conskfile` → `../1model/cnt_*.pdb`
- `parameters` → `../forcefield/*`

```bash
python3 0build/check_setup.py                 # ★ 先静态校验，全 PASS 再跑
cd 2min && namd3 +p32 +setcpuaffinity +devices 0 min.conf > min.log 2>&1
grep "PERIODIC CELL CENTER" min.log           # ★ 确认盒子中心对不对
cd ../3eq && namd3 +p32 +setcpuaffinity +devices 0 eq.conf > eq.log 2>&1
```

---

## 5. 步骤 4prod —— 生产模拟（加自定义力）

1. 挑一个 `forces/` 里的力脚本复制进 `4prod/`，或照 `_template.tcl` 新写。
2. `prod.conf` 里写：

```tcl
tclForces        on
tclForcesScript  field_axial_tri.tcl
```

3. `prod.conf` 续算 `../3eq/eq`，结构/力场同上。
4. **改完先离线自检**：`tclsh selftest_field.tcl ../3eq/eq.restart.xsc`。

```bash
cd 4prod && nohup namd3 +p32 +setcpuaffinity +devices 0 prod.conf > prod.log 2>&1 &
```

**prod.conf 两条禁忌**：
- 不要写 `CUDASOAintegrate`（NAMD 3 弃用）。
- ★★ **不要写 `stepsPerCycle`**：NAMD 3 GPU-resident 自己管原子迁移，写死会跑十几 ns 后突然
  `Low global CUDA exclusion count!` + `Atoms moving too fast` 崩溃（看似物理失稳，其实不是）。
  `margin` 用默认 4 即可。

**写力的关键**（详见 `forces/_template.tcl` 与 `field_axial_dc_radial_tri.tcl` 头注释）：
拿坐标要先 `addatom` 登记再 `loadcoords`；热路径内联不调 proc；跨周期用最小镜像；
`1/r` 场在 r→0 要截断；力要有界别 NaN。

---

## 6. 步骤 5 —— 自由能（US/SMD + WHAM）

建模复用 `models` 的 0build/1model（同一套，不另开目录）：

```bash
# ① US 建模（旋转孔 + 溶剂化 + 加离子，产物进 1model/）
cd 0build && ./run_build_us.sh --ion POT --zmax 12 --zmin -6
python3 check_setup_us.py                       # 通过再往下
# ② SMD 拉伸 1 ns
cd ../smd && ./run_smd.sh
# ③ 提取窗口构象
cd ../extract && ./run_extract.sh
# ④ 伞形采样（47 窗口）
cd ../us && ./setup_us.sh && ./run_all.sh
# ⑤ WHAM → PMF + 绘图
cd ../pmf && ./run_wham.sh && python plot_pmf.py
```

**只要改这几处**（详见 `free_energy/README.md`）：
离子种类/数量（`--ion POT/CAL/SOD`、`--nanion`）、z 范围（`--zmax/--zmin`）、
`us/windows.txt`（窗口中心+弹簧常数）、`smd.colvars.in`（拉速/弹簧）。

---

## 7. 步骤 6analysis —— 分析

```bash
bash analysis/calCurr.sh 2 100                 # 先试跑
nohup bash analysis/calCurr.sh 16 10000 &      # 正式并行
conda activate MD
python analysis/plot_iv.py
python analysis/plot_currents.py
python analysis/plot_concentration.py
```

改 `analysis/field_protocol.py` 顶部协议参数（`AXIAL_MODE`/`V_*`/`SHELL_RADII`/`TUBE_R`）。
**要算的东西不一样时，单独新写脚本**，不改坏通用脚本。

---

## 8. 已知坑（务必记住）

1. **`cellOrigin` 是盒子中心，不是角点**。盒子不居中时 NAMD 包裹输出会把水/碳管错开半个盒子，
   看起来像"碳管一半没在水里"。自检：`grep "PERIODIC CELL CENTER" xxx.log`。
2. **冠醚氧原子类型是 `OX`，不是 `OS`**。`forcefield/C_O.par` 定义的是 `CA-OX`，用错会缺参数。
3. **B 字段文件必须与结构原子数、顺序完全一致**（`cnt_restrain.pdb`/`cnt_langevin.pdb`），
   用未溶剂化模型生成会导致 NAMD 拒绝读取。
4. **PDB 原子名对齐到标准列（第 14 列）**，左对齐会让部分工具误读元素。
5. **NAMD 是 CUDA 版**：无 GPU 节点直接段错误，`+p32 +setcpuaffinity +devices 0` 是实测最优。
6. **NAMD 3 别写 `stepsPerCycle` / `CUDASOAintegrate`**（见 §5）。

---

## 9. 物理陷阱（算结果时务必注意）

- **管外是并联通路**：盒子横截面远大于管子，实测总电流约 79% 走管外体相水、只有 21% 走管腔。
  研究通道输运必须用"管内/柱心"分量。
- **管壁两侧各有约 5 Å 离子排斥层**：用 r<13 Å 当"管内"会算出假的贫化 20%；
  必须用**柱心 (r<9 Å)** 对**远处本体 (r>22 Å)** 比较。
- solvate 水盒子只有 0.912 g/cm³，初始欠密正常，eq 会压回来。
- 数据盘 `/mnt/data2` 已用 96%，单条 20 ns 轨迹（2.3 万原子 1 万帧）约 2.8 GB，注意清理。

---

## 10. 排错速查表

| 现象 | 原因 / 处理 |
|---|---|
| `CUDA error cudaGetDeviceCount` 段错误 | 无 GPU 节点；确认 `/dev/nvidia*`，或用 `+devices 0` |
| `FATAL ERROR: ... unknown atom type OX` | 冠醚氧用了 `OS`；改成 `OX`，确认 `C_O.par` 有 `CA OX` |
| 水/碳管错开半个盒子 | `cellOrigin` 写成角点了；改成盒子中心 |
| B 字段文件读不进去 | B 文件与结构原子数/顺序不一致；用溶剂化后的模型生成 |
| 跑十几 ns 突然 `Atoms moving too fast` | 写死了 `stepsPerCycle`；删掉（NAMD 3 自动管） |
| 多窗口 US 并发吞吐暴跌 | 多进程用了 `+setcpuaffinity`；去掉，单窗口才用绑核 |
| `import field_protocol` 失败 | `analysis/` 里漏了 `field_protocol.py`（公共依赖） |
| 电流算出"管内贫化" | 用 r<13 当管内了；改柱心 r<9 vs 本体 r>22 |

---

## 11. 命令速查

```bash
# 新建项目
bash new_project.sh /mnt/data2/.../新项目 --with-prod --with-analysis

# 跑 MD（NAMD 由你在终端启动）
python3 0build/check_setup.py
cd 2min  && namd3 +p32 +setcpuaffinity +devices 0 min.conf  > min.log  2>&1
cd ../3eq && namd3 +p32 +setcpuaffinity +devices 0 eq.conf   > eq.log   2>&1
cd ../4prod && nohup namd3 +p32 +setcpuaffinity +devices 0 prod.conf > prod.log 2>&1 &

# 自定义力离线自检
tclsh forces/selftest_field.tcl [../3eq/eq.restart.xsc]

# 自由能
cd 0build && ./run_build_us.sh --ion POT && cd ../smd && ./run_smd.sh
cd ../extract && ./run_extract.sh && cd ../us && ./setup_us.sh && ./run_all.sh
cd ../pmf && ./run_wham.sh && python plot_pmf.py

# 分析
conda activate MD
bash analysis/calCurr.sh 16 10000 && python analysis/plot_iv.py
```

---

## 12. 项目结束后：存入参考库

跑完一个项目，想把它收进参考库时，说"**把这个存入参考库**"，按 `ARCHIVE.md` 走：

1. 分类问清存什么（新模型 / 新力 / 新分析 / 自由能改动 / 新力场参数 / 新踩坑）。
2. 只复制可复用件（脚本/conf/小数据），**大轨迹留在数据盘、README 记路径**。
3. 写说明、更新所有联动点（README 索引、`new_project.sh` 清单、各子库 README、本手册）。
4. 校验 + 确认。

机械复制可代劳：`bash archive_model.sh /路径/项目 models/新模型名`。完整流程与"那些要改"清单见 `ARCHIVE.md`。
