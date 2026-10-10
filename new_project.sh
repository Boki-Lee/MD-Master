#!/bin/bash
# ============================================================
#  new_project.sh —— 一键搭建新的 MD 项目骨架（0–6 步骤）
#
#  用法：
#      bash new_project.sh /路径/新项目
#      bash new_project.sh /路径/新项目 --with-prod          # 步骤4：加电场生产模拟
#      bash new_project.sh /路径/新项目 --with-free-energy   # 步骤5：自由能
#      bash new_project.sh /路径/新项目 --with-analysis      # 步骤6：分析脚本
#      （三个开关可任意组合；--help 看说明）
#
#  参考库来源：本脚本所在目录（本 skill 根目录）
#
#  提示：新项目第一次跑 NAMD 前，先在新项目里 `bash bench_namd.sh`（脚本已一并复制过去）——
#        它会实测本机最优的线程数/是否绑核/并发路数并写进全局记忆，之后所有脚本自动读。
#
#  做的事：
#      1. 建骨架 forcefield/ 0build/ 1model/（2min/ 3eq/ 视分支而定，见下）
#      2. 复制力场 6 文件 + 标准建模脚本（build_cnt_crown.tcl 等，改头参数即可）
#      3. 按开关追加 4prod/（力脚本）、2smd+3extract+4us+5pmf/（自由能）、analysis/（分析）
#      4. 生成 README.md（目录说明）与 TODO.md（上手清单）
#
#  不做的事：
#      不生成 2min/3eq/4prod 的 conf —— 盒子尺寸/原子数/原子类型跟体系相关，
#      必须等建模完成后再按 WORKFLOW.md 填（可照抄 models/cnt_crown/ 的 conf）。
#
#  2min/ 3eq/ 什么时候建：
#      默认建（标准 0–3 流程）。**只加 --with-free-energy、不加 --with-prod 时不建**：
#      自由能分支自带最小化+平衡（smd/eq.conf 里 minimize 5000 + 1 ns NVT，
#      平衡产物 eq_output.coor/.vel/.xsc 直接交给 smd/smd.conf 续跑 —— 它就是"3eq 交接"），
#      再空着 2min/3eq 只会让人以为漏跑了步骤（里面什么都没有）。
#      （CNT5 2026-10-10 实测反馈：建了空的 2min/3eq，被问"为什么里面没东西"。）
# ============================================================
set -e

REF="$(cd "$(dirname "$0")" && pwd)"     # 参考库根目录
DEST=""
WITH_PROD=0
WITH_FE=0
WITH_ANALYSIS=0

usage() {
    # 打印文件开头的整段注释（到第一个非注释行为止），不写死行号
    awk 'NR>1 { if ($0 !~ /^#/) exit; print }' "$0" | sed 's/^# \{0,1\}//'
}

# ---- 解析参数 ----
while [ $# -gt 0 ]; do
    case "$1" in
        --with-prod)        WITH_PROD=1; shift ;;
        --with-free-energy) WITH_FE=1; shift ;;
        --with-analysis)    WITH_ANALYSIS=1; shift ;;
        -h|--help)          usage; exit 0 ;;
        *)                  DEST="$1"; shift ;;
    esac
done

if [ -z "$DEST" ]; then
    usage
    echo "错误：请指定目标路径"
    exit 1
fi

echo "参考库  : $REF"
echo "目标项目: $DEST"
echo "开关    : prod=$WITH_PROD  free_energy=$WITH_FE  analysis=$WITH_ANALYSIS"
echo

# ---- 1) 骨架 ----
#  只做自由能（FE 且非 prod）时不建 2min/3eq：那两步在 smd/eq.conf 里，空目录会误导。
if [ "$WITH_FE" = 1 ] && [ "$WITH_PROD" = 0 ]; then
    mkdir -p "$DEST"/{forcefield,0build,1model}
    echo "  [1/6] 骨架已建（forcefield/ 0build/ 1model/）"
    echo "        不建 2min/ 3eq/ —— 自由能分支自带 minimize+平衡（smd/eq.conf），"
    echo "        平衡产物 eq_output.coor/.vel/.xsc 由 smd.conf 续跑。"
    echo "        以后还要走标准生产流程时，再 mkdir 2min 3eq 即可。"
else
    mkdir -p "$DEST"/{forcefield,0build,1model,2min,3eq}
    echo "  [1/6] 骨架已建（forcefield/ 0build/ 1model/ 2min/ 3eq/）"
fi

