#!/bin/bash
# ============================================================
#  archive_model.sh —— 把跑完的项目归档成参考库里的新模型
#
#  用法：
#      bash archive_model.sh /路径/跑完的项目 models/新模型名
#
#  做的事（只复制可复用件，排除运行产物）：
#      - 0build 脚本（*.tcl / *.sh / *.py）
#      - 1model 小文件（*.psf / *.pdb / *.dat / system_solv.log）
#      - 2min/min.conf、3eq/eq.conf
#      - forcefield（如有）
#
#  不做 / 排除：
#      *.dcd *.coor *.vel *.xst *.restart.*、大 log、>20MB 的文件
#      （这些是运行产物，留在数据盘；归档只存模板）
#
#  兼容两种项目目录：
#      新式：0build/ 1model/ 2min/ 3eq/（new_project.sh 生成的）
#      旧式：build 脚本与模型产物在根目录，min/ eq/ prod/（CNT 老项目）
#
#  跑完会打印"还需手动改"清单（写 README、更新索引/ new_project.sh、校验），
#  别跳过 —— 完整流程见 ARCHIVE.md。
# ============================================================
set -euo pipefail

SRC="${1:-}"; DEST="${2:-}"
if [ -z "$SRC" ] || [ -z "$DEST" ]; then
    echo "用法: bash archive_model.sh /路径/跑完的项目 models/新模型名"
    exit 1
fi
SRC="$(cd "$SRC" && pwd)"
DEST="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"

if [ -e "$DEST" ]; then
    echo "错误：目标已存在 $DEST"
    echo "      入库前先查重：要覆盖先手动删，或换名 $DEST_v2"
    exit 1
fi

echo "源项目  : $SRC"
echo "归档到  : $DEST"
echo

# ---- 检测新旧目录结构 ----
NEW_LAYOUT=0
if [ -d "$SRC/0build" ] && [ -d "$SRC/1model" ]; then NEW_LAYOUT=1; fi

mkdir -p "$DEST"/{0build,1model,2min,3eq,forcefield}

# ---- 按后缀复制小文件（<=20MB，排除运行产物）----
# 用法：copy_by_ext <源目录> <目标目录> <后缀1> [后缀2 ...]
copy_by_ext() {
    local sd="$1" td="$2"; shift 2
    [ -d "$sd" ] || return 0
    local -a expr=()
    for e in "$@"; do
        [ ${#expr[@]} -gt 0 ] && expr+=(-o)
        expr+=(-name "*.$e")
    done
    find "$sd" -maxdepth 1 -type f \( "${expr[@]}" \) -size -20M -exec cp -n {} "$td/" \;
}

echo "== 1) 0build 脚本 =="
if [ "$NEW_LAYOUT" = 1 ]; then
    copy_by_ext "$SRC/0build" "$DEST/0build" tcl sh py
else
    # 旧式：build 脚本在项目根目录
    find "$SRC" -maxdepth 1 -type f \( -name 'build_*.tcl' -o -name 'run_build*.sh' \
        -o -name 'check_setup*.py' -o -name 'make_bfactor_pdbs.tcl' \) -exec cp -n {} "$DEST/0build/" \;
fi

echo "== 2) 1model 模型产物（小文件）=="
if [ "$NEW_LAYOUT" = 1 ]; then
    copy_by_ext "$SRC/1model" "$DEST/1model" psf pdb dat
    [ -f "$SRC/1model/system_solv.log" ] && cp -n "$SRC/1model/system_solv.log" "$DEST/1model/" || true
else
    # 旧式：产物在项目根目录
    find "$SRC" -maxdepth 1 -type f \( -name 'system_*.psf' -o -name 'system_*.pdb' \
        -o -name 'cnt_*.pdb' -o -name 'ion_ids.dat' -o -name 'system_solv.log' \) \
        -size -20M -exec cp -n {} "$DEST/1model/" \;
fi

echo "== 3) 2min / 3eq 配置 =="
if [ "$NEW_LAYOUT" = 1 ]; then
    [ -f "$SRC/2min/min.conf" ] && cp -n "$SRC/2min/min.conf" "$DEST/2min/" || true
    [ -f "$SRC/3eq/eq.conf" ]   && cp -n "$SRC/3eq/eq.conf"   "$DEST/3eq/" || true
else
    [ -f "$SRC/min/min.conf" ] && cp -n "$SRC/min/min.conf" "$DEST/2min/" || true
    [ -f "$SRC/eq/eq.conf" ]   && cp -n "$SRC/eq/eq.conf"   "$DEST/3eq/" || true
fi

echo "== 4) forcefield（如有）=="
copy_by_ext "$SRC/forcefield" "$DEST/forcefield" par prm str

# ---- 赋予执行位 ----
chmod +x "$DEST"/0build/*.sh "$DEST"/0build/*.py 2>/dev/null || true

echo
echo "============================================================"
echo "复制完成。文件清单："
find "$DEST" -type f | sort | sed "s#$DEST/##"
echo
echo "============ 还需手动改（别跳过，见 ARCHIVE.md）============"
echo "  □ 改 conf/脚本里的相对路径为新库结构（../1model、../3eq、../forcefield）"
echo "  □ 写 $DEST/README.md（盒子尺寸/原子数/离子/关键参数/相对路径）"
echo "  □ 顶层 README.md 的 models/ 下加一条"
echo "  □ 若引入新脚本：更新 new_project.sh 第 67 行（标准建模）或 88-89 行（US 建模）清单"
echo "  □ python3 $DEST/0build/check_setup.py 跑一遍"
echo "  □ grep 确认无 dcd/coor/vel 误入：find $DEST \\( -name '*.dcd' -o -name '*.coor' -o -name '*.vel' \\)"
echo "============================================================"
