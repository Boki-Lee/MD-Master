# ============================================================
#  field_axial_dc_radial_tri.tcl
#  轴向恒定电压  +  从管轴向外辐射的径向三角波电压
#  （NAMD tclForces 脚本，替换旧的 triangle_field.tcl）
#
#  【物理模型】
#    轴向（沿管轴 +z）：电压恒定 V_axial（默认 5 V），空间均匀
#        Ez = eFieldFactor * V_axial / Lz          [kcal/(mol·Å·e)]
#        Fz = q * Ez                                 （正离子被推向 +z）
#
#    径向（从管中心向外辐射）：柱对称 1/r 电场，电压为三角波
#        V_rad(t)：0 → +Vmax → −Vmax → 0，周期 period_ns
#        Er(r,t) = eFieldFactor * V_rad(t) / ( r * ln(R_out / r_in) )
#        r < r_in 时用 r_in 截断（1/r 在管轴处发散，必须截断）
#        (Fx,Fy) = q * Er * r̂ ，  r̂ = (dx,dy)/|(dx,dy)|
#        V_rad > 0 ：电场指向"远离管轴"，正离子被推离管轴、负离子被拉向管轴
#        V_rad < 0 ：反向
#
#    合起来： F = q * ( Er * r̂ + Ez * ẑ )
#
#  【1/r 里那两个参考半径怎么理解】
#    V_rad(t) 定义为「r = r_in 处」到「r = R_out 处」的电位差：
#        V_rad = ∫ Er dr = C * ln(R_out/r_in)   ⇒   C = V_rad / ln(R_out/r_in)
#    默认 r_in = 2.0 Å（≈ 离子+第一水合层尺度，同时充当数值截断），
#    R_out = 0.0 表示自动取盒子横截面内切半径 min(Lx,Ly)/2 ≈ 25.6 Å。
#    想改场强量级，改这两个比改 Vmax 更"物理"。
#
#  【坐标怎么拿到】
#    tclForces 不直接给坐标，必须先在脚本顶层 addatom 登记，
#    再在 calcforces 里 loadcoords 取（见 NAMD 手册 "Tcl Forces and Analysis"）。
#    登记后取到的是"上一步"的坐标，2 fs 的滞后可忽略。
#    152 个离子的开销实测 < 5%（见 4prod/README.md）。
#
#  【运行】在 4prod/ 目录下，conf 里写：
#        tclForces        on
#        tclForcesScript  field_axial_dc_radial_tri.tcl
#
#  【覆盖参数/路径】conf 里预先赋值即可（本脚本用 info exists 保护默认值）：
#        tclForcesScript {
#            set ionFile "/绝对路径/ion_ids.dat"
#            set xscFile "/绝对路径/eq.restart.xsc"
#            set vmaxRad 8.0
#            source ./field_axial_dc_radial_tri.tcl
#        }
#
#  【离线自检】 tclsh selftest_field.tcl     （不需要 NAMD）
#
#  【版本说明】2026-10-05
#    prod（0~16.96 ns）和 prod2（16.96~20 ns）是用**本文件的计算部分**跑出来的，
#    那部分一个字没动。之后只改了两处**只影响日志/健壮性、不影响受力**的地方：
#      · 日志改成"续算时追加、新运行时重开"，避免续算把前面的波形记录截断
#        （prod2 启动时就这样截断过一次，好在公式能完整还原，见 5analysis/README.md）
#    所以已有轨迹依然有效，受力与它们完全一致。
# ============================================================


# ============================================================
#  1. 参数区（conf 里预先 set 同名变量即可覆盖）
# ============================================================

# 单位换算：1 V/Å = 23.06054917 kcal/(mol·Å·e)
if {![info exists eFieldFactor]} { set eFieldFactor 23.06054917 }

# 轴向恒定电压（V）
if {![info exists vAxial]}      { set vAxial      5.0 }

# 径向三角波峰值电压（V）与周期（ns）
if {![info exists vmaxRad]}     { set vmaxRad     10.0 }
if {![info exists periodRad]}   { set periodRad   4.0 }

# 径向波形：1 = 双极性三角波（0→+Vmax→−Vmax→0，与旧轴向三角波同形）
#           0 = 整流三角波（|V| 始终向外，只推不拉）
if {![info exists triBipolar]}  { set triBipolar  1 }