# ---- 2) 力场 + 机器自检脚本 ----
cp -n "$REF"/forcefield/* "$DEST/forcefield/"
cp -n "$REF"/bench_namd.sh "$REF"/machine.conf.example "$DEST/" 2>/dev/null || true
chmod +x "$DEST/bench_namd.sh" 2>/dev/null || true
echo "  [2/6] 力场 6 文件已复制（+ 机器自检脚本 bench_namd.sh）"

# ---- 3) 标准建模脚本（照抄示例模型，改头参数）----
for f in build_cnt_crown.tcl run_build.sh check_setup.py make_bfactor_pdbs.tcl; do
    cp -n "$REF/models/cnt_crown/0build/$f" "$DEST/0build/"
done
chmod +x "$DEST/0build/run_build.sh"
echo "  [3/6] 标准建模脚本已复制到 0build/"

# ---- 4) 步骤4：生产模拟（自定义力脚本）----
if [ "$WITH_PROD" = 1 ]; then
    mkdir -p "$DEST/4prod"
    cp -n "$REF"/forces/*.tcl "$DEST/4prod/"
    echo "  [4/6] 4prod/ 已建，力脚本已复制（挑一个用 tclForcesScript 挂上）"
else
    echo "  [4/6] 跳过 4prod（需要时加 --with-prod）"
fi

# ---- 5) 步骤5：自由能（库里模板 smd/extract/us/pmf → 生成 2smd/3extract/4us/5pmf）----
if [ "$WITH_FE" = 1 ]; then
    # 库里的模板目录是不编号的 smd/extract/us/pmf（WORKFLOW.md 把自由能四步当作步骤 5 的
    # 子步骤）；生成的项目里改成带步骤号的 2smd/3extract/4us/5pmf，便于和 2min/3eq/4prod 对齐看。
    for pair in "smd:2smd" "extract:3extract" "us:4us" "pmf:5pmf"; do
        mkdir -p "$DEST/${pair##*:}"
        cp -n "$REF/free_energy/${pair%%:*}/"* "$DEST/${pair##*:}/"
    done
    cp -n "$REF/models/cnt_crown/0build/build_us_system.tcl" \
          "$REF/models/cnt_crown/0build/run_build_us.sh" \
          "$REF/models/cnt_crown/0build/check_setup_us.py" "$DEST/0build/"
    chmod +x "$DEST/0build/run_build_us.sh" \
             "$DEST"/{2smd,3extract,4us,5pmf}/*.sh "$DEST"/5pmf/*.py
    # 改名会让脚本内部对兄弟目录的引用失配（3extract 要读 ../smd/smd_output.*、
    # 5pmf 要读 ../us/windows.txt 等），必须一起改写。用 python 精确改写：
    # 只认这 4 个目录名、且只认"前面不是数字/字母/下划线"的出现 —— 所以 2smd/ 不会被
    # 再编号一次，status/ 里的 us/ 也不会被误伤；可重复执行。
    python3 - "$DEST" <<'PYEOF'
import os, re, sys
dest = sys.argv[1]
pairs = [("smd", "2smd"), ("extract", "3extract"), ("us", "4us"), ("pmf", "5pmf")]
table = dict(pairs)
pat = re.compile(r'(?<![0-9A-Za-z_])(' + "|".join(n for n, _ in pairs) + r')/')
n = 0
for pair in pairs:
    d = os.path.join(dest, pair[1])
    for fn in sorted(os.listdir(d)):
        fp = os.path.join(d, fn)
        if not os.path.isfile(fp):
            continue
        out = []
        hit = 0
        for line in open(fp, encoding="utf-8", errors="surrogateescape").read().splitlines(True):
            # 行里若出现绝对路径（形如 "# 参考：/某个老项目/.../us/1smd.conf"），
            # 那是外部历史出处、不是本项目里的兄弟目录 —— 整行跳过、不改名。
            # 相对路径（../smd/、../us/ 之类）不受影响，照常改写。
            if re.search(r"(^|[\s\"'(])/[\w.-]+/", line):
                out.append(line)
                continue
            nl = pat.sub(lambda m: table[m.group(1)] + "/", line)
            if nl != line:
                hit += 1
            out.append(nl)
        if hit:
            open(fp, "w", encoding="utf-8", errors="surrogateescape").write("".join(out))
            print("        引用改写 " + pair[0] + "/" + fn + "（%d 行）" % hit)
            n += 1
# 自检：脚本里 ../xxx/ 形式的兄弟目录引用必须都指到项目里已建的目录
bad = []
for pair in pairs:
    d = os.path.join(dest, pair[1])
    for fn in sorted(os.listdir(d)):
        fp = os.path.join(d, fn)
        if not os.path.isfile(fp):
            continue
        txt = open(fp, encoding="utf-8", errors="surrogateescape").read()
        for m in re.finditer(r'[.][.]/([0-9A-Za-z_]+)/', txt):
            if not os.path.isdir(os.path.join(dest, m.group(1))):
                bad.append(pair[1] + "/" + fn + " -> ../" + m.group(1) + "/")
if bad:
    print("        [警告] 有引用指不到已建目录：")
    for b in sorted(set(bad)):
        print("          " + b)
else:
    print("        自检通过：../xxx/ 引用全部指向已建目录")
print("        共改写 %d 个文件的兄弟目录引用" % n)
PYEOF
    echo "  [5/6] 自由能子步骤 2smd/3extract/4us/5pmf 已建（自带 min+eq，不需要 2min/3eq）"
    echo "        库里模板是不编号的 smd/extract/us/pmf，生成时已改名并改写脚本内部引用"
else
    echo "  [5/6] 跳过自由能（需要时加 --with-free-energy）"
fi

# ---- 6) 步骤6：分析脚本 ----
if [ "$WITH_ANALYSIS" = 1 ]; then
    mkdir -p "$DEST/analysis"
    cp -n "$REF"/analysis/field_protocol.py "$REF"/analysis/calCurr.sh \
          "$REF"/analysis/ion-cur.tcl "$REF"/analysis/plot_iv.py \
          "$REF"/analysis/plot_currents.py "$REF"/analysis/plot_concentration.py \
          "$DEST/analysis/"
    chmod +x "$DEST/analysis"/*.sh "$DEST/analysis"/*.py
    echo "  [6/6] analysis/ 已建，脚本已复制"
else
    echo "  [6/6] 跳过 analysis（需要时加 --with-analysis）"
fi

# ---- 生成项目 README.md ----
cat > "$DEST/README.md" <<'EOF'
# 新项目 README

## 目录（0–6 步骤）

```
forcefield/  力场参数（6 个，已复制）
0build/      ① 建模     build_cnt_crown.tcl / run_build.sh / check_setup.py / make_bfactor_pdbs.tcl
1model/      ② 产物     system_*.psf/pdb、cnt_restrain.pdb、cnt_langevin.pdb、ion_ids.dat
2min/        ③ 最小化   min.conf（建模后照 models/cnt_crown/2min 填）
3eq/         ④ 平衡     eq.conf（续算 ../2min/min）
4prod/       ⑤ 生产     prod.conf + 力脚本（选做，加 --with-prod）
2smd/        ⑤' 自由能  eq.conf（minimize + 1 ns NVT）→ smd.conf（SMD 拉伸）两步走
3extract/    ⑤'        从 SMD 轨迹按窗口目标 z 取帧 → win_*.pdb
4us/         ⑤'        伞形采样：windows.txt + setup_us.sh + run_all.sh
5pmf/        ⑤'        WHAM → pmf.txt / pmf.png（run_wham.sh、wham.py、plot_pmf.py）
analysis/    ⑥ 分析     calCurr.sh / plot_*.py（选做，加 --with-analysis）
```

> 只加 `--with-free-energy` 的项目**没有** `2min/3eq/4prod`：自由能分支的最小化+平衡
> 在 `2smd/eq.conf` 里，`2smd/eq_output.coor/.vel/.xsc` 就是交给 SMD 的交接件。
>
> 自由能四目录带**步骤号**（`2smd/3extract/4us/5pmf`）。库里的模板是不编号的
> `free_energy/smd|extract|us|pmf`（参考库把自由能四步视为步骤 5 的子步骤）；
> 生成时改名，并自动改写了脚本内部对兄弟目录的引用（`../smd/`→`../2smd/` 等），
> 所以拿出来就能用，不用手动改路径。

## 相对路径约定

- 所有 conf 都用相对路径引用 `../1model/*` 与 `../forcefield/*`
  （改了目录深度要整体加一层 `../`，否则 NAMD 跑到那一行才 FATAL）。
- `3eq` 续算 `../2min/min`；`4prod` 续算 `../3eq/eq`。
- 自由能分支的接力：`2smd/smd.conf` 续算 `2smd/eq_output.*`；`3extract` 读
  `2smd/smd_output.colvars.traj` 写 `4us/win_*.pdb`；`5pmf/run_wham.sh` 读 `4us/us_*.colvars.traj`。
- 力脚本/分析脚本引用 `../1model/ion_ids.dat`、`../3eq/eq.restart.xsc`、`../4prod/prod.dcd`。

## 下一步

看同目录 `TODO.md` 按清单走；完整流程、坑与排错见参考库 `WORKFLOW.md`。
EOF
echo "  README.md 已生成"

# ---- 生成 TODO.md ----
cat > "$DEST/TODO.md" <<'EOF'
# 新项目上手清单

> 完整说明见本 skill 根目录的 `WORKFLOW.md`

## 一、建模（0build → 1model）

- [ ] 改 `0build/build_cnt_crown.tcl` 头部参数（CNT_N/CNT_M、管长、孔圈数、盐浓度 ION_CONC）
- [ ] 确认 `forcefield/C_O.par` 里有 `CA OX` 参数（冠醚氧原子类型必须是 **OX**）
- [ ] `cd 0build && ./run_build.sh`，产物写入 `../1model/`
- [ ] 生成 `1model/ion_ids.dat`（0-based ID）、`cnt_restrain.pdb` / `cnt_langevin.pdb`（B 字段）
- [ ] 记录盒子：`cat 1model/system_solv.log` 里的 `-minmax`

## 二、写配置并跑（2min → 3eq，NAMD 由你在终端启动）

> 自由能分支（`--with-free-energy`）**没有** 2min/3eq：最小化+平衡写在 `2smd/eq.conf` 里，
> 直接跳到下面第三节的「5 自由能」即可。

- [ ] `2min/min.conf`：`structure/coordinates`→`../1model/system_ion.*`；
      `cellBasisVector*`=盒子边长；**`cellOrigin`=盒子中心**（不是角点！）；`langevinFile`/`consref`→`../1model/cnt_*.pdb`
- [ ] **先做机器自检**：`bash bench_namd.sh`（首次一次即可，结果全局记忆；重测用 `--retest`）
- [ ] `python3 0build/check_setup.py` 静态校验全 PASS 再跑
- [ ] `cd 2min && $NAMD +p$NTHREADS $AFFINITY +devices $DEVICES min.conf > min.log 2>&1`
      （参数来自 machine.conf；抄现成命令：`bash bench_namd.sh --print single`）
- [ ] `grep "PERIODIC CELL CENTER" min.log` 确认盒子中心对
- [ ] `cd ../3eq && $NAMD +p$NTHREADS $AFFINITY +devices $DEVICES eq.conf > eq.log 2>&1`

## 三、分支：步骤4 生产模拟 或 步骤5 自由能（二选一）

### 4prod（加自定义力）
- [ ] 挑一个 `4prod/` 里的力脚本，在 `prod.conf` 写 `tclForces on` + `tclForcesScript`
- [ ] `prod.conf` 续算 `../3eq/eq`；**不要写 CUDASOAintegrate、不要写 stepsPerCycle**
- [ ] 改完先离线自检：`tclsh 4prod/selftest_field.tcl ../3eq/eq.restart.xsc`
- [ ] `cd 4prod && nohup $NAMD +p$NTHREADS $AFFINITY +devices $DEVICES prod.conf > prod.log 2>&1 &`

### 5 自由能（US/SMD+WHAM）
- [ ] `0build/run_build_us.sh`（--ion POT/CAL/SOD、--zmax/--zmin 等）生成 US 体系进 `1model/`
- [ ] `python3 0build/check_setup_us.py` 通过
- [ ] `cd 2smd && ./run_smd.sh`（先 eq.conf 跑 minimize + 1 ns NVT，再 smd.conf 续跑 SMD；
      这就是自由能分支的"3eq"，`2smd/eq_output.coor/.vel/.xsc` 是交接件）
- [ ] `cd ../3extract && ./run_extract.sh`（按 windows.txt 的窗口中心取帧 → 4us/win_*.pdb）
- [ ] `cd ../4us && ./setup_us.sh && ./run_all.sh`（多窗口，见 run_all.sh 头注释的并发说明）
- [ ] `cd ../5pmf && ./run_wham.sh && python plot_pmf.py`

## 四、分析（步骤6，每次按目标单独确认算什么）

- [ ] 改 `analysis/field_protocol.py` 顶部协议参数（AXIAL_MODE/V_*/SHELL_RADII/TUBE_R）
- [ ] `bash analysis/calCurr.sh 2 100` 试跑，再 `nohup bash analysis/calCurr.sh "${ANALYSIS_JOBS:-8}" 10000 &`
- [ ] 激活分析用的 Python 环境（示例 `conda activate MD`）后跑 `plot_iv.py` / `plot_currents.py` / `plot_concentration.py`

## 五、别忘了（物理陷阱）

- [ ] 总电流里管外是并联通路，测通道输运要用"管内/柱心"分量
- [ ] 管壁两侧各有约 5 Å 离子排斥层，算浓度用柱心对远处本体
- [ ] 轨迹文件（dcd）很占地方，跑完记得清理或转存
EOF
echo "  TODO.md 已生成"

echo
echo "============================================"
echo "完成！项目: $DEST"
echo
ls -1 "$DEST"
echo
echo "下一步：读 $DEST/TODO.md，按清单走"
echo "============================================"
