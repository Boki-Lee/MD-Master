# MD 全流程手册（0–6 步骤）

> 从建模到分析，按 **0–6 编号**一步步走。目录索引见 `README.md`，交互协议见 `AGENTS.md`。
> 参考库：本 skill 根目录；示例模型：`models/cnt_crown/`。

---

## 0. 环境与首次自检（★ 第一次用这套 skill 先看这里）

### 0.1 一次性自检：先让技能认识这台机器

**NAMD 的线程数、要不要绑核、能开几路并发，全是机器相关的。** 文档里出现的具体数字
（`+p32`、`3 并发 × +p16` 之类）只是开发机（52 核 Xeon + RTX 4090）的实测值 ——
照抄到别的机器可能慢十倍，甚至因为绑核把多进程全钉到 CPU0 而假死。所以：

```bash
bash bench_namd.sh                   # ★ 首次使用跑一次（约 1~3 分钟），实测本机最优参数
bash bench_namd.sh --show            # 看现有配置 + 推荐命令
bash bench_namd.sh --print single    # 只打印一条可直接粘贴的 NAMD 命令
bash bench_namd.sh --retest          # 换机器 / 想复核 / 驱动变了 → 重测（旧配置自动备份）
bash bench_namd.sh --env             # 只看环境探测（CPU/内存/GPU/NAMD/VMD/Python），不跑基准
```

- 结果写进**全局记忆** `~/.config/md-master/machine.conf`（纯 `key=value`，可被 source）；
  全库脚本自动读它 —— **第一次测过之后不用每次都测**。
- 自检给出三件事：单进程命令（`+p` 多少、要不要 `+setcpuaffinity`）、并发路数×线程数
  （US 多窗口用）、分析脚本的并发 VMD 数（按内存缩放）。
- 原理：拿示例模型 `models/cnt_crown/1model/system_ion.*`（23045 原子、盒子从 PDB 的
  `CRYST1` 自动读）在各档参数下跑 5000 步，比较 NAMD 日志里的 `PERFORMANCE: ... ns/day`。
  **全程在 `mktemp -d` 临时目录里跑**，不写项目目录、不碰任何现存 conf。
- **没有可用 GPU 时直接报错退出、且不写配置**（CUDA 版 NAMD 离不开 `/dev/nvidia*`，见 §8 第 9 条）；
  如果手上是 multicore（非 CUDA）版 NAMD，用 `bash bench_namd.sh --cpu-only`。
- 换机器 / 换同事接手：跑一次 `bench_namd.sh` 就够，**不用改任何 conf 或脚本**。

### 0.2 软件路径（脚本自动探测，也可用环境变量覆盖）

| 软件 | 探测顺序 |
|---|---|
| VMD | `$VMD` → `PATH` 里的 `vmd` → `/usr/local/bin/vmd` |
| NAMD 3.0.1（推荐）/ NAMD 2.14 | `$NAMD` → `PATH` 里的 `namd3`/`namd2` → `~/Install/Namd/*/namd3` → `/opt`、`/usr/local/bin` |
| Python（分析 / 绘图 / WHAM） | `$PYTHON` → conda `MD` 环境 → `$CONDA_PREFIX/bin/python` → `PATH` 里的 `python3`（要求能 `import numpy`） |

- 实际取到的值都记在 `machine.conf`（`NAMD=` / `VMD=` / `PYTHON=`），`--show` 可见。
- 分析环境示例：`conda activate MD`，或直接用 `machine.conf` 里 `PYTHON` 的绝对路径。

### 0.3 NAMD 运行规矩（重要）

- **CUDA 编译版 NAMD 必须有 GPU 设备节点**（`/dev/nvidia*`）才能启动，否则
  `FATAL ERROR: CUDA error cudaGetDeviceCount` 段错误。
- **命令长这样**（并行参数用自检结果替换，`--print single` 可以直接抄）：
  ```bash
  cd 某目录 && namd3 +p32 +setcpuaffinity +devices 0 xxx.conf > xxx.log 2>&1
  ```