# 径向 1/r 的内参考半径（Å）：决定"径向电压"的基准，同时是 r→0 的截断
if {![info exists rIn]}         { set rIn         2.0 }
# 径向 1/r 的外参考半径（Å）：<=0 表示自动取 min(Lx,Ly)/2（盒子横截面内切半径）
if {![info exists rOut]}        { set rOut        0.0 }

# 管轴位置（Å）：默认 auto（从 xsc 的盒子中心取）。
# 本项目建模时把管子放在 x=y=0，NAMD 的 PERIODIC CELL CENTER 也是 (0,0,39.911)，
# 所以轴心 == 盒子横截面中心。若以后管子不居中，在这里手填覆盖。
if {![info exists axisX]}       { set axisX       "auto" }
if {![info exists axisY]}       { set axisY       "auto" }

# 积分步长（fs）：必须与 conf 里的 timestep 一致，用于把步数换成时间
if {![info exists dtFs]}        { set dtFs        2.0 }

# 诊断输出：每隔多少步打印/记录一行（<=0 表示只在第 0 步打印一次）
if {![info exists printEvery]}  { set printEvery  25000 }
# 是否把电压/电场写进日志文件（交给后面的分析脚本用）
if {![info exists writeLog]}    { set writeLog    1 }
if {![info exists logFile]}     { set logFile     "field_log.dat" }

# 画日志用的"管壁半径"（Å），只影响日志里 Er@wall 这一列
if {![info exists tubeR]}       { set tubeR       15.58 }

# 数据文件（相对 4prod/ 运行目录）
if {![info exists ionFile]}     { set ionFile     "../1model/ion_ids.dat" }
if {![info exists xscFile]}     { set xscFile     "../3eq/eq.restart.xsc" }
# 读不到 xsc 时的兜底盒子（旧项目 eq 后的实测值）
if {![info exists fallbackLz]}  { set fallbackLz  87.539 }
if {![info exists fallbackLxy]} { set fallbackLxy 51.15 }


# ============================================================
#  2. 纯数学函数（不依赖 NAMD，离线自检脚本也调用这几个）
# ============================================================

# 三角波电压：t_ns 时刻的电压
#   t=0 → 0 ；t=T/4 → +vmax ；t=3T/4 → −vmax ；t=T → 0
#   bipolar=0 时取绝对值（整流，始终向外）
proc triWave {t_ns period_ns vmax bipolar} {
    set n_p  [expr {int(floor($t_ns / $period_ns))}]
    set tmod [expr {$t_ns - $n_p * $period_ns}]
    set qt   [expr {$period_ns / 4.0}]
    set hf   [expr {$period_ns / 2.0}]
    if {$tmod < $qt} {
        set V [expr {$vmax * $tmod / $qt}]
    } elseif {$tmod < 3.0 * $qt} {
        set V [expr {$vmax * (1.0 - 2.0 * ($tmod - $qt) / $hf)}]
    } else {
        set V [expr {$vmax * ($tmod - $period_ns) / $qt}]
    }
    if {!$bipolar} { set V [expr {abs($V)}] }
    return $V
}

# 最小镜像：把沿某个盒子边的位移 d 折进 [-L/2, L/2)
# （离子被 NAMD 折回原胞时坐标会跳一个盒子长，必须折回来）
proc minImage {d L} {
    if {$L <= 0.0} { return $d }
    return [expr {$d - $L * floor($d / $L + 0.5)}]
}

# 径向 1/r 场的对数因子 ln(R_out/r_in)
proc radialLogRatio {rIn rOut} {
    return [expr {log($rOut / $rIn)}]
}

# 径向电场强度（V/Å，不含 eFieldFactor）：Er(r) = V / (r·ln(R_out/r_in))
proc radialEr {V r rIn rOut} {
    if {$r < $rIn} { set r $rIn }
    return [expr {$V / ($r * [radialLogRatio $rIn $rOut])}]
}

