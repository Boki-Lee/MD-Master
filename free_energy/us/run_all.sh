#!/bin/bash
# ============================================================
#  批量后台运行 US 窗口（分批并发，每批 MAX_JOBS 个）
#
#  用法：
#      ./run_all.sh                          # 并发路数/线程数读全局机器记忆 machine.conf
#      NTHREADS=32 MAX_JOBS=1 ./run_all.sh   # 单窗口顺序跑（唯一能用绑核的情况）
#      DRY_RUN=1 ./run_all.sh                # 只打印将要执行的命令，不真跑
#
#  并发参数从哪来：首次使用这套 skill 时先跑一次 `bash bench_namd.sh`，它实测出本机
#  最优的「并发路数 × 线程数」写进全局记忆，这里只负责读。
#  文档里"3 并发 × +p16、约 2030 步/秒"是开发机（52 核 Xeon + RTX 4090）的数值，
#  换机器务必用 bench_namd.sh 重测，别照抄。
#
#  注意：NAMD 是 CUDA 编译版，必须有 GPU 设备（/dev/nvidia*）。
#  ⚠️ 多进程并发时【严禁 +setcpuaffinity】：实测它会把所有 namd3 进程都钉到 CPU 0，
#     吞吐暴跌几十倍。只有单窗口顺序跑（MAX_JOBS=1）才用绑核。
# ============================================================
set -e
cd "$(dirname "$0")"

# ---- 机器自适应配置（首次使用：bash bench_namd.sh）----
CONF="${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}"
if [ -r "$CONF" ]; then
    . "$CONF"
else
    echo "⚠ 未找到机器配置 $CONF —— 首次使用请先跑 bash bench_namd.sh（本次用保守默认值）" >&2
    [ "${MD_MASTER_STRICT:-0}" = "1" ] && { echo "MD_MASTER_STRICT=1，退出"; exit 1; }
fi

NAMD="${NAMD:-$(command -v namd3 || command -v namd2 || true)}"
NTHREADS="${NTHREADS:-${CONC_NTHREADS:-${SINGLE_NTHREADS:-8}}}"
MAX_JOBS="${MAX_JOBS:-${CONC_MAX_JOBS:-1}}"
DEVICES="${DEVICES:-0}"

# 只有单窗口顺序跑（MAX_JOBS=1）才允许绑核；多并发一律不绑
AFFINITY=""
[ "$MAX_JOBS" = "1" ] && AFFINITY="${SINGLE_AFFINITY:-}"

[ -n "$NAMD" ] || { echo "ERROR: 找不到 namd3/namd2（设 NAMD=/path/to/namd3，或先跑 bench_namd.sh）" >&2; exit 1; }

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

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "   [dry-run] $NAMD +p$NTHREADS${AFFINITY:+ $AFFINITY} +devices $DEVICES us_${win}.conf > us_${win}.log 2>&1 &"
    else
        echo ">> 后台提交窗口 Z = $win"
        nohup $NAMD +p$NTHREADS${AFFINITY:+ $AFFINITY} +devices $DEVICES us_${win}.conf > us_${win}.log 2>&1 &
    fi

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
