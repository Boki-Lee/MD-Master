# CHANGELOG —— 参考库变更日志

> **本文件只增不改（append-only）**：每一条都是历史，写错了就再追加一条「更正」，不要回头删旧条目。
> 规则见 `logs/README.md`，也写进了顶层 `AGENTS.md`（§6 变更日志规则）。
>
> 记录范围：**① 归档入库（`ARCHIVE.md` 流程）　② 用户直接让我改库**
> 时间戳格式：`YYYY-MM-DD HH:MM:SS +0800`

---

## 2026-10-08 20:50:36 +0800 — [规则] 新增「变更日志」铁律：入库/改库必带时间戳记 logs/CHANGELOG.md

- **时间**：2026-10-08 20:50:36 +0800
- **类型**：规则
- **改动文件**：
  - logs/CHANGELOG.md
  - logs/README.md
  - logs/log_change.sh
  - AGENTS.md
  - ARCHIVE.md
  - README.md
  - WORKFLOW.md
- **说明**：
  新建 logs/ 目录（CHANGELOG.md + log_change.sh + README.md）；AGENTS.md 新增 §6 并把「写日志」写进 §1 触发；ARCHIVE.md 由 6 步改 7 步、联动清单加一行、两个示例补第 7 步；README.md 索引加 logs/ 条目、铁律由两条改三条；WORKFLOW.md §12 加第 5 步和铁律提示。范围：归档入库 + 用户直接改库；不含 new_project.sh 建的项目骨架；纯只读操作不记。

## 2026-10-08 20:50:47 +0800 — [修复] 对齐 logs/ 文件权限到库内惯例（md=644, sh=755）

- **时间**：2026-10-08 20:50:47 +0800
- **类型**：修复
- **改动文件**：
  - logs/CHANGELOG.md
  - logs/README.md
  - logs/log_change.sh
- **说明**：
  新建文件默认 600/711，与库内其他文档(644)和脚本(755)不一致，统一之。

## 2026-10-08 20:56:08 +0800 — [规则] 把「归档触发 + 改库必记日志」同步到全局 ~/.dsh/AGENTS.md，任何工作区都生效

- **时间**：2026-10-08 20:56:08 +0800
- **类型**：规则
- **改动文件**：
  - /home/dell/.dsh/AGENTS.md（沙箱外，越权写入）
- **说明**：
  新增全局第 6 节：6.1 归档触发词（存入参考库/归档/存库 → 按 ARCHIVE.md 走）；6.2 动了参考库任何文件都必须写 logs/CHANGELOG.md，含改规则本身；明确不记 new_project.sh 建的项目骨架与纯只读操作。原因：全局文件原先完全没有归档/日志字样，在别的文件夹说归档时规则加载不到。

## 2026-10-08 21:03:46 +0800 — [修改] 技能同步参考库 2026-10-08 改动（SMD 两步走 + US 双窗口清单 + PMF --bulk-z + logs 台账）

- **时间**：2026-10-08 21:03:46 +0800
- **类型**：修改
- **来源项目**：/home/dell/LBJ/WORKFLOW
- **改动文件**：
  - logs/CHANGELOG.md
  - logs/README.md
  - logs/log_change.sh
  - AGENTS.md
  - ARCHIVE.md
  - README.md
  - WORKFLOW.md
  - new_project.sh
  - SKILL.md
  - free_energy/README.md
  - free_energy/smd/eq.conf
  - free_energy/smd/run_smd.sh
  - free_energy/smd/smd.conf
  - free_energy/smd/smd.colvars.in
  - free_energy/pmf/plot_pmf.py
  - free_energy/us/windows.txt
  - free_energy/us/windows_bulk_to_tube.txt
  - free_energy/us/setup_us.sh
  - free_energy/us/template.conf
  - models/cnt_crown/0build/build_us_system.tcl
- **说明**：
  把参考库 2026-10-08 的变动同步进 MD-Master 技能：① SMD 改为两步走，新增平衡阶段 free_energy/smd/eq.conf（minimize 5000 + 1 ns NVT，离子三维钉死），run_smd.sh 串起 eq→smd 并支持 SKIP_EQ/断点续跑，smd.conf 改从 eq_output.coor/.vel/.xsc 续跑（删 temperature/minimize/reinitvels）；② US 拆成两份窗口清单——windows.txt 改窄量程 ±5 Å/27 窗口（默认、含孔心 0.00），新增 windows_bulk_to_tube.txt 宽量程 47 窗口；③ plot_pmf.py 新增 --bulk-z 体相参考点参数；④ 新增 logs/ 变更台账系统（CHANGELOG.md + log_change.sh + README.md）及 AGENTS.md §6、ARCHIVE.md 7 步、README/WORKFLOW 联动；⑤ 文档内 /home/dell/LBJ/WORKFLOW 自引用改为可移植写法，new_project.sh 注释同步上游措辞。
