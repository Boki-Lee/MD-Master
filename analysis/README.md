# analysis/ —— 步骤 6 提取数据 + 绘图脚本库

分析脚本**已做自动探测**（DCD 原子数/帧长/坐标块偏移、盒子尺寸、协议波形全部自动识别），
换新体系通常只需改脚本顶部/命令行参数，不用改任何常量。

> **步骤 6 每次单独写**：下面这组脚本面向「离子输运 + 电场」的电流/I-V/浓度分析，
> 是**菜单 + 模板**。要算的东西不一样时（比如 PMF 用 `free_energy/pmf/`，
> 别的量度再按需新增脚本），按这里的样子新写一个，不要改坏通用脚本。

## 文件清单

| 文件 | 算什么 | 前置 |
|---|---|---|
| `calCurr.sh` | 并行算电流（VMD/Tcl，分径向/轴向/分区） | 有 `../4prod/prod.dcd` |
| `ion-cur.tcl` | 电流计算核心（`calCurr.sh` 调用） | — |
| `field_protocol.py` | **公共依赖**：协议参数 + 波形 + DCD/盒子自动探测（被三个 plot 脚本 import） | — |
| `plot_iv.py` | 径向 V-I 回线 + 轴向直流工作点（新协议） | `calCurr.sh` 产出 |
| `plot_currents.py` | 分区电流（管腔/管壁/管外）时间序列与占比 | `calCurr.sh` 产出 |
| `plot_concentration.py` | 各区域离子浓度（径向/时间/z/电压） | `calCurr.sh` 产出 |

## 快速上手

```bash
cd <项目>/analysis
bash calCurr.sh 2 100          # 先小规模试跑（2 并行 × 100 段）
nohup bash calCurr.sh 16 10000 &   # 正式并行（16 并行 × 10000 段）

conda activate MD
python plot_iv.py               # I-V 回线
python plot_currents.py         # 分区电流
python plot_concentration.py    # 分区浓度
```

## 要改的参数

改协议/盒子/管半径时，统一在 `field_protocol.py` 顶部（其余脚本 import 它）：

| 参数 | 含义 |
|---|---|
| `AXIAL_MODE` | 轴向波形：`const`（恒定直流）/ `tri`（三角波扫描） |
| `V_AXIAL` / `AXIAL_PERIOD` / `AXIAL_VMAX` | 轴向电压 / 周期 / 峰值 |
| `VMAX_RAD` / `PERIOD_RAD` / `TRI_BIPOLAR` | 径向三角波峰值 / 周期 / 是否双极性 |
| `R_IN` / `TUBE_R` | 径向 1/r 内参考半径 / 管半径 |
| `SHELL_RADII` | 径向电流统计柱面（默认 `(9.0, 15.58, 22.0)` = 柱心/管壁/管外） |

> **协议一致性**：`field_protocol.py` 里这些值要和 `4prod` 里实际跑的 tcl 脚本一致；
> 更稳的办法是让 `4prod` 把波形写进 `field_log.dat`，脚本默认优先读它。

## 路径约定（脚本内已写死相对路径）

| 数据 | 路径（相对 `analysis/`） |
|---|---|
| 轨迹 | `../4prod/prod.dcd` |
| 离子列表 | `../1model/ion_ids.dat`（0-based ID） |
| 盒子/管轴 | `../3eq/eq.restart.xsc` |
| 实际波形 | `../4prod/field_log.dat`（有则优先） |

> 也可用命令行覆盖：各 plot 脚本带 `--dcd / --ionfile / --xsc` 等参数，见各自 `--help`。

## 已知物理陷阱（算结果时务必注意）

- 总电流里**管外是并联通路**，测通道输运要用"管内/柱心"分量。
- 管壁两侧各有约 5 Å **离子排斥层**：算浓度要拿柱心（r<9 Å）对远处本体（r>22 Å）比，
  拿 r<13 Å 当"管内"会得到假的贫化。
- 详见顶层 `WORKFLOW.md`。
