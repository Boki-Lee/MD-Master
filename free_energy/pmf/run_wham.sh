#!/bin/bash
# ============================================================
#  提取 US 数据 + 跑 WHAM 算 PMF
#  剔除每个窗口前 EQUIL_STEPS 步（默认 0.5 ns）的平衡期
# ============================================================
set -e
cd "$(dirname "$0")"

PYTHON="${PYTHON:-/home/dell/anaconda3/envs/MD/bin/python}"
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
