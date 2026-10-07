#!/bin/bash
# ============================================================
#  提取 US 窗口起始构象启动器
# ============================================================
set -e
cd "$(dirname "$0")"

VMD="${VMD:-/usr/local/bin/vmd}"

if [ ! -f ../smd/smd_output.colvars.traj ]; then
    echo "ERROR: 先跑 SMD（cd ../smd && ./run_smd.sh）"
    exit 1
fi

echo ">> 从 SMD 轨迹提取各窗口起始构象（写入 ../us/win_XX.XX.pdb）..."
vmd -dispdev none -e extract.tcl
echo ">> 提取完成"
