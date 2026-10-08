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
#  做的事：
#      1. 建骨架 forcefield/ 0build/ 1model/ 2min/ 3eq/
#      2. 复制力场 6 文件 + 标准建模脚本（build_cnt_crown.tcl 等，改头参数即可）
#      3. 按开关追加 4prod/（力脚本）、smd~pmf/（自由能）、analysis/（分析）
#      4. 生成 README.md（目录说明）与 TODO.md（上手清单）
#
#  不做的事：
#      不生成 2min/3eq/4prod 的 conf —— 盒子尺寸/原子数/原子类型跟体系相关，
#      必须等建模完成后再按 WORKFLOW.md 填（可照抄 models/cnt_crown/ 的 conf）。
# ============================================================
set -e

REF="$(cd "$(dirname "$0")" && pwd)"     # 参考库根目录
DEST=""
WITH_PROD=0
WITH_FE=0
WITH_ANALYSIS=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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
mkdir -p "$DEST"/{forcefield,0build,1model,2min,3eq}
echo "  [1/6] 骨架已建（forcefield/ 0build/ 1model/ 2min/ 3eq/）"

# ---- 2) 力场 ----
cp -n "$REF"/forcefield/* "$DEST/forcefield/"
echo "  [2/6] 力场 6 文件已复制"

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

# ---- 5) 步骤5：自由能（smd/extract/us/pmf + US 建模脚本）----
if [ "$WITH_FE" = 1 ]; then
    for d in smd extract us pmf; do
        mkdir -p "$DEST/$d"
        cp -n "$REF/free_energy/$d/"* "$DEST/$d/"
    done
    cp -n "$REF/models/cnt_crown/0build/build_us_system.tcl" \
          "$REF/models/cnt_crown/0build/run_build_us.sh" \
          "$REF/models/cnt_crown/0build/check_setup_us.py" "$DEST/0build/"
    chmod +x "$DEST/0build/run_build_us.sh" \
             "$DEST"/{smd,extract,us,pmf}/*.sh "$DEST"/pmf/*.py
    echo "  [5/6] 自由能子步骤 smd/extract/us/pmf 已建，US 建模脚本已进 0build/"
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
smd~pmf/     ⑤' 自由能  平衡→SMD拉伸→提取→伞形采样→WHAM（选做，加 --with-free-energy）
analysis/    ⑥ 分析     calCurr.sh / plot_*.py（选做，加 --with-analysis）
```

## 相对路径约定

- `2min`/`3eq`/`4prod`/`smd`/`us` 的 conf 都引用 `../1model/*` 与 `../forcefield/*`。
- `3eq` 续算 `../2min/min`；`4prod` 续算 `../3eq/eq`。
- 力脚本/分析脚本引用 `../1model/ion_ids.dat`、`../3eq/eq.restart.xsc`、`../4prod/prod.dcd`。

## 下一步

看同目录 `TODO.md` 按清单走；完整流程、坑与排错见参考库 `WORKFLOW.md`。
EOF
echo "  README.md 已生成"

# ---- 生成 TODO.md ----
cat > "$DEST/TODO.md" <<'EOF'
# 新项目上手清单

> 完整说明见参考库 `WORKFLOW.md`

## 一、建模（0build → 1model）

- [ ] 改 `0build/build_cnt_crown.tcl` 头部参数（CNT_N/CNT_M、管长、孔圈数、盐浓度 ION_CONC）
- [ ] 确认 `forcefield/C_O.par` 里有 `CA OX` 参数（冠醚氧原子类型必须是 **OX**）
- [ ] `cd 0build && ./run_build.sh`，产物写入 `../1model/`
- [ ] 生成 `1model/ion_ids.dat`（0-based ID）、`cnt_restrain.pdb` / `cnt_langevin.pdb`（B 字段）
- [ ] 记录盒子：`cat 1model/system_solv.log` 里的 `-minmax`

## 二、写配置并跑（2min → 3eq，NAMD 由你在终端启动）

- [ ] `2min/min.conf`：`structure/coordinates`→`../1model/system_ion.*`；
      `cellBasisVector*`=盒子边长；**`cellOrigin`=盒子中心**（不是角点！）；`langevinFile`/`consref`→`../1model/cnt_*.pdb`
- [ ] `python3 0build/check_setup.py` 静态校验全 PASS 再跑
- [ ] `cd 2min && namd3 +p32 +setcpuaffinity +devices 0 min.conf > min.log 2>&1`
- [ ] `grep "PERIODIC CELL CENTER" min.log` 确认盒子中心对
- [ ] `cd ../3eq && namd3 +p32 +setcpuaffinity +devices 0 eq.conf > eq.log 2>&1`

## 三、分支：步骤4 生产模拟 或 步骤5 自由能（二选一）

### 4prod（加自定义力）
- [ ] 挑一个 `4prod/` 里的力脚本，在 `prod.conf` 写 `tclForces on` + `tclForcesScript`
- [ ] `prod.conf` 续算 `../3eq/eq`；**不要写 CUDASOAintegrate、不要写 stepsPerCycle**
- [ ] 改完先离线自检：`tclsh 4prod/selftest_field.tcl ../3eq/eq.restart.xsc`
- [ ] `cd 4prod && nohup namd3 +p32 +setcpuaffinity +devices 0 prod.conf > prod.log 2>&1 &`

### 5 自由能（US/SMD+WHAM）
- [ ] `0build/run_build_us.sh`（--ion POT/CAL/SOD、--zmax/--zmin 等）生成 US 体系进 `1model/`
- [ ] `python3 0build/check_setup_us.py` 通过
- [ ] `cd smd && ./run_smd.sh` → `cd ../extract && ./run_extract.sh`
- [ ] `cd ../us && ./setup_us.sh && ./run_all.sh`（多窗口，见 run_all.sh 头注释的并发说明）
- [ ] `cd ../pmf && ./run_wham.sh && python plot_pmf.py`

## 四、分析（步骤6，每次按目标单独确认算什么）

- [ ] 改 `analysis/field_protocol.py` 顶部协议参数（AXIAL_MODE/V_*/SHELL_RADII/TUBE_R）
- [ ] `bash analysis/calCurr.sh 2 100` 试跑，再 `nohup bash analysis/calCurr.sh 16 10000 &`
- [ ] `conda activate MD` 后跑 `plot_iv.py` / `plot_currents.py` / `plot_concentration.py`

## 五、别忘了（物理陷阱）

- [ ] 总电流里管外是并联通路，测通道输运要用"管内/柱心"分量
- [ ] 管壁两侧各有约 5 Å 离子排斥层，算浓度用柱心对远处本体
- [ ] 数据盘 /mnt/data2 偏满，大轨迹记得清理
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
