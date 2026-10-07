#!/usr/bin/env tclsh
# ============================================================
#  selftest_field.tcl  --  电场脚本离线自检（不需要 NAMD）
#
#  用法：
#      tclsh selftest_field.tcl                 # 用内置的旧项目盒子
#      tclsh selftest_field.tcl ../3eq/eq.restart.xsc
#
#  干三件事：
#    ① 断言：波形关键点、连续性、整流模式、1/r 截断、力的方向与大小
#    ② 出表：三角波波形表、径向场剖面表、离子受力/漂移速度
#    ③ 给量级：径向场 vs 旧轴向三角波，以及"要多大电压才和轴向可比"
#
#  本脚本 source 同目录的 field_axial_dc_radial_tri.tcl，
#  核对的公式就是 NAMD 里跑的那一套，不是另抄一份。
# ============================================================

set scriptDir [file dirname [info script]]
source [file join $scriptDir field_axial_dc_radial_tri.tcl]

# ---------- 盒子：命令行给了 xsc 就用它，否则用旧项目 eq 后的实测值 ----------
set Lx 51.152
set Ly 51.144
set Lz 87.539
set ox 0.0
set oy 0.0
set boxSrc "built-in (old project eq.restart.xsc values)"
if {[llength $argv] >= 1} {
    set b [readXscBox [lindex $argv 0]]
    if {[llength $b] >= 6} {
        set Lx [lindex $b 0]; set Ly [lindex $b 1]; set Lz [lindex $b 2]
        set ox [lindex $b 3]; set oy [lindex $b 4]
        set boxSrc [lindex $argv 0]
    } else {
        puts "!! cannot read xsc '[lindex $argv 0]', falling back to built-in box"
    }
}
if {$rOut <= 0.0} { set rOut [expr {0.5 * ($Lx < $Ly ? $Lx : $Ly)}] }

# ---------- 常量 ----------
set NA        6.02214076e23
set kcal2J    4184.0
set eV2kcal   23.0605489
set mK        39.0983
set mCl       35.453
set muK       7.6e-8
set muCl      7.91e-8
proc hr {} { puts "------------------------------------------------------------" }
proc hdr {s} { puts ""; puts "== $s"; hr }

set lnRatio [radialLogRatio $rIn $rOut]

puts "============================================================"
puts " field_axial_dc_radial_tri.tcl  --  offline self-test"
puts "============================================================"
puts [format " box      : Lx=%.3f  Ly=%.3f  Lz=%.3f  origin=(%.3f, %.3f)   source: %s" \
          $Lx $Ly $Lz $ox $oy $boxSrc]
puts [format " tube axis: (%.4f, %.4f)  (auto = box cross-section center)" $ox $oy]
puts [format " axial    : V = %.3f V  ->  Ez = %.6f V/A" $vAxial [expr {$vAxial / $Lz}]]
puts [format " radial   : Vmax = %.3f V, period = %.3f ns, r_in = %.3f A, R_out = %.3f A, ln(R/r) = %.4f" \
          $vmaxRad $periodRad $rIn $rOut $lnRatio]

# ============================================================
# ① 断言
# ============================================================
hdr "1. assertions"
set nPass 0
set nFail 0
proc check {name cond detail} {
    global nPass nFail
    if {$cond} {
        incr nPass
        puts [format "  \[PASS\] %-42s %s" $name $detail]
    } else {
        incr nFail
        puts [format "  \[FAIL\] %-42s %s" $name $detail]
    }
}
proc near {a b tol} { expr {abs($a - $b) <= $tol} }

set T $periodRad
check "triWave(t=0) = 0"            [near [triWave 0.0 $T $vmaxRad 1] 0.0 1e-9] \
      [format "V=%.6f" [triWave 0.0 $T $vmaxRad 1]]
check "triWave(t=T/4) = +Vmax"      [near [triWave [expr {$T/4.0}] $T $vmaxRad 1] $vmaxRad 1e-9] \
      [format "V=%.6f" [triWave [expr {$T/4.0}] $T $vmaxRad 1]]