# 单个离子的受力（kcal/(mol·Å)），返回 {fx fy fz}
#   q        电荷(e)
#   kRad     = eFieldFactor * V_rad / ln(R_out/r_in)   （径向场系数）
#   dx,dy    离子相对管轴的位移（Å，已做最小镜像）
#   Ez       轴向电场（kcal/(mol·Å·e)）
#
# ★ 注意：calcforces 是热路径，里面的同一套算式是**内联**写的（不调这个 proc），
#   两边必须保持一致。selftest_field.tcl 校验的是这个 proc 版本，
#   _selftest/mock_namd.tcl + check_force.py 校验的是 calcforces 的内联版本，
#   两者都对同一套闭式解做过对照。
proc ionForce {q kRad dx dy rIn Ez} {
    set r2 [expr {$dx*$dx + $dy*$dy}]
    if {$r2 < 1.0e-12} { return [list 0.0 0.0 [expr {$q * $Ez}]] }
    set rt [expr {sqrt($r2)}]
    # 1/r 截断：r < r_in 时力不再增大
    set rc $rt
    if {$rc < $rIn} { set rc $rIn }
    # F_r 大小 = q*kRad/rc，方向 r̂ = (dx,dy)/rt
    set s [expr {$q * $kRad / $rc / $rt}]
    return [list [expr {$s * $dx}] [expr {$s * $dy}] [expr {$q * $Ez}]]
}

# 从 NAMD 的 .xsc 文件读盒子：返回 {Lx Ly Lz ox oy skew}，读失败返回 {}
#   xsc 第 3 行格式：step a_x a_y a_z b_x b_y b_z c_x c_y c_z o_x o_y o_z ...
#   注意 NAMD 里 o_x,o_y,o_z 是"盒子中心"（本项目管轴正好在 (o_x,o_y)）
proc readXscBox {fn} {
    if {![file exists $fn]} { return {} }
    set fp [open $fn r]
    set lines [split [read $fp] "\n"]
    close $fp
    foreach line $lines {
        set line [string trim $line]
        if {$line eq ""} continue
        if {[string index $line 0] eq "#"} continue
        set d [regexp -inline -all {\S+} $line]
        if {[llength $d] < 13} continue
        set ax [lindex $d 1]; set ay [lindex $d 2]; set az [lindex $d 3]
        set bx [lindex $d 4]; set by [lindex $d 5]; set bz [lindex $d 6]
        set cx [lindex $d 7]; set cy [lindex $d 8]; set cz [lindex $d 9]
        set ox [lindex $d 10]; set oy [lindex $d 11]
        set Lx [expr {sqrt($ax*$ax + $ay*$ay + $az*$az)}]
        set Ly [expr {sqrt($bx*$bx + $by*$by + $bz*$bz)}]
        set Lz [expr {sqrt($cx*$cx + $cy*$cy + $cz*$cz)}]
        # 非对角项之和：用来判断盒子是否正交（正交时≈0）
        set skew [expr {abs($ay)+abs($az)+abs($bx)+abs($bz)+abs($cx)+abs($cy)}]
        return [list $Lx $Ly $Lz $ox $oy $skew]
    }
    return {}
}


