#!/bin/bash
# ============================================================
#  SMD 前处理 + 拉伸启动器（两步走，对外仍然是一条命令）
#
#    第 1 步  eq.conf  : minimize 5000 + 1 ns NVT 平衡
#                        （目标离子用 selectConstrX/Y/Z 三维钉在放置点）
#    第 2 步  smd.conf : 从 eq_output.coor/.vel/.xsc 续跑，
#                        把离子从管外体相匀速拉到管内
#
#  为什么要有第 1 步：溶剂化出来的水是格点摆放的，目标离子又是建模脚本手工
#  挪到 (0,0,+ion_z_max) 的。只做 5000 步最小化就立刻以几 Å/ns 往外拉，SMD
#  起始那一段的水还没热平衡。若 US 窗口范围压得较窄（例如孔心 ±5 Å），最外端
#  窗口就落在 SMD 起点附近，而它往往又是 PMF 的零点参考 —— 会直接污染基线。
#
#  断点续跑：eq_output.coor/.vel/.xsc 三者齐备就跳过平衡。
#  SKIP_EQ=1 可强制跳过（用于严格对齐"不做独立平衡"的老跑法）。
#
#  用法：
#      ./run_smd.sh                  # 默认 +p32 +setcpuaffinity（单进程顺序跑，绑核 +29%）
#      NTHREADS=16 ./run_smd.sh      # 降线程
#      SKIP_EQ=1 ./run_smd.sh        # 不跑平衡（需已有 eq_output.*）
#
#  注意：本机 NAMD 是 CUDA 编译版，必须有 /dev/nvidia* 才能起。
#        多进程并发时才严禁 +setcpuaffinity；这里是单进程顺序跑，绑核是安全的。
# ============================================================
set -e
cd "$(dirname "$0")"

NAMD="${NAMD:-/home/dell/Install/Namd/NAMD_3.0.1_Linux-x86_64-multicore-CUDA/namd3}"
NTHREADS="${NTHREADS:-32}"

if [ ! -f ../1model/ion_index.dat ] || [ ! -f ../1model/ox_indices.dat ]; then
    echo "ERROR: 先跑 0build（cd ../0build && ./run_build_us.sh）生成 ion_index.dat / ox_indices.dat"
    exit 1
fi

ION=$(cat ../1model/ion_index.dat)
OX=$(cat ../1model/ox_indices.dat)

sed -e "s/@ION@/$ION/g" -e "s/@OX@/$OX/g" smd.colvars.in > smd.colvars
echo ">> ion index=$ION   target pore O indices: $OX"

# ---------------- 第 1 步：最小化 + 1 ns NVT 平衡 ----------------
if [ "${SKIP_EQ:-0}" = "1" ]; then
    echo ">> SKIP_EQ=1: skip equilibration stage"
elif [ -f eq_output.coor ] && [ -f eq_output.vel ] && [ -f eq_output.xsc ]; then
    echo ">> eq_output.coor/.vel/.xsc already present, skip equilibration stage"
else
    echo ">> [1/2] minimize + 1 ns NVT equilibration ..."
    # 清掉上一次没跑完的残留，避免读到半截文件
    rm -f eq_output.coor eq_output.vel eq_output.xsc eq_output.dcd eq_output.xst
    if ! $NAMD +p$NTHREADS +setcpuaffinity +devices 0 eq.conf > eq.log 2>&1; then
        echo "ERROR: 平衡阶段失败，eq.log 末尾："
        tail -20 eq.log
        exit 1
    fi
    if [ ! -f eq_output.coor ] || [ ! -f eq_output.vel ] || [ ! -f eq_output.xsc ]; then
        echo "ERROR: 平衡没有产出 eq_output.coor/.vel/.xsc，eq.log 末尾："
        tail -20 eq.log
        exit 1
    fi
    echo ">> 平衡完成（eq_output.coor/.vel/.xsc，日志 eq.log）"
fi

# 无论走哪条分支，续跑文件都必须齐备，否则 smd.conf 起不来
if [ ! -f eq_output.coor ] || [ ! -f eq_output.vel ] || [ ! -f eq_output.xsc ]; then
    echo "ERROR: 缺 eq_output.coor/.vel/.xsc，smd.conf 无法续跑"
    echo "       请先跑平衡（去掉 SKIP_EQ=1），或确认 eq.log 是否正常结束"
    exit 1
fi

# ---------------- 第 2 步：SMD 拉伸 ----------------
echo ">> [2/2] SMD pulling (1 ns, ion from +12 A outside to -6 A inside) ..."
if ! $NAMD +p$NTHREADS +setcpuaffinity +devices 0 smd.conf > smd.log 2>&1; then
    echo "ERROR: SMD 失败，smd.log 末尾："
    tail -20 smd.log
    exit 1
fi
echo ">> SMD 完成。产物：smd_output.dcd + smd_output.colvars.traj，日志 smd.log"
