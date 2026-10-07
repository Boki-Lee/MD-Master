#!/usr/bin/env bash
# ============================================================
#  build_us_system.tcl 的 Ubuntu 启动器
#
#  用法：
#      SRC_MODEL=/路径/system_combined ./run_build.sh
#      ./run_build.sh --src /路径/system_combined --ion POT --zmax 12 --zmin -6
#
#  选项：
#      --src PATH      未溶剂化 CNT+冠醚模型前缀（等价 SRC_MODEL，必需）
#      --ion NAME      目标阳离子（POT/CAL/SOD，默认 POT）
#      --anion NAME    反离子（默认 CLA）
#      --nion N        目标离子个数（默认 1）
#      --nanion N      反离子个数（默认 1）
#      --zmax Z        管外体相最远窗口 z Å（默认 12）
#      --zmin Z        管内最深窗口 z Å（默认 -6）
#      --outdir DIR    输出目录（默认 ../1model）
#      -h, --help      显示帮助
#
#  环境变量：
#      VMD_BIN   VMD 可执行文件路径（默认：从 PATH 查找 vmd）
# ============================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat <<'USAGE'
build_us_system.tcl 的 Ubuntu 启动器（旋转目标孔 + 溶剂化 + 加离子）

  SRC_MODEL=/路径/system_combined ./run_build.sh [选项]

选项：
  --src PATH      未溶剂化 CNT+冠醚模型前缀（必需，如 /path/system_combined）
  --ion NAME      目标阳离子 POT/CAL/SOD（默认 POT）
  --anion NAME    反离子（默认 CLA）
  --nion N        目标离子个数（默认 1）
  --nanion N      反离子个数（默认 1）
  --zmax Z        管外体相最远窗口 z，Å（默认 12）
  --zmin Z        管内最深窗口 z，Å（默认 -6）
  --outdir DIR    输出目录（默认 ../1model）
  -h, --help      显示本帮助

环境变量：
  VMD_BIN         VMD 可执行文件路径（默认：从 PATH 查找 vmd）
USAGE
}

# ---- 默认值 ----
: "${ION_TYPE:=POT}"
: "${ION_ANION:=CLA}"
: "${NION:=1}"
: "${NANION:=1}"
: "${ION_Z_MAX:=12.0}"
: "${ION_Z_MIN:=-6.0}"
: "${BULK_MARGIN:=10.0}"
: "${PAD:=8.0}"
: "${OUTDIR:=$SCRIPT_DIR/../1model}"

# ---- 定位 VMD ----
if [ -n "$VMD_BIN" ]; then
    :
elif command -v vmd >/dev/null 2>&1; then
    VMD_BIN="$(command -v vmd)"
else
    echo "ERROR: vmd was not found in PATH. 安装 VMD 或设 VMD_BIN=/path/to/vmd"
    exit 1
fi

# ---- 解析命令行参数 ----
while [ $# -gt 0 ]; do
    case "$1" in
        --src)    SRC_MODEL="$2"; shift 2 ;;
        --ion)    ION_TYPE="$2"; shift 2 ;;
        --anion)  ION_ANION="$2"; shift 2 ;;
        --nion)   NION="$2"; shift 2 ;;
        --nanion) NANION="$2"; shift 2 ;;
        --zmax)   ION_Z_MAX="$2"; shift 2 ;;
        --zmin)   ION_Z_MIN="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [ -z "$SRC_MODEL" ]; then
    echo "ERROR: 请指定 SRC_MODEL=/路径/system_combined（未溶剂化的 CNT+冠醚模型）"
    echo "       可用 CNT 参考库 build_cnt_crown.tcl 生成。"
    exit 1
fi

export SRC_MODEL ION_TYPE ION_ANION NION NANION ION_Z_MAX ION_Z_MIN BULK_MARGIN PAD OUTDIR

mkdir -p "$OUTDIR"

echo "============================================"
echo " VMD    : $VMD_BIN"
echo " src    : $SRC_MODEL"
echo " ion    : $NION x $ION_TYPE  +  $NANION x $ION_ANION"
echo " z 范围 : $ION_Z_MAX .. $ION_Z_MIN  (Å，孔心=0)"
echo " outdir : $OUTDIR"
echo "============================================"

"$VMD_BIN" -dispdev none -e "$SCRIPT_DIR/build_us_system.tcl"
