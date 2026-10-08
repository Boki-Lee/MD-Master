---
name: MD-Master
description: 分子动力学（MD）全流程技能与参考库：NAMD/VMD 建模→最小化→平衡→生产模拟（自定义力/电场）→自由能（平衡→SMD→US→WHAM）→分析绘图；覆盖 CNT+冠醚孔道离子输运，含力场、示例模型、踩坑与排错速查。当用户要开始/跑 MD、NAMD 建模、加电场生产、算自由能 PMF、分析电流/I-V，或说"我要开始 MD / 开始 MD / 跑 MD / 建模 / 归档 / 存库"时加载。Complete NAMD/VMD molecular-dynamics workflow (0–6 steps) skill and reference library.
---

# MD-Master —— MD 全流程参考库技能（0–6 步）

本技能是一套**已跑通的分子动力学（NAMD/VMD）参考库**：把建模 → 最小化 → 平衡 →
生产模拟（自定义力/电场）→ 自由能（平衡 → SMD → 提取 → US → WHAM）→ 分析绘图，
按 0–6 步骤编号组织好，并沉淀了力场、示例模型、踩坑记录与排错速查表。

> 本技能镜像自 MD 参考库；每次同步/改动的记录见 `logs/CHANGELOG.md`。

## 触发与用法

- 用户说 **“我要开始 MD / 开始 MD / 跑 MD”** → 按 `AGENTS.md` 的逐步交互协议走：
  **先问本次做哪一段**（只建模 / 加力生产 / 自由能 / 只分析 / 完整跑），不凭经验假设；
  每步完成后**双重确认**（报告→用户通过→校验→再确认→才继续）。
- 用户说 **“存入参考库 / 归档 / 存库”** → 按 `ARCHIVE.md` 的归档流程走。
- 换新体系 / 新项目 → 先 `bash new_project.sh <路径> [--with-prod] [--with-free-energy] [--with-analysis]`
  搭骨架，再照 `models/cnt_crown/` 示例改参数。

## 文件路由表

| 用户要做的 | 先读 |
| --- | --- |
| 了解本库有什么 / 目录索引 | `README.md` |
| 开始 MD 的交互协议（逐步问、双重确认） | `AGENTS.md` |
| 0–6 全流程手册：命令 + 踩坑 + 排错速查 + 物理陷阱 | `WORKFLOW.md` |
| 项目跑完，把可复用部分收进参考库 | `ARCHIVE.md` |
| 一键搭新项目骨架 | `new_project.sh` |
| 归档跑完的项目成新模型 | `archive_model.sh` |
| 力场参数（CHARMM36 / 冠醚 C_O.par / 水离子） | `forcefield/` |
| 建模 / 加离子 / B 字段 / 静态校验脚本 | `models/cnt_crown/0build/` |
| 建好的示例模型（照抄改参数） | `models/cnt_crown/` |
| 步骤 4：自定义力（电场）写法与离线自检 | `forces/` |
| 步骤 5：自由能（平衡→SMD→提取→US→WHAM） | `free_energy/` |
| 步骤 6：提取电流 / 绘图（I-V、分区电流、浓度） | `analysis/` |
| 入库/改库后写变更日志（只增不改） | `logs/CHANGELOG.md`（用 `logs/log_change.sh` 追加） |

## 路径约定（重要）

- 脚本用 `$0` 相对定位（`new_project.sh` 内 `REF="$(cd "$(dirname "$0")" && pwd)"`），
  **本库搬到任何位置都能用**，不要依赖固定绝对路径。
- 本机专属路径（`namd3`、`python`、conda `MD` 环境）在 `WORKFLOW.md` §0 是**示例默认值**，
  换机器时按实际环境覆盖对应变量 / 常量。

## 三条铁律

1. **NAMD 长跑由用户在终端启动**：只负责写 conf、跑静态校验、把完整命令行交给用户；
   除非用户明确授权，绝不擅自起长跑。
2. **每步双重确认**：0→1→2→3→(4|5)→6，每步完成后问一次、通过后校验再问一次，
   两次都“通过”才继续下一步。
3. **入库/改库必记日志**：归档或对库内文件增删改，收尾往 `logs/CHANGELOG.md` 追加一条
   带时间戳记录（`bash logs/log_change.sh <类型> <摘要> ...`），只增不改。
