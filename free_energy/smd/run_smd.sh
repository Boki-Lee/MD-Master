#!/bin/bash
# ============================================================
#  SMD 拉伸启动器：生成 smd.colvars（替换原子序号）后跑 NAMD
# ============================================================
set -e
cd "$(dirname "$0")"

NAMD="${NAMD:-/home/dell/Install/Namd/NAMD_3.0.1_Linux-x86_64-multicore-CUDA/namd3}"

if [ ! -f ../1model/ion_index.dat ] || [ ! -f ../1model/ox_indices.dat ]; then
    echo "ERROR: 先跑 0build（cd ../0build && ./run_build_us.sh）生成 ion_index.dat / ox_indices.dat"
    exit 1
fi

ION=$(cat ../1model/ion_index.dat)
OX=$(cat ../1model/ox_indices.dat)

sed -e "s/@ION@/$ION/g" -e "s/@OX@/$OX/g" smd.colvars.in > smd.colvars
echo ">> K⁺ index=$ION   目标孔 O indices: $OX"

echo ">> 开始 SMD 拉伸（1 ns，K⁺ 从管外 +12 Å 拉到管内 -6 Å）..."
$NAMD +p32 +setcpuaffinity +devices 0 smd.conf > smd.log 2>&1
echo ">> SMD 完成。产物：smd_output.dcd + smd_output.colvars.traj，日志 smd.log"
