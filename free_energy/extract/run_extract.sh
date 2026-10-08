#!/bin/bash
# ============================================================
#  提取 US 窗口起始构象启动器
# ============================================================
set -e
cd "$(dirname "$0")"

# ---- 机器自适应配置（首次使用：bash bench_namd.sh）----
CONF="${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}"
if [ -r "$CONF" ]; then
    . "$CONF"
else
    echo "⚠ 未找到机器配置 $CONF —— 首次使用请先跑 bash bench_namd.sh（本次自动探测 vmd）" >&2
    [ "${MD_MASTER_STRICT:-0}" = "1" ] && { echo "MD_MASTER_STRICT=1，退出"; exit 1; }
fi
VMD="${VMD:-$(command -v vmd || true)}"
[ -n "$VMD" ] || { echo "ERROR: 找不到 vmd（设 VMD=/path/to/vmd，或先跑 bench_namd.sh）" >&2; exit 1; }

if [ ! -f ../smd/smd_output.colvars.traj ]; then
    echo "ERROR: 先跑 SMD（cd ../smd && ./run_smd.sh）"
    exit 1
fi

echo ">> 从 SMD 轨迹提取各窗口起始构象（写入 ../us/win_XX.XX.pdb）..."
"$VMD" -dispdev none -e extract.tcl
echo ">> 提取完成"
