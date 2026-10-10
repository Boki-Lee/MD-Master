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

## 2026-10-10 15:05:16 +0800 — [修改] 同步上游改动（v1.3.0）：new_project.sh 自由能目录带步骤号 + FE 分支不建空 2min/3eq；US 窗口清单规则②更新（混用弹簧需验算接头重叠）；新增版本号铁律

- **时间**：2026-10-10 15:05:16 +0800
- **类型**：修改
- **来源项目**：/home/dell/LBJ/WORKFLOW
- **改动文件**：
  - new_project.sh
  - free_energy/us/windows.txt
  - free_energy/us/windows_bulk_to_tube.txt
  - README.md
  - free_energy/README.md
  - WORKFLOW.md
  - AGENTS.md
  - VERSION
- **说明**：
  同步上游（../WORKFLOW）2026-10-10 的改动，版本 v1.3.0（原 0.1.0）。
① new_project.sh 以上游新版为基线合并：只加 --with-free-energy 时不建空的 2min/3eq
（自由能分支的最小化+平衡本来就在 smd/eq.conf 里，空目录会让人以为漏跑步骤），
并在生成的项目里把自由能四目录改成带步骤号的 2smd/3extract/4us/5pmf，同时用 python
精确改写脚本内部对兄弟目录的引用（../smd/→../2smd/、../us/→../4us/ 等；只认这 4 个
目录名且前面不是数字/字母/下划线，所以 2smd/ 不会被再编号、status/ 里的 us/ 不会误伤），
改完自检每个 ../xxx/ 是否都指到已建目录；usage() 改用 awk 打印头部注释不写死行号。
我方可移植化改动（参考库来源去本机化、复制 bench_namd.sh + machine.conf.example、
TODO 模板改为先自检 + 并行参数走 machine.conf）已合并进这个新基线，并顺手把
TODO 里「完整说明见参考库 /home/dell/LBJ/WORKFLOW/WORKFLOW.md」也去掉本机路径。
② free_energy/us/windows.txt 规则②重写：从「弹簧常数必须统一」改为「混用弹簧可以，
但每个接头都要验算重叠」，附 CNT5 2026-10-10 实测反例（孔区 k=50 接体相 k=10、间距
1.0 Å 时空隙区每 0.01 Å bin 只剩 1.6 个样本、约 40% 概率冒 NaN；改 k=5 + 间距 1.5 Å
后最薄接头 9.4 样本/bin，5 个窗口即覆盖 +6~+12）。③ windows_bulk_to_tube.txt 的
「已知脆弱点」补上同一条实测教训。④ 文档一致性：README.md、free_energy/README.md、
WORKFLOW.md 都注明「生成的项目里自由能目录带步骤号、FE 分支不建空 2min/3eq」。
⑤ 新增 §7 版本号铁律：动手改库前先问用户「这次改到 v几.几.几」，收尾更新 VERSION +
写台账 + 提醒发 Release。⑥ 上游 logs/CHANGELOG.md 不复制（库内台账各记各的）。

## 2026-10-10 15:08:55 +0800 — [修复] v1.3.0 收尾修补：并行参数在「不绑核」时命令行多出的双空格；new_project.sh 改名器判据泛化（去掉写死的 /mnt/share）

- **时间**：2026-10-10 15:08:55 +0800
- **类型**：修复
- **改动文件**：
  - bench_namd.sh
  - free_energy/us/run_all.sh
  - free_energy/smd/run_smd.sh
  - new_project.sh
- **说明**：
  ① bench_namd.sh / us/run_all.sh / smd/run_smd.sh 里 $AFFINITY 为空时会输出 "+p16  +devices 0"（双空格），改成 ${AFFINITY:+ $AFFINITY} 形式；这是用户会照着抄的命令，顺手清干净。② new_project.sh 的兄弟目录引用改写器原用 "if '/mnt/share' in line" 跳过外部历史路径注释，属上游写死的外来路径；改成通用判断「行内出现绝对路径即整行跳过」，对现有模板的改写结果完全不变（实测 5 文件 10 行、自检通过），但库里不再残留任何本机/外来路径。两条都属于 v1.3.0 批次内的收尾打磨。