check "triWave(t=3T/4) = -Vmax"     [near [triWave [expr {3.0*$T/4.0}] $T $vmaxRad 1] [expr {-$vmaxRad}] 1e-9] \
      [format "V=%.6f" [triWave [expr {3.0*$T/4.0}] $T $vmaxRad 1]]
check "triWave(t=T) = 0 (periodic)" [near [triWave $T $T $vmaxRad 1] 0.0 1e-9] \
      [format "V=%.6f" [triWave $T $T $vmaxRad 1]]
check "triWave continuous at T"     [near [triWave [expr {$T-1e-9}] $T $vmaxRad 1] 0.0 1e-6] \
      [format "V(T-1e-9)=%.3e" [triWave [expr {$T-1e-9}] $T $vmaxRad 1]]
check "triWave continuous at T/4"   [near [triWave [expr {$T/4.0-1e-9}] $T $vmaxRad 1] $vmaxRad 1e-5] \
      [format "V=%.6f" [triWave [expr {$T/4.0-1e-9}] $T $vmaxRad 1]]
check "triWave continuous at 3T/4"  [near [triWave [expr {3.0*$T/4.0-1e-9}] $T $vmaxRad 1] [expr {-$vmaxRad}] 1e-5] \
      [format "V=%.6f" [triWave [expr {3.0*$T/4.0-1e-9}] $T $vmaxRad 1]]
# 整流模式
set vmin 1e9; set vmaxSeen -1e9
for {set t 0.0} {$t < 2.0*$T} {set t [expr {$t + 0.01}]} {
    set v [triWave $t $T $vmaxRad 0]
    if {$v < $vmin} { set vmin $v }
    if {$v > $vmaxSeen} { set vmaxSeen $v }
}
check "rectified mode: 0 <= V <= Vmax" [expr {$vmin >= -1e-9 && [near $vmaxSeen $vmaxRad 1e-6]}] \
      [format "V in \[%.4f, %.4f\]" $vmin $vmaxSeen]
# 旧轴向三角波形状不变（10 V / 8 ns）
check "shape matches old axial tri-wave" [near [triWave [expr {8.0/4.0}] 8.0 10.0 1] 10.0 1e-9] \
      "old script 10V/8ns at T/4 -> +10"
# 最小镜像
check "minImage folds +1.5L -> -0.5L" [near [minImage [expr {1.5*$Lx}] $Lx] [expr {-0.5*$Lx}] 1e-9] \
      [format "%.4f" [minImage [expr {1.5*$Lx}] $Lx]]
check "minImage keeps small d"        [near [minImage 3.0 $Lx] 3.0 1e-9] "3.0 -> 3.0"
# 1/r 截断与单调性
check "Er clamped below r_in"   [near [radialEr $vmaxRad [expr {$rIn*0.1}] $rIn $rOut] \
                                      [radialEr $vmaxRad $rIn $rIn $rOut] 1e-12] \
      [format "Er(0.1*r_in)=Er(r_in)=%.4f V/A" [radialEr $vmaxRad $rIn $rIn $rOut]]
check "Er strictly decreasing in r" \
      [expr {[radialEr $vmaxRad 5.0 $rIn $rOut] > [radialEr $vmaxRad 10.0 $rIn $rOut] && \
             [radialEr $vmaxRad 10.0 $rIn $rOut] > [radialEr $vmaxRad 20.0 $rIn $rOut]}] \
      [format "%.4f > %.4f > %.4f" [radialEr $vmaxRad 5.0 $rIn $rOut] \
              [radialEr $vmaxRad 10.0 $rIn $rOut] [radialEr $vmaxRad 20.0 $rIn $rOut]]