- 多进程并发（自由能 US 多窗口）**严禁 `+setcpuaffinity`**（会全钉到 CPU0，吞吐暴跌几十倍），
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
bash bench_namd.sh                            # ★ 首次：先测出本机最优并行参数（一次即可）
python3 0build/check_setup.py                 # ★ 先静态校验，全 PASS 再跑
cd 2min && namd3 +p32 +setcpuaffinity +devices 0 min.conf > min.log 2>&1   # 参数按自检结果
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
cd 4prod && nohup namd3 +p32 +setcpuaffinity +devices 0 prod.conf > prod.log 2>&1 &   # 参数按自检结果
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
#    窄量程（默认 windows.txt：±5 Å / 27 窗口）用 --zmax 6；
#    宽量程（windows_bulk_to_tube.txt：+12 → -6 / 47 窗口）才用 --zmax 12
cd 0build && ./run_build_us.sh --ion POT --zmax 6 --zmin -6
python3 check_setup_us.py                       # 通过再往下
# ② 平衡 1 ns + SMD 拉伸 1 ns（run_smd.sh 自动两步走：eq.conf -> smd.conf）
cd ../smd && ./run_smd.sh
# ③ 提取窗口构象
cd ../extract && ./run_extract.sh
# ④ 伞形采样（windows.txt 默认 27 窗口；宽量程方案见 windows_bulk_to_tube.txt）
cd ../us && ./setup_us.sh && ./run_all.sh
# ⑤ WHAM → PMF + 绘图
cd ../pmf && ./run_wham.sh && python plot_pmf.py
```

**只要改这几处**（详见 `free_energy/README.md`）：
离子种类/数量（`--ion POT/CAL/SOD`、`--nanion`）、z 范围（`--zmax/--zmin`）、
`us/windows.txt`（窗口中心+弹簧常数）、`smd.colvars.in`（拉速/弹簧）、
`smd/eq.conf`（平衡时长，默认 `run 500000` = 1 ns；想跳过平衡用 `SKIP_EQ=1 ./run_smd.sh`）。

> `smd/` 现在是**两步走**：`eq.conf` 先做 `minimize 5000` + 1 ns NVT，
> `smd.conf` 再用 `bincoordinates/binvelocities/extendedSystem` 从 `eq_output.*` 续跑。
> 两步由 `run_smd.sh` 串起来。**不要在两处都写 `minimize`。**
> 这样改的原因见 §8 第 7 条。

---

## 7. 步骤 6analysis —— 分析

```bash
bash analysis/calCurr.sh 2 100                 # 先试跑
nohup bash analysis/calCurr.sh 16 10000 &      # 正式并行（进程数看 machine.conf 的 ANALYSIS_JOBS）
conda activate MD                              # 分析环境示例（按机器改）
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
5. **NAMD 是 CUDA 版**：无 GPU 节点直接段错误。并行参数（`+p` 多少、要不要
   `+setcpuaffinity`、并发几路）**必须用 `bench_namd.sh` 在本机实测**，别照抄文档里的
   `+p32` —— 那只是开发机数值，换机器可能差十倍甚至假死（见 §0.1）。
6. **NAMD 3 别写 `stepsPerCycle` / `CUDASOAintegrate`**（见 §5）。
7. **用 `binvelocities` 续跑时，绝不能再写 `temperature`**。
   两者同时存在 NAMD 直接 `FATAL ERROR: Cannot specify both an initial temperature
   and a velocity file`，连一步都跑不了。`temperature` 的语义是"没给速度就按这个
   温度赋初速"，既然给了速度文件它就冲突。恒温改由 `langevin` + `langevinTemp`
   负责，与 `temperature` 无关，删掉那一行即可。
   （这是把 SMD 改成"从平衡产物续跑"时必然踩到的一步。）
