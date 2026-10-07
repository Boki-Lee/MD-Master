#!/bin/bash
# ============================================================
#  批量后台运行 US 窗口（分批并发，每批 MAX_JOBS 个）
#
#  用法：
#      ./run_all.sh                          # 默认 3 并发 × +p16（实测最优，约 2030 步/秒合计）
#      NTHREADS=32 MAX_JOBS=1 ./run_all.sh   # 单窗口顺序跑 +p32（唯一能用绑核的情况）
#
#  注意：本机 NAMD 是 CUDA 编译版，必须有 GPU 设备（/dev/nvidia*）。
#  ⚠️ 多进程并发时【严禁 +setcpuaffinity】：实测它会把所有 namd3 进程都钉到 CPU 0，
#     吞吐从 ~866 步/秒/窗 暴跌到 ~16 步/秒/窗（50 倍）。只有单窗口顺序跑才用绑核（+29%）。
#  实测吞吐（本机，24818 原子体系）：
#     单窗口 +p32 +setcpuaffinity = 1041 步/秒（GPU ~34%）
#     2 并发 +p16（无绑核）        = 1732 步/秒合计
#     3 并发 +p16（无绑核）        = 2032 步/秒合计（GPU ~97%，最优）
#     3 并发 +p32 +setcpuaffinity  = ~13 步/秒合计（钉核灾难，别用）
# ============================================================
set -e
cd "$(dirname "$0")"

NAMD="${NAMD:-/home/dell/Install/Namd/NAMD_3.0.1_Linux-x86_64-multicore-CUDA/namd3}"
NTHREADS="${NTHREADS:-16}"
MAX_JOBS="${MAX_JOBS:-3}"

# 只有单窗口顺序跑（MAX_JOBS=1）才允许绑核；多并发一律不绑
AFFINITY=""
[ "$MAX_JOBS" = "1" ] && AFFINITY="+setcpuaffinity"

count=0
while read -r z k; do
    case "$z" in ''|\#*) continue ;; esac
    win=$(printf "%.2f" "$z")

    if [ ! -f "us_${win}.conf" ]; then
        echo "!! 缺 us_${win}.conf，请先跑 ./setup_us.sh"
        exit 1
    fi

    # 断点续跑：已完成（日志里有 WallClock 完成标记）的窗口直接跳过
    if grep -q "WallClock" "us_${win}.log" 2>/dev/null; then
        echo ">> 跳过已完成窗口 Z = $win"
        continue
    fi

    # 清理未完成窗口的残留，避免 colvars.state 导致重启错乱
    rm -f "us_${win}.dcd" "us_${win}.colvars.traj" "us_${win}.colvars.state" \
          "us_${win}.colvars.state.old" "us_${win}.restart."* "us_${win}.vel" \
          "us_${win}.xsc" "us_${win}.xst" "us_${win}.coor" "us_${win}.log" 2>/dev/null

    echo ">> 后台提交窗口 Z = $win"
    nohup $NAMD +p$NTHREADS $AFFINITY +devices 0 us_${win}.conf > us_${win}.log 2>&1 &

    count=$((count+1))
    if [ "$count" -eq "$MAX_JOBS" ]; then
        echo ">> 已达最大并发 ($MAX_JOBS)，等待本批完成..."
        wait
        count=0
    fi
done < windows.txt

wait
echo "======================================================"
echo "全部 US 窗口完成。下一步：cd ../pmf && ./run_wham.sh"
echo "======================================================"
