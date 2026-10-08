#!/bin/bash
# ============================================================
#  calCurr.sh -- 并行计算离子电流（轴向 + 径向）
#
#  本项目协议：轴向恒定 5 V 直流 + 径向三角波 10 V/4 ns。
#  轴向电流 I_z 与径向电流 I_r(rs) 的定义见 ion-cur.tcl 头部注释。
#
#  用法（在 analysis/ 目录下执行）：
#      bash calCurr.sh                              # 进程数默认读 machine.conf 的 ANALYSIS_JOBS
#      bash calCurr.sh 16 10000                     # 指定进程数与总帧数
#      bash calCurr.sh 16 10000 "9.0 15.58 22.0"    # 指定径向统计柱面（Å）
#
#  原理：把 prod.dcd 的帧平均切成 $core 段，每段起一个 VMD 进程
#        跑 ion-cur.tcl，最后把各段的 curr*.dat 按顺序拼成 Acurr*.dat。
#
#  前置条件：../4prod/prod.dcd 已生成
#  产物：
#      AcurrTotal.dat    t(ns)  I_z(nA)                          总轴向电流
#      AcurrPOT.dat      t(ns)  I_z,K+(nA)                       阳离子轴向
#      AcurrCLA.dat      t(ns)  I_z,Cl-(nA)                      阴离子轴向
#      AcurrRadial.dat   t(ns)  I_r(rs1..rsN)  N_in(rs1..rsN)    径向电流 + 柱面占据数
#      radial_shells.txt 柱面半径清单（对应 AcurrRadial.dat 的列）
# ============================================================

# ---- 机器自适应配置（首次使用：bash bench_namd.sh）----
CONF="${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}"
if [ -r "$CONF" ]; then
    . "$CONF"
else
    echo "⚠ 未找到机器配置 $CONF —— 首次使用请先跑 bash bench_namd.sh（本次用保守默认值）" >&2
    [ "${MD_MASTER_STRICT:-0}" = "1" ] && { echo "MD_MASTER_STRICT=1，退出"; exit 1; }
fi
VMD="${VMD:-$(command -v vmd || true)}"
[ -n "$VMD" ] || { echo "ERROR: 找不到 vmd（设 VMD=/path/to/vmd，或先跑 bench_namd.sh）" >&2; exit 1; }

core=${1:-${ANALYSIS_JOBS:-4}}
frames=${2:-10000}
shells=${3:-"9.0 15.58 22.0"}

finish="finish.txt"
[ -f "$finish" ] && rm -f "$finish"

dframes=$((frames / core))

# ---- 为每个进程生成一份带参数的临时脚本 ----
for ((i = 0; i < core; i++)); do
    echo -n "$i "
    first=$((i * dframes))
    totalFrames=$dframes
    # 最后一段把余下的帧都拿走，保证总数正好是 $frames
    if [ $i = $((core - 1)) ]; then
        ((totalFrames = frames - i * dframes))
    fi
    cp ion-cur.tcl temp-ion-cur_$i.tcl
    # 在第 1 行插入四个变量（ion-cur.tcl 里会用到）
    sed -i "1iset first $first"            temp-ion-cur_$i.tcl
    sed -i "1iset totalFrames $totalFrames" temp-ion-cur_$i.tcl
    sed -i "1iset index $i"                temp-ion-cur_$i.tcl
    sed -i "1iset shellRadii {$shells}"    temp-ion-cur_$i.tcl
done

echo ""
echo "启动 $core 个并行 VMD 任务（每段 $dframes 帧，径向柱面: $shells Å）..."

for ((i = 0; i < core; i++)); do
    "$VMD" -dispdev none -e temp-ion-cur_$i.tcl &
done

# ---- 等待所有任务完成（靠 finish_<i>.txt 标记）----
while true; do
    cnt=0
    for ((i = 0; i < core; i++)); do
        [ -f "finish_${i}.txt" ] && ((cnt++))
    done
    [ $cnt = $core ] && break
    sleep 2
done

sleep 3

# ---- 收集出现过的前缀（Total / POT / CLA / Radial）----
# ★ 必须严格匹配 "curr<名字>_<数字>.dat"：
#   旧写法 ^curr([^_]*)_ 会把 current_components.dat 匹配成 key="ent"，
#   然后在清理阶段被 "rm -f curr${key}_*.dat" 删掉（=删掉 current_*.dat）。
declare -A matches
for file in *; do
    if [[ -f $file && $file =~ ^curr([A-Za-z]+)_([0-9]+)\.dat$ ]]; then
        matches["${BASH_REMATCH[1]}"]=1
    fi
done

# ---- 按进程顺序拼接（第 0 段打头，其余追加）----
for key in "${!matches[@]}"; do
    cat "curr${key}_0.dat" > "Acurr${key}.dat"
done

for ((i = 1; i < core; i++)); do
    for key in "${!matches[@]}"; do
        cat "curr${key}_$i.dat" >> "Acurr${key}.dat"
    done
done

# ---- 清理中间文件 ----
for key in "${!matches[@]}"; do
    rm -f curr${key}_*.dat
done
rm -f temp-ion-cur_*.tcl finish_*

echo ""
echo "电流计算完成。输出文件："
ls -la Acurr*.dat radial_shells.txt 2>/dev/null
echo ""
echo "下一步（分析用 Python 环境按机器改，例如 conda activate MD）："
echo "  python plot_iv.py            # 径向 I_r-V_rad 回线 + 轴向直流工作点"
echo "  python plot_currents.py      # 电流分物种/分区的时间序列"