8. **US 窗口清单里必须包含势垒中心那一个（通常是 `z=0.00`）**。
   势垒顶部又窄又陡，离子会被系统性推离孔心：实测 ±0.20 两个窗口的实测均值是
   ±0.43，`|z|<0.15` 只各采到 8 / 13 个样本，WHAM 在孔心输出 26 个 `NaN` 空洞，
   势垒高度只能靠两侧斜坡外推。**"靠相邻两个窗口覆盖峰顶"是靠不住的。**
   最阴的地方是：把窗口从 0.25 Å 间距改成 0.4 Å 均匀网格时，格点
   （-5.0 起步 → ……-0.2, +0.2……）恰好把 0.00 跳过去了 —— 是"优化"出来的 bug。
   **任何窗口清单，先确认势垒中心在列表里。**
9. **跑 MD 前先确认沙箱策略（dsh 特有）**：本机 GPU 设备节点 `/dev/nvidia*`
   只在 `danger-full-access` 下可见。默认的只读/`workspace-write` 沙箱里 `/dev`
   是精简版，`nvidia-smi` 报 "couldn't communicate with the NVIDIA driver"，
   NAMD 直接 `CUDA error cudaGetDeviceCount` 段错误；`mknod` 补节点也会被拒
   （无 CAP_MKNOD）。**不是配置错误，是权限，别去改 conf 排错。**

---

## 9. 物理陷阱（算结果时务必注意）

- **管外是并联通路**：盒子横截面远大于管子，实测总电流约 79% 走管外体相水、只有 21% 走管腔。
  研究通道输运必须用"管内/柱心"分量。
- **管壁两侧各有约 5 Å 离子排斥层**：用 r<13 Å 当"管内"会算出假的贫化 20%；
  必须用**柱心 (r<9 Å)** 对**远处本体 (r>22 Å)** 比较。
- solvate 水盒子只有 0.912 g/cm³，初始欠密正常，eq 会压回来。
- **冠醚孔 PMF 的交叉验证数据点**（CNT + 18-冠-6 侧壁孔，同力场同盒子）：
  Na⁺ 势垒 **17.8 kcal/mol**、K⁺ 势垒 **12.1 kcal/mol**（都以管外 z≈+5 Å 为参考点）。
  Na⁺ 高 5.8 kcal/mol —— 18-冠-6 空腔尺寸与 K⁺ 匹配最好，Na⁺ 偏小、与冠醚氧结合更弱，
  但电荷密度更高、脱水代价更大。**算别的离子时可以拿这个趋势做 sanity check：**
  碱金属在冠醚孔上的势垒应当 K⁺ < Na⁺（Li⁺ 更高）。若算出来反过来，先怀疑采样或坐标定义。
- **势垒必须落在孔心（z≈0）**：反应坐标是"离子 vs 孔环 6 个氧的质心"的 Z 差，
  势垒峰应落在 z=0 且左右大致对称。**峰位明显偏离 0（例如 -0.11）通常说明峰顶没采到**，
  是窗口清单漏了孔心窗口的典型症状（见 §8 第 8 条），不是物理效应。
- 轨迹文件很占地方：单条 20 ns 轨迹（2.3 万原子、1 万帧）约 2.8 GB，跑完注意清理/转存。

---

## 10. 排错速查表

