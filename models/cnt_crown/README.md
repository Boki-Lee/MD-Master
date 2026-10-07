# models/cnt_crown —— 示例模型：CNT + 18-冠-6 孔道

已跑通的标准 MD 模型，用作**照抄样板**。新模型复制这个目录、改 `0build/` 头参数即可。

## 体系参数

| 项目 | 值 |
|---|---|
| 体系 | 碳纳米管 (23,23) armchair + 18-冠-6 孔道（石墨烯晶格上雕刻） |
| 手性 / 管长 | CNT_N=CNT_M=23，管长 8.0 nm |
| 孔 | 4 圈 × 3 孔，冠醚氧原子类型 **OX**（不是 OS） |
| 总原子数 | 23045 |
| 溶剂 | TIP3P 水 + **0.6 M KCl**（76 K⁺ / 76 Cl⁻，离子 ID 见 `1model/ion_ids.dat`） |
| 盒子 | 51.152 × 51.144 × 99.822 Å³，中心 (0, 0, 39.911) |
| 力场 | CHARMM36 + 自建 `C_O.par`（CA-OX 键/角参数，冠醚关键） |

## 目录（对应 0–6 步骤里的 0–3）

```
cnt_crown/
├── forcefield/    力场 6 文件（自包含，可独立跑）
├── 0build/        建模脚本
│   ├── build_cnt_crown.tcl / run_build.sh   标准建模（CNT+冠醚+溶剂化+加离子）
│   ├── check_setup.py                       标准流水线静态校验（跑 2min 前必跑）
│   ├── make_bfactor_pdbs.tcl                给已有体系补 B 字段文件
│   ├── build_us_system.tcl / run_build_us.sh / check_setup_us.py  自由能(5)用 US 建模
├── 1model/        建模产物（MD 起点）
│   ├── system_combined/solv/ion.psf+pdb     建模/溶剂化/加离子三级产物
│   ├── cnt_restrain.pdb / cnt_langevin.pdb  B 字段约束/恒温文件
│   ├── ion_ids.dat                          离子 ID（0-based）+ 电荷
│   └── system_solv.log                      溶剂化日志（记着盒子 -minmax，填 cellOrigin 用）
├── 2min/          min.conf   能量最小化 + 短 MD
└── 3eq/           eq.conf    NPT 平衡（从 2min 续算）
```

## 相对路径约定（conf 里已写死）

| 文件 | 引用 |
|---|---|
| `2min/min.conf` | `../1model/system_ion.psf/.pdb`、`../1model/cnt_*.pdb`、`../forcefield/*` |
| `3eq/eq.conf` | 续算 `../2min/min`；结构/力场同上 |
| 后续 `4prod/prod.conf` | 续算 `../3eq/eq`；力脚本见 `forces/` |
| 后续 `smd/us`（自由能） | `../1model/*`、`../forcefield/*` |

## 怎么照抄到新模型

1. 复制整个 `cnt_crown/` 为新目录（或 `new_project.sh` 生成骨架后填）。
2. 改 `0build/build_cnt_crown.tcl` 头部参数：`CNT_N/CNT_M`、`CNT_LENGTH_NM`、
   `PORE_RINGS/PORE_PER_RING`、`ION_CONC/ION_CATION/ION_ANION`。
3. `cd 0build && ./run_build.sh`，产物写入 `../1model/`。
4. 用 `make_bfactor_pdbs.tcl` 生成 B 字段文件；记录 `system_solv.log` 里的 `-minmax`。
5. 改 `2min/min.conf` 的 `cellBasisVector*/cellOrigin`（**cellOrigin = 盒子中心**）。
6. `python3 0build/check_setup.py` 通过后再跑 2min → 3eq。

> 完整流程、坑与排错见顶层 `WORKFLOW.md`。
