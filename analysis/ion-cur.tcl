# ============================================================
#  ion-cur.tcl -- 从 prod 轨迹计算离子电流（轴向 + 径向）
#
#  本项目协议（见 4prod/README.md）：轴向恒定 5 V 直流 + 径向三角波 10 V/4 ns。
#  所以电流有两条：
#
#    ① 轴向电流 I_z（沿管轴）
#       每 freq 步统计阳/阴离子沿 z 的位移合计：
#           I_z = Σ qi·Δzi /(Lz·Δt)
#       跨周期性边界的位移用最小镜像修正。
#
#    ② 径向电流 I_r(rs)（穿过以管轴为中心、半径 rs 的圆柱面）
#           I_r(rs) = −ΔQ_in(rs) / Δt
#       其中 Q_in(rs) = Σ qi [ ri < rs ] 是柱面内的净电荷。
#       柱面内电荷只能靠"穿过柱面"改变，所以这个式子和"数穿越次数"
#       完全等价，但不用逐次判断穿越、也不会漏掉来回穿的情况。
#       r 由离子相对管轴的位移算出，做了最小镜像。
#
#  用法：
#    由 calCurr.sh 自动调用（它会用 sed 在第 1 行插入
#    $first / $totalFrames / $index，实现分段并行）
#    手动单进程：vmd -dispdev none -e ion-cur.tcl
#
#  产物（$index 是分段号）：
#    currTotal_$index.dat     t(ns)  I_z(nA)           总轴向
#    currPOT_$index.dat       t(ns)  I_z,K+            阳离子轴向
#    currCLA_$index.dat       t(ns)  I_z,Cl-           阴离子轴向
#    currRadial_$index.dat    t(ns)  I_r(rs1..rsN)  N_in(rs1..rsN)
#    radial_shells.txt        （只有 index=0 写）柱面半径清单
# ============================================================

# ---- 允许 calCurr.sh 用 sed 在第 1 行覆盖的参数 ----
if {![info exists first]}       { set first 0 }
if {![info exists totalFrames]} { set totalFrames 100 }
if {![info exists index]}       { set index 0 }
# 径向电流统计的柱面半径（Å），从小到大
if {![info exists shellRadii]}  { set shellRadii {9.0 15.58 22.0} }

# ============================================================
#  工具函数
# ============================================================

# 计算一组粒子沿某方向的位移合计（含最小镜像修正）
proc calParticleTotalDisplacement {p1Partical p2Partical length} {
    set PDis 0.0
    foreach p1 $p1Partical p2 $p2Partical {
        set dp [expr {$p2 - $p1}]
        # 跨周期性边界：位移超过半个盒子就折回来
        if {$dp > 0.5 * $length} {
            set dp [expr {$dp - $length}]
        } elseif {$dp < -0.5 * $length} {
            set dp [expr {$dp + $length}]
        }
        set PDis [expr {$PDis + $dp}]
    }
    return $PDis
}

# 统计离子在若干同心圆柱面内的净电荷与个数
#   返回扁平列表 {q1 n1 q2 n2 ...}，对应 shellRadii 的每个半径
#   半径从大到小判断，落在最外层之外就直接 break（大部分离子都这样，省时间）
proc calShellOccupancy {xs ys qs shellRadii ox oy lx ly} {
    set nShell [llength $shellRadii]
    set qin [lrepeat $nShell 0.0]
    set nin [lrepeat $nShell 0]
    foreach x $xs y $ys q $qs {
        # 相对管轴的位移 + 最小镜像
        set dx [expr {$x - $ox}]
        set dx [expr {$dx - $lx * floor($dx / $lx + 0.5)}]
        set dy [expr {$y - $oy}]
        set dy [expr {$dy - $ly * floor($dy / $ly + 0.5)}]
        set r [expr {sqrt($dx*$dx + $dy*$dy)}]
        for {set j [expr {$nShell - 1}]} {$j >= 0} {incr j -1} {
            if {$r < [lindex $shellRadii $j]} {
                lset qin $j [expr {[lindex $qin $j] + $q}]
                lset nin $j [expr {[lindex $nin $j] + 1}]
            } else {
                break
            }
        }
    }
    set out {}
    for {set j 0} {$j < $nShell} {incr j} {
        lappend out [lindex $qin $j] [lindex $nin $j]
    }
    return $out
}

