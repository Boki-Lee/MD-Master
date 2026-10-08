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

## 2026-10-08 22:20:22 +0800 — [修改] 发行化 + 机器自适应自检：新增 bench_namd.sh（首次实测→全局记忆→可重测），脚本并行参数改读 machine.conf，路径/权限/许可发行化

- **时间**：2026-10-08 22:20:22 +0800
- **类型**：修改
- **来源项目**：/home/dell/LBJ/WORKFLOW
- **改动文件**：
  - bench_namd.sh
  - machine.conf.example
  - VERSION
  - LICENSE
  - .gitattributes
  - README.md
  - WORKFLOW.md
  - SKILL.md
  - AGENTS.md
  - ARCHIVE.md
  - .gitignore
  - logs/README.md
  - logs/log_change.sh
  - free_energy/README.md
  - free_energy/us/run_all.sh
  - free_energy/us/template.conf
  - free_energy/smd/run_smd.sh
  - free_energy/smd/smd.conf
  - free_energy/extract/run_extract.sh
  - free_energy/extract/extract.tcl
  - free_energy/pmf/run_wham.sh
  - analysis/calCurr.sh
  - new_project.sh
  - models/cnt_crown/0build/build_us_system.tcl
  - models/cnt_crown/1model/system_solv.log
  - models/cnt_crown/2min/min.conf
  - models/cnt_crown/3eq/eq.conf
- **说明**：
  MD-Master 发行化 + 机器自适应自检（同步参考库最新措辞）。① 新增 bench_namd.sh：
首次使用实测本机最优 NAMD 参数（线程扫描 → 绑核验证 → 并发扫描），结果写进全局记忆
~/.config/md-master/machine.conf，之后全库脚本自动读、不再重复测试；--retest 重测、
--show 看配置、--print 抄命令、--env 只看环境、--cpu-only 兼容非 CUDA 版；无 GPU 时
报错退出且不写配置；全程在用户目录临时目录里跑，不碰项目与现存 conf。② 六个脚本改为
读该全局配置（us/run_all.sh、smd/run_smd.sh、extract/run_extract.sh、pmf/run_wham.sh、
analysis/calCurr.sh），并行参数不再写死；顺带修 run_extract.sh 定义了 $VMD 却直接调
vmd 的 bug；缺配置时降级为保守默认 + 醒目提示，MD_MASTER_STRICT=1 才硬报错。
③ 发行化：路径去本机化（/home/dell、/mnt/data2、/mnt/share 全部换成变量/占位符）、
权限归一到 644/755（消除 4 个 600）、补 VERSION/LICENSE(MIT)/.gitattributes、
machine.conf.example、.gitignore 增补。④ 文档：WORKFLOW.md §0 重写为「环境与首次自检」、
README/SKILL/AGENTS 增加首次自检流程与铁律、new_project.sh 模板命令改为读配置。
⑤ 铁律遵守：/home/dell/LBJ/WORKFLOW 全程零写入（只读 diff 校验）。

## 2026-10-08 22:24:08 +0800 — [修复] 更正上一条说明：改读全局配置的脚本是 5 个（run_all/run_smd/run_extract/run_wham/calCurr），原文误写为六个

- **时间**：2026-10-08 22:24:08 +0800
- **类型**：修复
- **改动文件**：
  - logs/CHANGELOG.md
- **说明**：
  只更正计数，不影响改动内容；CHANGELOG 只增不改，故追加而非修改旧条目。