| 现象 | 原因 / 处理 |
|---|---|
| `CUDA error cudaGetDeviceCount` 段错误 | 无 GPU 节点；确认 `/dev/nvidia*`，或用 `+devices 0` |
| `FATAL ERROR: ... unknown atom type OX` | 冠醚氧用了 `OS`；改成 `OX`，确认 `C_O.par` 有 `CA OX` |
| 水/碳管错开半个盒子 | `cellOrigin` 写成角点了；改成盒子中心 |
| B 字段文件读不进去 | B 文件与结构原子数/顺序不一致；用溶剂化后的模型生成 |
| 跑十几 ns 突然 `Atoms moving too fast` | 写死了 `stepsPerCycle`；删掉（NAMD 3 自动管） |
| `FATAL ERROR: Cannot specify both an initial temperature and a velocity file` | 用了 `binvelocities` 续跑又在 conf 里写了 `temperature`；删掉 `temperature` 行，恒温靠 `langevinTemp`（§8 第 7 条） |
| SMD 从平衡产物续跑却从头开始 / 能量突变 | 漏了 `bincoordinates`/`binvelocities`/`extendedSystem` 三行，或 `eq.conf` 没先跑；看 `eq_output.*` 在不在 |
| PMF 在势垒顶部出现 `NaN` 空洞、峰位偏离 z=0 | 窗口清单漏了势垒中心窗口；补 `z=0.00` 后重算 WHAM（不用重跑旧窗口，只有新窗口要跑）（§8 第 8 条） |
| PMF 曲线在窗口间距处周期性"锯齿"或空洞 | 相邻窗口 Δz 远大于 σ=√(RT/k)，直方图没重叠；加密窗口或统一弹簧常数（§6 与 `us/windows.txt` 顶部规则） |
| 多窗口 US 并发吞吐暴跌 | 多进程用了 `+setcpuaffinity`；去掉，单窗口才用绑核（并发参数看 machine.conf） |
| 脚本提示"未找到机器配置" | 这台机器还没自检：跑 `bash bench_namd.sh`（一次即可，之后全局记忆） |
| `import field_protocol` 失败 | `analysis/` 里漏了 `field_protocol.py`（公共依赖） |
| 电流算出"管内贫化" | 用 r<13 当管内了；改柱心 r<9 vs 本体 r>22 |

---

## 11. 命令速查

```bash
# 新建项目
bash new_project.sh /path/to/新项目 --with-prod --with-analysis

# 首次自检（只跑一次，结果全局记忆；换机器再来一次）
bash bench_namd.sh && bash bench_namd.sh --print single

# 跑 MD（NAMD 由你在终端启动；+p 与绑核按自检结果）
python3 0build/check_setup.py
cd 2min  && namd3 +p32 +setcpuaffinity +devices 0 min.conf  > min.log  2>&1
cd ../3eq && namd3 +p32 +setcpuaffinity +devices 0 eq.conf   > eq.log   2>&1
cd ../4prod && nohup namd3 +p32 +setcpuaffinity +devices 0 prod.conf > prod.log 2>&1 &

# 自定义力离线自检
tclsh forces/selftest_field.tcl [../3eq/eq.restart.xsc]

# 自由能（窄量程默认 ±5 Å：--zmax 6；宽量程用 --zmax 12 + windows_bulk_to_tube.txt）
cd 0build && ./run_build_us.sh --ion POT --zmax 6 --zmin -6
cd ../smd && ./run_smd.sh          # 内部：eq.conf 平衡 1 ns -> smd.conf 拉伸 1 ns
cd ../extract && ./run_extract.sh && cd ../us && ./setup_us.sh && ./run_all.sh
cd ../pmf && ./run_wham.sh && python plot_pmf.py

# 分析
conda activate MD                              # 分析环境示例，按机器改
bash analysis/calCurr.sh 16 10000 && python analysis/plot_iv.py
```

---

## 12. 项目结束后：存入参考库

跑完一个项目，想把它收进参考库时，说"**把这个存入参考库**"，按 `ARCHIVE.md` 走：

1. 分类问清存什么（新模型 / 新力 / 新分析 / 自由能改动 / 新力场参数 / 新踩坑）。
2. 只复制可复用件（脚本/conf/小数据），**大轨迹留在数据盘、README 记路径**。
3. 写说明、更新所有联动点（README 索引、`new_project.sh` 清单、各子库 README、本手册）。
4. 校验 + 确认。
5. **写变更日志**（必做）：`bash logs/log_change.sh 归档 "摘要" --files "改动文件" --source <项目路径>`。

> 铁律：**只要动了参考库（归档 or 直接改），就必须往 `logs/CHANGELOG.md` 追加一条带时间戳的记录。**
> 规则见 `AGENTS.md` §6，格式与清单见 `logs/README.md`。

机械复制可代劳：`bash archive_model.sh /路径/项目 models/新模型名`。完整流程与"那些要改"清单见 `ARCHIVE.md`。