# ============================================================
#  3. 模式判断：NAMD 里才有 addatom；没有就进"自检模式"
# ============================================================
if {[info commands addatom] eq ""} {

    puts "\[field_axial_dc_radial_tri.tcl\] no NAMD 'addatom' command found -> selftest mode"
    puts "\[field_axial_dc_radial_tri.tcl\] params and math procs defined; no atom registered, no force applied."
    puts "\[field_axial_dc_radial_tri.tcl\] for the waveform/field tables run: tclsh selftest_field.tcl"

} else {

    # ---------------- 3.1 读盒子 ----------------
    set _box [readXscBox $xscFile]
    if {[llength $_box] >= 6} {
        set Lx    [lindex $_box 0]
        set Ly    [lindex $_box 1]
        set Lz    [lindex $_box 2]
        set _ox   [lindex $_box 3]
        set _oy   [lindex $_box 4]
        set _skew [lindex $_box 5]
        print "field: box from $xscFile -> Lx=[format %.3f $Lx] Ly=[format %.3f $Ly] Lz=[format %.3f $Lz] origin=([format %.3f $_ox], [format %.3f $_oy])"
        if {$_skew > 1.0e-3} {
            print "field: WARNING cell is not orthogonal (off-diagonal sum=$_skew); min-image uses the orthogonal approximation"
        }
    } else {
        set Lx $fallbackLxy
        set Ly $fallbackLxy
        set Lz $fallbackLz
        set _ox 0.0
        set _oy 0.0
        print "field: ERROR cannot read $xscFile; falling back to Lx=Ly=$Lx Lz=$Lz"
    }

    # 管轴：默认取盒子横截面中心，可用 axisX/axisY 覆盖
    if {$axisX eq "auto"} { set axisX $_ox }
    if {$axisY eq "auto"} { set axisY $_oy }

    # 径向外参考半径：默认盒子横截面内切半径
    if {$rOut <= 0.0} { set rOut [expr {0.5 * ($Lx < $Ly ? $Lx : $Ly)}] }

    # 径向场对数因子（必须为正）
    set lnRatio [radialLogRatio $rIn $rOut]
    if {$lnRatio <= 0.0} {
        error "field: rOut ($rOut) must be larger than rIn ($rIn); ln(R_out/r_in)=$lnRatio"
    }

    # ---------------- 3.2 读离子列表并登记坐标请求 ----------------
    if {![file exists $ionFile]} {
        error "field: ion list not found: $ionFile (run from 4prod/ ? check 1model/ion_ids.dat)"
    }
    set ionIDs     {}
    set ionCharges {}
    set fp [open $ionFile r]
    set data [split [read $fp] "\n"]
    close $fp
    foreach line $data {
        set line [string trim $line]
        if {$line eq ""} continue
        if {[string index $line 0] eq "#"} continue
        set parts [regexp -inline -all {\S+} $line]
        if {[llength $parts] >= 2} {
            lappend ionIDs     [lindex $parts 0]
            lappend ionCharges [lindex $parts 1]
        }
    }
    set nIon [llength $ionIDs]
    if {$nIon == 0} { error "field: no ions parsed from $ionFile" }

    # ★ 关键：必须先 addatom 登记，calcforces 里的 loadcoords 才拿得到坐标
    foreach id $ionIDs { addatom $id }

    # ---------------- 3.3 预计算常数 ----------------
    # 轴向恒定电场（kcal/(mol·Å·e)）与它的 V/Å 表示（日志用）
    set EzConst [expr {$eFieldFactor * $vAxial / $Lz}]
    set EzPerA  [expr {$vAxial / $Lz}]
    # 径向场系数：Er = kRadCoef / r
    set kRadCoef [expr {$eFieldFactor / $lnRatio}]

    # 热路径用的扁平离子表：每 3 个元素 = 一个离子 {id  q·kRadCoef  q·Ez}
    # qk 和 fz 都是常量，预先算好，省掉每步的电荷查表和两次乘法
    set ionPairs {}
    set _n [llength $ionIDs]
    for {set _i 0} {$_i < $_n} {incr _i} {
        set _q [lindex $ionCharges $_i]
        lappend ionPairs [lindex $ionIDs $_i] [expr {$_q * $kRadCoef}] [expr {$_q * $EzConst}]
    }

    if {$triBipolar} { set _mode "bipolar (0 -> +Vmax -> -Vmax -> 0)" } else { set _mode "rectified (always outward)" }

    print "field: ============================================================"
    print "field: axial DC      V = [format %.3f $vAxial] V  ->  Ez = [format %.6f [expr {$EzConst / $eFieldFactor}]] V/A = [format %.6f $EzConst] kcal/(mol.A.e)"
    print "field: radial tri    Vmax = [format %.3f $vmaxRad] V, period = [format %.3f $periodRad] ns, $_mode"
    print "field: radial 1/r    r_in = [format %.3f $rIn] A, R_out = [format %.3f $rOut] A, ln(R/r) = [format %.4f $lnRatio]"
    print "field: tube axis     (x,y) = ([format %.4f $axisX], [format %.4f $axisY])  min-image Lx = [format %.3f $Lx] Ly = [format %.3f $Ly]"
    print "field: peak Er        Er(r_in) = [format %.4f [expr {$vmaxRad / ($rIn * $lnRatio)}]] V/A ; Er(tube wall [format %.2f $tubeR] A) = [format %.4f [expr {$vmaxRad / ($tubeR * $lnRatio)}]] V/A"
    print "field: ions           = $nIon"
    print "field: ============================================================"

    # 日志文件的初始化推迟到第一次 calcforces（那时才知道本次运行的起始步数），
    # 以决定"接着写"还是"重开"——见下面的 logInit 分支。
    set logInit 0

    # ---------------- 3.4 每步回调 ----------------
    # ★ 这是热路径：152 个离子 × 1e7 步。所以最小镜像、1/r、截断全部内联进
    #   expr，不调用 proc —— Tcl 里一次 proc 调用 ≈ 0.4 us，三处 proc 就是
    #   每步 180 us 的纯开销。改完实测见 4prod/README.md 的"性能"一节。
    #   注意 rt 加了 1e-30：既避免 r=0 除零，又不需要额外分支
    #   （dx=dy=0 时 s 是有限大数，乘 0 仍得 0）。
    proc calcforces {} {
        global vmaxRad periodRad triBipolar rIn rOut
        global Lx Ly axisX axisY ionPairs
        global dtFs printEvery writeLog logFile logInit tubeR EzConst kRadCoef lnRatio vAxial EzPerA

        # 当前时间（ns）
        set step [getstep]
        set t_ns [expr {$step * $dtFs * 1.0e-6}]

        # 此刻的径向三角波电压（V）。注意 qk 里已经含了 eFieldFactor/ln(R/r_in)，
        # 所以这里 kr 就是电压本身，F_r = qk·kr / (max(r,r_in)·r)
        set kr [triWave $t_ns $periodRad $vmaxRad $triBipolar]

        # 取坐标（脚本顶层 addatom 登记过的原子）
        loadcoords p

        # 局部化，省掉循环里的 global 变量查找
        set ax $axisX; set ay $axisY
        set lx $Lx;    set ly $Ly
        set ri $rIn

        foreach {id qk fz} $ionPairs {
            if {![info exists p($id)]} continue
            lassign $p($id) x y zz
            # 相对管轴的位移 + 最小镜像（内联版 minImage）
            set dx [expr {($x - $ax) - $lx * floor(($x - $ax) / $lx + 0.5)}]
            set dy [expr {($y - $ay) - $ly * floor(($y - $ay) / $ly + 0.5)}]
            set rt [expr {sqrt($dx*$dx + $dy*$dy) + 1.0e-30}]
            # F_r = q·Er = qk·V_rad / (max(r,r_in)·r)，方向沿 r̂
            set s [expr {$qk * $kr / (($rt < $ri ? $ri : $rt) * $rt)}]
            addforce $id [list [expr {$s * $dx}] [expr {$s * $dy}] $fz]
        }

        # ---------- 诊断输出（每 printEvery 步一次，不在热路径的预算里）----------
        # 第一次调用先决定日志是"接着写"还是"重开"：
        #   续算（prod2 从 prod 的 restart 接上）时，日志的最后一步刚好在本次
        #   起始步之前 → 追加，不要把前面十几纳秒的波形记录截断；
        #   全新一次运行 → 重开并写表头。
        if {$writeLog && !$logInit} {
            set logInit 1
            set _append 0
            if {[file exists $logFile]} {
                set _fp [open $logFile r]
                set _last ""
                foreach _l [split [read $_fp] "\n"] {
                    set _l [string trim $_l]
                    if {$_l ne "" && [string index $_l 0] ne "#"} { set _last $_l }
                }
                close $_fp
                if {$_last ne ""} {
                    set _lastStep [lindex $_last 0]
                    set _win [expr {10 * ($printEvery > 0 ? $printEvery : 25000)}]
                    if {[string is integer -strict $_lastStep] && $step >= $_lastStep \
                        && ($step - $_lastStep) <= $_win} {
                        set _append 1
                    }
                }
            }
            set _fp [open $logFile [expr {$_append ? "a" : "w"}]]
            if {!$_append} {
                puts $_fp "# step  t_ns  V_axial_V  V_rad_V  Ez_V_per_A  Er_wall_V_per_A"
            }
            close $_fp
            print "field: log $logFile -> [expr {$_append ? {appending (continuation run)} : {new file}}]"
        }

        if {$step == 0 || ($printEvery > 0 && $step % $printEvery == 0)} {
            # kr 就是此刻的径向电压；管壁处的场强 Er = V / (r·ln(R_out/r_in))  [V/A]
            set vradNow $kr
            set erWall  [expr {$kr / ($tubeR * $lnRatio)}]
            print "field: step=$step t=[format %.4f $t_ns] ns  V_rad=[format %.4f $vradNow] V  Er(wall)=[format %.5f $erWall] V/A  Ez=[format %.5f $EzPerA] V/A"
            if {$writeLog} {
                set fp [open $logFile a]
                puts $fp [format "%10d %10.4f %8.3f %10.4f %12.6f %12.6f" \
                              $step $t_ns $vAxial $vradNow $EzPerA $erWall]
                close $fp
            }
        }
    }
}
