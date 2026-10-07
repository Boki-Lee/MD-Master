# MD 参考库（0–6 分步工作流）

本目录是**统一 MD 参考库**：按 **0–6 步骤编号**组织，整合了 CNT 离子输运项目与
伞形采样自由能项目里**已跑通**的脚本、力场、踩坑经验。

> **每次开始 MD 前**，先说"我要开始 MD"，我会按 `AGENTS.md` 里的逐步协议先问清楚
> 做哪一段（只建模 / 加力生产 / 自由能 / 只分析），再一步一步来、每步双重确认。

---

## 一、目录索引（每个文件/文件夹是什么）

```
MD-Master/
│
├── AGENTS.md                 ★ 会话工作流协议：说"我要开始MD"后怎么一步步问、一步步做
├── README.md                 ★ 本文件：目录索引
├── WORKFLOW.md               ★ 0–6 全流程手册（命令 + 踩坑 + 排错速查）
├── ARCHIVE.md                ★ 项目结束后「存入参考库」的归档流程 + 联动清单
├── new_project.sh            ★ 一键搭新项目骨架（--with-prod / --with-free-energy / --with-analysis）
├── archive_model.sh          ★ 归档辅助：把跑完的项目复制成新模型（排除大轨迹）
│
├── forcefield/               力场母版（复制给每个模型用）
│   ├── C_O.par               冠醚关键：定义 CA-OX 键/角参数（★冠醚氧类型必须是 OX）
│   ├── par_all36_prot.prm / par_all36_lipid.prm / par_all36_na.prm   CHARMM36 蛋白质/脂/核酸参数
│   ├── par_water_ions_na.prm  水 + Na+/Cl- 参数
│   └── toppar_all36_dphpc.str  拓扑（脂）
│
├── models/                   按模型建的子文件夹，每个含 0–3（+自由能用建模脚本）
│   └── cnt_crown/            示例模型（已跑通：CNT (23,23) + 18-冠-6，0.6 M KCl）
│       ├── README.md         该模型参数（盒子/原子数/离子）+ 照抄方法
│       ├── forcefield/       复制好的力场（自包含）
│       ├── 0build/           建模脚本（标准 + 自由能 US 建模）
│       │   ├── build_cnt_crown.tcl / run_build.sh   标准建模（CNT+冠醚+溶剂化+加离子）
│       │   ├── check_setup.py                        标准流水线静态校验
│       │   ├── make_bfactor_pdbs.tcl                 给已有体系补 B 字段文件
│       │   ├── build_us_system.tcl / run_build_us.sh / check_setup_us.py   自由能(5) US 建模
│       ├── 1model/           建模产物（MD 起点）
│       │   ├── system_combined/solv/ion.psf+pdb      建模/溶剂化/加离子三级产物
│       │   ├── cnt_restrain.pdb / cnt_langevin.pdb   B 字段约束/恒温文件
│       │   ├── ion_ids.dat                           离子 ID（0-based）+ 电荷
│       │   └── system_solv.log                       溶剂化日志（记着盒子 -minmax）
│       ├── 2min/  min.conf   能量最小化 + 短 MD
│       └── 3eq/   eq.conf    NPT 平衡（续算 ../2min/min）
│
├── forces/                   步骤4：各种自定义力(tcl)写法参考
│   ├── README.md             每种力用途/参数/如何新写
│   ├── field_axial_tri.tcl   轴向三角波电压（入门范例）
│   ├── field_axial_dc_radial_tri.tcl   轴向DC + 径向三角波（进阶范例，注释最全）
│   ├── selftest_field.tcl    离线自检（tclsh 跑，不需 NAMD）
│   └── _template.tcl         新力写法骨架（照抄改三块）
│
├── free_energy/              步骤5：自由能模板（US/SMD+WHAM）
│   ├── README.md             全链说明 + "只改几处"清单
│   ├── smd/     smd.conf + smd.colvars.in + run_smd.sh       SMD 拉伸
│   ├── extract/ extract.tcl + run_extract.sh                 提取窗口构象
│   ├── us/      template.conf + windows.txt + setup_us.sh + run_all.sh   伞形采样
│   └── pmf/     wham.py + run_wham.sh + plot_pmf.py          WHAM + 绘图
│
└── analysis/                 步骤6：提取数据 + 绘图脚本库
    ├── README.md             每个脚本算什么、怎么用
    ├── field_protocol.py     公共依赖（协议参数 + 波形 + DCD/盒子自动探测）
    ├── calCurr.sh / ion-cur.tcl              并行算电流
    ├── plot_iv.py                            I-V 回线 + 轴向直流工作点
    ├── plot_currents.py                      分区电流（管腔/管壁/管外）
    └── plot_concentration.py                分区离子浓度
```

---

## 二、步骤编号（本库唯一约定）

| 编号 | 含义 | 必做 |
|---|---|---|
| 0build | 编写建模文件 | ✔ |
| 1model | 存放建好的模型 | ✔ |
| 2min | 能量最小化 + 存跑后文件 | ✔ |
| 3eq | 平衡（min 之后）+ 存跑后文件 | ✔ |
| 4prod | 生产模拟（各种 tcl 自定义力） | 与 5 二选一 |
| 5 | 自由能计算（SMD→提取→US→WHAM） | 与 4 二选一 |
| 6analysis | 提取数据 / 绘图 | 每次单独写 |

> `free_energy/` 里的 `smd/extract/us/pmf` 是**步骤 5 的子步骤**，不是顶层编号。
> 自由能建模复用 `models/<name>/0build` 与 `1model`（同一套建模，不另开目录）。

---

## 三、怎么用

### 新建一个模型/项目

```bash
bash new_project.sh /mnt/data2/.../新项目 --with-prod --with-analysis
# 或跑自由能：bash new_project.sh /mnt/data2/.../新项目 --with-free-energy
```

生成骨架 + 力场 + 建模脚本 + `README.md` + `TODO.md`，然后按 `TODO.md` 走。

### 照抄示例模型

`models/cnt_crown/` 是完整跑通样板：改 `0build/build_cnt_crown.tcl` 头部参数 →
`./run_build.sh` → 写 `2min/min.conf` → 跑 → `3eq`。

### 加自定义力 / 自由能 / 分析

分别到 `forces/`、`free_energy/`、`analysis/` 里取模板，各 README 写明"哪些地方要改"。

---

## 四、两条铁律

1. **NAMD 由你在终端启动**：我只负责写 conf、跑静态校验、把命令写好交给你；正式长跑你自己敲。
   我可在你授权后做几秒冒烟测试验证能否启动。
2. **每步双重确认**：0→1→2→3→(4|5)→6，每步完成后问一次、你通过后我校验再问一次，
   你两次都说"通过"才继续下一步（见 `AGENTS.md`）。

> 详细流程、坑与排错见 `WORKFLOW.md`；交互协议见 `AGENTS.md`。