# 电位差 = 定义的电压
set dV [expr {[radialEr $vmaxRad $rIn $rIn $rOut]*$rIn*$lnRatio}]
check "V(r_in -> R_out) = Vmax" [near $dV $vmaxRad 1e-6] [format "%.6f V" $dV]
# 力的方向：正电荷 + 正电压 -> 沿 +x 向外
set kRad [expr {$eFieldFactor * $vmaxRad / $lnRatio}]   ;# 与 calcforces 里的 kRadCoef*Vrad 一致
foreach {fx fy fz} [ionForce 1.0 $kRad 8.0 0.0 $rIn 0.0] {}
check "q>0, V>0 -> force outward (+x)" [expr {$fx > 0.0 && [near $fy 0.0 1e-12]}] [format "fx=%.4f" $fx]
foreach {fx fy fz} [ionForce -1.0 $kRad 8.0 0.0 $rIn 0.0] {}
check "q<0, V>0 -> force inward (-x)"  [expr {$fx < 0.0}] [format "fx=%.4f" $fx]
# 力的大小 = q*Er
set er8 [radialEr $vmaxRad 8.0 $rIn $rOut]
foreach {fx fy fz} [ionForce 1.0 $kRad 8.0 0.0 $rIn 0.0] {}
check "|F_r| = eFieldFactor * Er" [near [expr {abs($fx)}] [expr {$eFieldFactor*$er8}] 1e-9] \
      [format "%.6f vs %.6f" [expr {abs($fx)}] [expr {$eFieldFactor*$er8}]]
# 纯轴向
foreach {fx fy fz} [ionForce 1.0 0.0 8.0 3.0 $rIn 1.0] {}
check "kRad=0 -> pure axial force" [expr {$fx == 0.0 && $fy == 0.0 && [near $fz 1.0 1e-12]}] [format "fz=%.4f" $fz]
# r=0 不炸
foreach {fx fy fz} [ionForce 1.0 $kRad 0.0 0.0 $rIn 0.5] {}
check "r=0 handled (no NaN/div0)" [expr {$fx == 0.0 && $fy == 0.0 && [near $fz 0.5 1e-12]}] "radial part = 0"

puts ""
puts [format "  ==> %d passed, %d failed" $nPass $nFail]

# ============================================================
# ② 波形表
# ============================================================
hdr [format "2. radial triangular wave V(t)   (period %.3f ns, Vmax %.3f V)" $periodRad $vmaxRad]
puts "        t\[ns\]     V_rad\[V\]  (bipolar)     V_rad\[V\]  (rectified)"
for {set t 0.0} {$t <= 2.0*$periodRad + 1e-9} {set t [expr {$t + $periodRad/8.0}]} {
    puts [format "   %10.4f   %10.4f                %10.4f" $t \
              [triWave $t $periodRad $vmaxRad 1] [triWave $t $periodRad $vmaxRad 0]]
}

# ============================================================
# ③ 径向场剖面 + 离子受力
# ============================================================
hdr "3. radial field / force profile at the peak voltage"
puts "  r is the distance from the tube axis; Er is at |V_rad| = Vmax (peak)"
puts "  v_drift = mu*E is the bulk-water estimate (linear response, upper bound)"
puts ""
puts "     r\[A\]     Er\[V/A\]   Er\[V/nm\]   F_K\[kcal/mol/A\]   a_K\[A/ps^2\]   v_drift,K\[A/ps\]   dphi(r_in->r)\[V\]"
set prof {1.0 2.0 3.0 5.0 8.0 11.0 14.0 15.58 17.0 20.0 23.0 25.57 30.0 36.0}
foreach r $prof {
    set er [radialEr $vmaxRad $r $rIn $rOut]
    set fk [expr {$eFieldFactor * $er}]           ;# 单电荷离子受力
    set ak [expr {$fk * 418.4 / $mK}]
    set vd [expr {$muK * $er * 1.0e10 * 1.0e10 / 1.0e12}]   ;# m/s -> A/ps
    # 电位降 φ(r_in) − φ(r) = Vmax·ln(r/r_in)/ln(R/r_in)，到 R_out 处正好等于 Vmax
    set dV [expr {$vmaxRad * log($r/$rIn) / $lnRatio}]
    puts [format "  %7.2f  %9.5f  %9.4f  %15.4f  %13.2f  %16.4f  %14.4f" \
              $r $er [expr {$er*10.0}] $fk $ak $vd $dV]
}
puts ""
set dz [expr {$vAxial / $Lz}]
set fzK [expr {$eFieldFactor * $dz}]
puts [format "  axial reference : Ez = %.5f V/A, F_K = %.4f kcal/mol/A, a_K = %.2f A/ps^2, v_drift,K = %.4f A/ps" \
          $dz $fzK [expr {$fzK*418.4/$mK}] [expr {$muK*$dz*1.0e10*1.0e10/1.0e12}]]
