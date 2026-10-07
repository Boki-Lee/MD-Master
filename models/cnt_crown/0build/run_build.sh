#!/usr/bin/env bash
# ============================================================
#  build_cnt_crown.tcl 的 Ubuntu 启动器
#
#  用法：
#      ./run_build.sh                 # 只建模：CNT + 冠醚孔（默认）
#      ./run_build.sh --solvate       # 再溶剂化 + 加 0.6 M KCl
#      ./run_build.sh --solvate --render
#      ./run_build.sh --outdir /path/to/out
#      ./run_build.sh --n 23 --m 23 --length 8.0 --rings 4
#
#  选项：
#      --outdir DIR     输出目录（默认：本脚本所在目录）
#      --solvate        执行阶段 2（溶剂化 + 加离子）
#      --render         执行阶段 3（渲染 system_final.bmp）
#      --n N --m M      手性指数（默认 23 23）
#      --length NM      管长，单位 nm（默认 8.0）
#      --rings N        孔圈数（默认 4）
#      --conc M         盐浓度 mol/L（默认 0.6）
#      -h, --help       显示帮助
#
#  环境变量：
#      VMD_BIN   VMD 可执行文件路径（默认：从 PATH 中查找 vmd）
#      VMDDIR    VMD 安装根目录，用于定位 nanotube 插件
# ============================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat <<'USAGE'
build_cnt_crown.tcl 的 Ubuntu 启动器

  ./run_build.sh [选项]

选项：
  --outdir DIR   输出目录（默认：本脚本所在目录）
  --solvate      执行阶段 2（溶剂化 + 加离子）
  --render       执行阶段 3（渲染 system_final.bmp）
  --n N          手性指数 n（默认 23）
  --m M          手性指数 m（默认 23）
  --length NM    管长，单位 nm（默认 8.0）
  --rings N      孔圈数（默认 4）
  --conc M       盐浓度 mol/L（默认 0.6）
  -h, --help     显示本帮助

环境变量：
  VMD_BIN        VMD 可执行文件路径（默认：从 PATH 中查找 vmd）
  VMDDIR         VMD 安装根目录（用于定位 nanotube 插件）
USAGE
}

# ---- 默认值（可被环境变量覆盖） ----
if [ -z "$CNT_N" ];         then CNT_N=23;        fi
if [ -z "$CNT_M" ];         then CNT_M=23;        fi
if [ -z "$CNT_LENGTH_NM" ]; then CNT_LENGTH_NM=8.0; fi
if [ -z "$PORE_RINGS" ];    then PORE_RINGS=4;    fi
if [ -z "$ION_CONC" ];      then ION_CONC=0.6;    fi
if [ -z "$DO_SOLVATE" ];    then DO_SOLVATE=0;    fi
if [ -z "$DO_RENDER" ];     then DO_RENDER=0;     fi
if [ -z "$CNT_OUTDIR" ];    then CNT_OUTDIR="$SCRIPT_DIR"; fi
OUTDIR="$CNT_OUTDIR"

# ---- 定位 VMD ----
if [ -n "$VMD_BIN" ]; then
    :
elif command -v vmd >/dev/null 2>&1; then
    VMD_BIN="$(command -v vmd)"
else
    echo "ERROR: vmd was not found in PATH."
    echo "       Install VMD or set VMD_BIN=/path/to/vmd"
    exit 1
fi

# ---- 定位 VMD 插件根目录（用于 nanotube1.6） ----
if [ -z "$VMDDIR" ] && [ -d /usr/local/lib/vmd ]; then
    VMDDIR=/usr/local/lib/vmd
fi

# ---- 解析命令行参数 ----
while [ $# -gt 0 ]; do
    case "$1" in
        --outdir)  OUTDIR="$2"; shift 2 ;;
        --solvate) DO_SOLVATE=1; shift ;;
        --render)  DO_RENDER=1; shift ;;
        --n)       CNT_N="$2"; shift 2 ;;
        --m)       CNT_M="$2"; shift 2 ;;
        --length)  CNT_LENGTH_NM="$2"; shift 2 ;;
        --rings)   PORE_RINGS="$2"; shift 2 ;;
        --conc)    ION_CONC="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

export CNT_N CNT_M CNT_LENGTH_NM PORE_RINGS ION_CONC
export DO_SOLVATE DO_RENDER
export CNT_OUTDIR="$OUTDIR"
if [ -n "$VMDDIR" ]; then export VMDDIR; fi

mkdir -p "$OUTDIR"

echo "============================================"
echo " VMD      : $VMD_BIN"
echo " VMDDIR   : $VMDDIR"
echo " outdir   : $OUTDIR"
echo " chirality: n=$CNT_N m=$CNT_M  length=$CNT_LENGTH_NM nm"
echo " rings    : $PORE_RINGS"
echo " solvate  : $DO_SOLVATE    render: $DO_RENDER"
echo "============================================"

"$VMD_BIN" -dispdev none -e "$SCRIPT_DIR/build_cnt_crown.tcl"