mol delete all

# 体系名与输出前缀
set model_name system_ion
# 每次统计跨过的帧数（对应 dcdfreq 的采样间隔）
set baseFrames 10
# 采样间隔（步）与积分步长（s），需与 prod.conf 一致
set freq 1000
set dt 2e-15

# 阳离子 / 阴离子名称与电荷
set nameCat POT
set qCat 1.0
set nameAn CLA
set qAn -1.0

set outputcurr    "currTotal_$index.dat"
set outputcurrCat "curr${nameCat}_$index.dat"
set outputcurrAn  "curr${nameAn}_$index.dat"
set outputrad     "currRadial_$index.dat"

# 轨迹与结构文件（本脚本在 analysis/ 下运行，七文件夹结构）
# 这几个也允许外部覆盖，方便拿别的轨迹做冒烟测试
if {![info exists dcdFile]} { set dcdFile ../4prod/prod_full.dcd }
if {![info exists psf]}     { set psf     ../1model/${model_name}.psf }
if {![info exists pdb]}     { set pdb     ../1model/${model_name}.pdb }
if {![info exists xscFile]} { set xscFile ../3eq/eq.restart.xsc }
# 离子 ID 文件这里没直接用：径向电流按"选中的 POT/CLA 原子"统计，
# 与 1model/ion_ids.dat 是同一批原子（check_setup.py 会校验两者一致）。

mol load psf $psf pdb $pdb

set selCat [atomselect top "name $nameCat"]
set selAn  [atomselect top "name $nameAn"]
set selIon [atomselect top "name $nameCat or name $nameAn"]

# 每个被选中的离子的电荷（顺序与 selIon 的 get x/y 一致，按名字映射，不依赖排列）
set ionQs {}
foreach nm [$selIon get name] {
    lappend ionQs [expr {$nm eq $nameCat ? $qCat : $qAn}]
}
set nShell [llength $shellRadii]

set out    [open "$outputcurr"    w]
set outCat [open "$outputcurrCat" w]
set outAn  [open "$outputcurrAn"  w]
set outRad [open "$outputrad"     w]
if {$index == 0} {
    set fr [open "radial_shells.txt" w]
    puts $fr [join $shellRadii " "]
    close $fr
}

# 电流沿 z 方向计算（轴向）；径向按到管轴的距离算
set origin z
animate delete all
mol addfile $dcdFile type dcd first 0 last 1 waitfor all

# 盒子与管轴：从 eq 的 xsc 读（最可靠，等于成品模拟所用的盒子）。
# 注意 NAMD 里 (o_x, o_y) 是盒子中心，本项目管轴正好在那里。
set ll 0.0
set lx 0.0
set ly 0.0
set ox 0.0
set oy 0.0
if {[file exists $xscFile]} {
    set fp [open $xscFile r]
    set lines [split [read $fp] "\n"]
    close $fp
    foreach line $lines {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} continue
        set d [regexp -inline -all {\S+} $line]
        if {[llength $d] < 13} continue
        set lx [expr {abs([lindex $d 1])}]
        set ly [expr {abs([lindex $d 5])}]
        set ll [expr {abs([lindex $d 9])}]
        set ox [lindex $d 10]
        set oy [lindex $d 11]
        break
    }
}
if {$ll <= 0.0} {
    switch $origin {
        "x" {set ll [molinfo top get a]}
        "y" {set ll [molinfo top get b]}
        "z" {set ll [molinfo top get c]}
        default {puts "ERROR: unknown origin"; quit}
    }
}
if {$lx <= 0.0} { set lx [molinfo top get a] }
if {$ly <= 0.0} { set ly [molinfo top get b] }
puts "Box: Lx=$lx Ly=$ly Lz=$ll  tube axis=($ox, $oy)  (应与 eq 平衡后的盒子一致)"
puts "Radial shells (A): $shellRadii"