puts [format "  ratio Er(wall)/Ez = %.2f ;  Er(r_in)/Ez = %.2f" \
          [expr {[radialEr $vmaxRad $tubeR $rIn $rOut]/$dz}] \
          [expr {[radialEr $vmaxRad $rIn $rIn $rOut]/$dz}]]

# ============================================================
# ④ 能量账 & 与旧轴向三角波对比
# ============================================================
hdr "4. energy budget and comparison with the old axial triangle wave"
set dVwall [expr {$vmaxRad * log($tubeR/$rIn) / $lnRatio}]
puts [format "  radial : one K+ drifting from r_in=%.1f A to the tube wall %.2f A gains %.3f eV" $rIn $tubeR $dVwall]
puts [format "           (by construction r_in -> R_out=%.2f A is exactly Vmax = %.3f eV)" $rOut $vmaxRad]
puts [format "  axial  : one K+ crossing the whole box Lz=%.2f A gains %.3f eV" $Lz $vAxial]
puts ""
puts "  old protocol (CNT/4prod/triangle_field.tcl): axial triangle, 10 V / 8 ns"
puts [format "     old Ez at peak = %.5f V/A  (=%.2f x the new constant axial Ez)" \
          [expr {10.0/$Lz}] [expr {(10.0/$Lz)/$dz}]]
puts ""
puts "  to make the radial field at the tube wall as weak as the axial one you would need"
puts [format "     Vmax_rad = Ez * R_tube * ln(R_out/r_in) = %.3f V   (instead of %.2f V)" \
          [expr {$dz * $tubeR * $lnRatio}] $vmaxRad]
puts [format "     lowering r_in only helps a little: with r_in = 1 A, Er(wall) = %.4f V/A (%.2f x Ez)" \
          [expr {$vmaxRad/($tubeR*[radialLogRatio 1.0 $rOut])}] \
          [expr {[expr {$vmaxRad/($tubeR*[radialLogRatio 1.0 $rOut])}]/$dz}]]
puts "     (this is geometry, not a bug: the radial span ~R_out is ~3.4x shorter than Lz)"

# ============================================================
# ⑤ 结论
# ============================================================
hdr "5. verdict"
if {$nFail == 0} {
    puts "  ALL CHECKS PASSED ($nPass/$nPass)"
} else {
    puts "  !!! $nFail CHECK(S) FAILED !!!"
}
puts ""
puts "  NOTE 1: 'all ions in the box' means the radial drive also acts on the"
puts "          bulk water outside the tube, which carries most of the current"
puts "          (the old axial run found ~79% outside vs ~21% inside the tube)."
puts "  NOTE 2: r_in doubles as the 1/r singularity cutoff. Nothing bad happens"
puts "          at r -> 0, but the force there is the largest in the system."
puts "  NOTE 3: the radial field alternates sign every ${periodRad}/2 ns, so a given"
puts "          ion is pushed out, then pulled back in - i.e. a radial AC drive."
puts "          Set triBipolar 0 in the conf for a rectified (always outward) drive."
puts ""
exit [expr {$nFail == 0 ? 0 : 1}]
