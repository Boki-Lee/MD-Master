#!/bin/bash
# ============================================================
#  提取 US 数据 + 跑 WHAM 算 PMF
#  剔除每个窗口前 EQUIL_STEPS 步（默认 0.5 ns）的平衡期
# ============================================================
set -e
cd "$(dirname "$0")"

# ---- 机器自适应配置（首次使用：bash bench_namd.sh）----
CONF="${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}"
if [ -r "$CONF" ]; then
    . "$CONF"
else
    echo "⚠ 未找到机器配置 $CONF —— 首次使用请先跑 bash bench_namd.sh（本次自动探测 python）" >&2
    [ "${MD_MASTER_STRICT:-0}" = "1" ] && { echo "MD_MASTER_STRICT=1，退出"; exit 1; }
fi
PYTHON="${PYTHON:-$(command -v python3 || true)}"
if [ -n "$PYTHON" ] && ! "$PYTHON" -c 'import numpy' >/dev/null 2>&1; then
    echo "⚠ $PYTHON 缺 numpy，WHAM 会失败（换机器时用 PYTHON=/path/to/python 指定分析环境）" >&2
fi
[ -n "$PYTHON" ] || { echo "ERROR: 找不到 python3（设 PYTHON=...，或先跑 bench_namd.sh）" >&2; exit 1; }
EQUIL_STEPS="${EQUIL_STEPS:-250000}"

rm -f metadata.txt data_*.txt

echo ">> 剔除每窗口前 $EQUIL_STEPS 步平衡期，提取数据..."
while read -r z k; do
    case "$z" in ''|\#*) continue ;; esac
    win=$(printf "%.2f" "$z")
    traj="../us/us_${win}.colvars.traj"
    if [ ! -f "$traj" ]; then
        echo "警告: 缺 $traj，跳过"
        continue
    fi
    awk -v es="$EQUIL_STEPS" '!/^#/ && $1 > es {print $1, $2}' "$traj" > "data_${win}.txt"
    echo "data_${win}.txt  ${win}  ${k}" >> metadata.txt
done < ../us/windows.txt

echo ">> 跑 WHAM ..."
$PYTHON wham.py metadata.txt -T 300 --bin 0.01 -o pmf.txt
echo "======================================================"
echo "完成：PMF 在 pmf.txt（第 1 列 z(Å)，第 2 列 PMF(kcal/mol)）"
echo "绘图：$PYTHON plot_pmf.py"
echo "======================================================"