# 轴向电流换算因子：I(nA) = Σqi·Δzi(e·Å) × currFactor
set currFactor [expr (1.60217733e-10) / ($ll * $dt * $freq)]
# 径向电流换算因子：I(nA) = ΔQ_in(e) / Δt × currRadFactor
# Δt = dt·freq 秒；1 e/Δt = 1.602177e-19/(2e-12) A = 80.11 nA
set currRadFactor [expr (1.60217733e-10) / ($dt * $freq)]
# 每帧对应的物理时间（ns）
set timeFactor [expr $dt * $freq * 1.0e9]

# 上一帧的柱面内电荷（用于差分）
set prevQin {}

for {set i 0} {$i < $totalFrames} {set i [expr {$i + $baseFrames}]} {
    animate delete all
    set f1 [expr {$first + $i}]
    if {[expr {$totalFrames - $i}] < $baseFrames} {
        set f2 [expr {$f1 + $totalFrames - $i}]
    } else {
        set f2 [expr {$f1 + $baseFrames}]
    }

    mol addfile $dcdFile type dcd first $f1 last $f2 waitfor all

    set nFrames [molinfo top get numframes]
    for {set f 0} {$f < [expr {$nFrames - 1}]} {incr f} {
        molinfo top set frame $f
        set p1Cat [$selCat get $origin]
        set p1An  [$selAn  get $origin]

        molinfo top set frame [expr {$f + 1}]
        set p2Cat [$selCat get $origin]
        set p2An  [$selAn  get $origin]
        # 只需要"后一帧"的柱面占据；前一帧的由 prevQin 带过来
        set occ2 [calShellOccupancy [$selIon get x] [$selIon get y] $ionQs \
                                     $shellRadii $ox $oy $lx $ly]
        # 全局第一帧没有"前一帧"，补算一次（整个运行只发生一次，代价可忽略）
        if {[llength $prevQin] == 0} {
            molinfo top set frame $f
            set prevQin [calShellOccupancy [$selIon get x] [$selIon get y] $ionQs \
                                             $shellRadii $ox $oy $lx $ly]
            molinfo top set frame [expr {$f + 1}]
        }

        set currCat [expr {[calParticleTotalDisplacement $p1Cat $p2Cat $ll] * $currFactor * $qCat}]
        set currAn  [expr {[calParticleTotalDisplacement $p1An  $p2An  $ll] * $currFactor * $qAn}]

        set time [expr {($first + $i + $f + 0.5) * $timeFactor}]
        set currTotal [expr {$currCat + $currAn}]

        puts $out    "$time $currTotal"
        puts $outCat "$time $currCat"
        puts $outAn  "$time $currAn"

        # ---- 径向电流：I_r = −ΔQ_in/Δt ----
        set radCurr {}
        set radOcc  {}
        for {set j 0} {$j < $nShell} {incr j} {
            set q2 [lindex $occ2 [expr {2 * $j}]]
            set n2 [lindex $occ2 [expr {2 * $j + 1}]]
            if {[llength $prevQin] > 0} {
                set q1 [lindex $prevQin [expr {2 * $j}]]
                lappend radCurr [expr {-($q2 - $q1) * $currRadFactor}]
            } else {
                lappend radCurr 0.0
            }
            lappend radOcc $n2
        }
        set prevQin $occ2
        if {[llength $radCurr] > 0} {
            puts $outRad "$time [join $radCurr " "] [join $radOcc " "]"
        }
    }
}

close $out
close $outCat
close $outAn
close $outRad

# 写完一个分段就留下标记文件，供 calCurr.sh 判断是否全部完成
set finish [open "finish_$index.txt" w]
close $finish
