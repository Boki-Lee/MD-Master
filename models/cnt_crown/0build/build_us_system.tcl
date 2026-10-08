# ============================================================
#  构建「伞形采样(US)自由能」体系：CNT 侧壁冠醚孔 + 离子穿膜
#
#  目标：算离子从管外体相 → 穿过碳纳米管侧壁的 18-冠-6 孔 → 进入管腔
#       的 PMF（自由能曲线）。采用伞形采样 + WHAM。
#
#  用法：
#      SRC_MODEL=/路径/system_combined vmd -dispdev none -e build_us_system.tcl
#  或：  SRC_MODEL=/路径/system_combined ./run_build.sh
#
#  输入（必需）：未溶剂化的 CNT+冠醚模型 system_combined.psf/pdb
#       —— 可用本库 models/cnt_crown/0build/build_cnt_crown.tcl 生成
#
#  核心技巧：把目标冠醚孔旋转到「孔轴 = +Z、孔心 = 原点」。
#       这样离子径向穿过孔的坐标就退化成 z，后面 SMD/US 的 colvars 直接用
#       distanceZ（与外部石墨烯孔参考项目一致）。
#
#  输出（写进 ../1model/ 或 $OUTDIR）：
#      rotated.psf/pdb         旋转后（孔轴=Z、孔心=原点）的 CNT+冠醚
#      system_solv.psf/pdb     溶剂化
#      system_ion.psf/pdb      溶剂化 + 目标离子 + 反离子（MD-ready）
#      cnt_fixed.pdb           CNT B=1  → NAMD fixedAtoms 冻结管
#      ion_restrain.pdb        目标离子 B=1 → NAMD 侧向(XY)约束，钉在孔轴
#      cnt_langevin.pdb        水+离子 B=1 → NAMD Langevin 恒温
#      cell_params.tcl         盒子向量/中心（NAMD conf 里 source 它）
#      ion_index.dat           目标离子原子序号（colvars main 用）
#      ox_indices.dat          目标孔 6 个冠醚氧序号（colvars ref 用）
#      pore_info.dat           人类可读摘要
# ============================================================

catch {mol delete all}

proc getenv_def {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}

# ---------------- 可调参数（可用环境变量覆盖）----------------
set env_src   [getenv_def SRC_MODEL ""]
set ion_type   [getenv_def ION_TYPE POT]      ;# 目标阳离子（POT=K⁺、CAL=Ca²⁺、SOD=Na⁺）
set ion_anion  [getenv_def ION_ANION CLA]     ;# 反离子（CLA=Cl⁻）
set nion       [getenv_def NION 1]            ;# 目标离子个数（默认单离子）
set nanion     [getenv_def NANION 1]          ;# 反离子个数（默认中和单离子）
set ion_z_max  [getenv_def ION_Z_MAX 12.0]    ;# 管外体相最远窗口 z（Å，孔心=0，管外为正）
set ion_z_min  [getenv_def ION_Z_MIN -6.0]    ;# 管内最深窗口 z（Å，管内为负）
set bulk_margin [getenv_def BULK_MARGIN 10.0] ;# 离子与盒边/周期镜像的最小间距（Å）
set pad        [getenv_def PAD 8.0]           ;# 管四周水 padding（Å）

# ---------------- 输入校验 ----------------
if {$env_src eq ""} {
    puts "ERROR: 请设置 SRC_MODEL=/路径/system_combined（未溶剂化的 CNT+冠醚模型）"
    exit 1
}
if {![file exists "${env_src}.psf"] || ![file exists "${env_src}.pdb"]} {
    puts "ERROR: 找不到 ${env_src}.psf / .pdb"
    exit 1
}

# ---------------- 输出目录 ----------------
set scriptdir [file dirname [file normalize [info script]]]
set outdir [getenv_def OUTDIR [file normalize [file join $scriptdir ../1model]]]
file mkdir $outdir
puts "Source model : $env_src"
puts "Output dir   : $outdir"
puts "Ion          : $nion x $ion_type  +  $nanion x $ion_anion"

# ============================================================
# 阶段 1：读取模型，旋转目标孔到「孔轴=+Z、孔心=原点」
# ============================================================
mol load psf "${env_src}.psf" pdb "${env_src}.pdb"
set all [atomselect top all]
set natom [$all num]
puts "Loaded $natom atoms from ${env_src}"

# 冠醚氧：原子名 O、类型 OX（水氧是 OH2，不会混进来）
set oxsel [atomselect top "name O"]
set nox [$oxsel num]
if {$nox < 6} { puts "ERROR: 冠醚氧不足 6 个，检查模型（冠醚氧原子名应为 O）"; exit 1 }
puts "Crown ether O atoms: $nox (=$nox/6 pores)"

# ---- 目标孔 = 离管轴中点最近的 O（选中段环，远离管两端，避免端部效应）----
# 管轴沿 Z，管两端 = CNT 的 z 最小/最大
set mm0 [measure minmax $all]
set zmin0 [lindex [lindex $mm0 0] 2]
set zmax0 [lindex [lindex $mm0 1] 2]
set zmid [expr {($zmin0 + $zmax0) / 2.0}]
# 找 z 最接近管轴中点 zmid 的冠醚氧作种子（其 5 个最近邻 = 该中段环的一个孔）
set best_idx -1
set best_dz 1e9
foreach idx [$oxsel get index] {
    set s [atomselect top "index $idx"]
    set zz [lindex [lindex [$s get {x y z}] 0] 2]
    set dz [expr {abs($zz - $zmid)}]
    if {$dz < $best_dz} { set best_dz $dz; set best_idx $idx }
    $s delete
}
set seed [atomselect top "index $best_idx"]
set sc [lindex [$seed get {x y z}] 0]
lassign $sc sx sy sz
set dist {}
foreach idx [$oxsel get index] {
    set s [atomselect top "index $idx"]
    set cc [lindex [$s get {x y z}] 0]
    lassign $cc x y z
    lappend dist [list [expr {sqrt(($x-$sx)**2+($y-$sy)**2+($z-$sz)**2)}] $idx]
    $s delete
}
set dist [lsort -real -index 0 $dist]
set cluster {}
for {set i 0} {$i < 6} {incr i} { lappend cluster [lindex [lindex $dist $i] 1] }
set cluster [lsort -integer $cluster]
puts "Target pore = 6 O (0-based index): $cluster"

set pore [atomselect top "index $cluster"]
set c [measure center $pore]
lassign $c cx cy cz
puts "Pore center (before rotation): [format "%.3f %.3f %.3f" $cx $cy $cz]"

# 管轴沿 Z，孔的外法向 = (cx, cy, 0) 归一化；θ0 = atan2(cy, cx)
set theta0 [expr {atan2($cy, $cx)}]
set theta0deg [expr {$theta0 * 57.2957795130823}]
puts "Pore azimuth theta0 = [format "%.2f" $theta0deg] deg"

# 旋转：先把孔转到 +X（绕 Z 转 -θ0），再把 +X 转到 +Z（绕 Y 转 -90°）
$all move [transaxis z [expr {-$theta0deg}] deg]
$all move [transaxis y -90 deg]

# 再把孔心平移到原点（此时孔法向已沿 +Z）
set c2 [measure center [atomselect top "index $cluster"]]
$all moveby [vecinvert $c2]
set c3 [measure center [atomselect top "index $cluster"]]
puts "Pore center after rotation : [format "%.3f %.3f %.3f" $c3 [lindex $c3 1] [lindex $c3 2]]  (应≈0 0 0)"

# 旋转只改坐标不改拓扑 → 直接复制原始 PSF（vmd writepsf 会把原子质量写错，导致
# NAMD 把碳当成氢报 "H atom bonded only to child H atoms"），只重写旋转后的 PDB
file copy -force "${env_src}.psf" "$outdir/rotated.psf"
$all writepdb "$outdir/rotated.pdb"

# 记下旋转后 CNT 的坐标（solvate/autoionize 会清零 CNT 坐标，稍后恢复）
set rot_coords [$all get {x y z}]

# 旋转后 CNT 的 minmax → 定水盒子
set mm [measure minmax $all]
set xmin [lindex [lindex $mm 0] 0]; set xmax [lindex [lindex $mm 1] 0]
set ymin [lindex [lindex $mm 0] 1]; set ymax [lindex [lindex $mm 1] 1]
set zmin [lindex [lindex $mm 0] 2]; set zmax [lindex [lindex $mm 1] 2]
set tube_R [expr {($ymax - $ymin) / 2.0}]
puts "CNT minmax after rotation:  x [format "%.2f %.2f" $xmin $xmax]  y [format "%.2f %.2f" $ymin $ymax]  z [format "%.2f %.2f" $zmin $zmax]"
puts "Tube radius R = [format "%.3f" $tube_R] Ang"

# 水盒子：管四周 pad；+Z 一侧额外留 bulk_margin + ion_z_max 给离子当管外体相
set bx1 [expr {$xmin - $pad}]; set bx2 [expr {$xmax + $pad}]
set by1 [expr {$ymin - $pad}]; set by2 [expr {$ymax + $pad}]
set bz1 [expr {$zmin - $pad}]
set bz2 [expr {max($zmax, $ion_z_max) + $bulk_margin}]
puts "Water box (minmax): x [$bx1 $bx2]  y [$by1 $by2]  z [$bz1 $bz2]"

# ============================================================
# 阶段 2：溶剂化 + 加离子
# ============================================================
if {[catch {
    package require solvate
    solvate "$outdir/rotated.psf" "$outdir/rotated.pdb" \
        -minmax [list [list $bx1 $by1 $bz1] [list $bx2 $by2 $bz2]] \
        -o "$outdir/system_solv"

    mol delete all; mol load psf "$outdir/system_solv.psf" pdb "$outdir/system_solv.pdb"
    [atomselect top "segname CNT"] set {x y z} $rot_coords
    [atomselect top all] writepdb "$outdir/system_solv.pdb"

    package require autoionize
    autoionize -psf "$outdir/system_solv.psf" -pdb "$outdir/system_solv.pdb" \
        -nions [list "$ion_type $nion" "$ion_anion $nanion"] -o "$outdir/system_ion"

    mol delete all; mol load psf "$outdir/system_ion.psf" pdb "$outdir/system_ion.pdb"
    [atomselect top "segname CNT"] set {x y z} $rot_coords
    [atomselect top all] writepdb "$outdir/system_ion.pdb"
} err]} {
    puts "ERROR in solvation/ionization: $err"
    exit 1
}

# ============================================================
# 阶段 3：把目标离子放到管外体相起点 (0,0,+ion_z_max)
# ============================================================
mol delete all; mol load psf "$outdir/system_ion.psf" pdb "$outdir/system_ion.pdb"
set pot [atomselect top "name $ion_type"]
set npot [$pot num]
if {$npot != $nion} { puts "ERROR: 期望 $nion 个 $ion_type，实际 $npot 个"; exit 1 }
$pot set x 0.0
$pot set y 0.0
$pot set z $ion_z_max
[atomselect top all] writepdb "$outdir/system_ion.pdb"
puts "Placed $ion_type at (0, 0, $ion_z_max)"

# ---- 记录原子序号（colvars 用 1-based = VMD index + 1）----
set pot_idx [expr {[lindex [$pot get index] 0] + 1}]

# 目标孔 6 个氧 = 离原点最近的 6 个 O（旋转后目标孔在原点）
set oxall [atomselect top "name O"]
set ox_dist {}
foreach idx [$oxall get index] {
    set s [atomselect top "index $idx"]
    set cc [lindex [$s get {x y z}] 0]
    lassign $cc xx yy zz
    lappend ox_dist [list [expr {sqrt($xx*$xx + $yy*$yy + $zz*$zz)}] $idx]
    $s delete
}
set ox_dist [lsort -real -index 0 $ox_dist]
set target_ox {}
for {set i 0} {$i < 6} {incr i} {
    lappend target_ox [expr {[lindex [lindex $ox_dist $i] 1] + 1}]
}
set target_ox [lsort -integer $target_ox]

set fp [open "$outdir/ion_index.dat" w]; puts $fp $pot_idx; close $fp
set fp [open "$outdir/ox_indices.dat" w]
foreach o $target_ox { puts -nonewline $fp "$o " }
puts $fp ""; close $fp

# ============================================================
# 阶段 4：写 NAMD 用的 B 字段 PDB + 盒子参数
# ============================================================
set iall [atomselect top all]

# cnt_fixed.pdb：CNT（碳+氧）B=1 → fixedAtoms 冻结管（孔环刚性，反应坐标最干净）
$iall set beta 0.0
[atomselect top "segname CNT"] set beta 1.0
$iall writepdb "$outdir/cnt_fixed.pdb"

# ion_restrain.pdb：目标离子 B=1 → selectConstrX/Y on 钉在孔轴 (x=0,y=0)
$iall set beta 0.0
[atomselect top "name $ion_type"] set beta 1.0
$iall writepdb "$outdir/ion_restrain.pdb"

# cnt_langevin.pdb：水+离子 B=1 → Langevin 恒温；CNT B=0（已被 fixedAtoms 冻结）
$iall set beta 0.0
[atomselect top "not segname CNT"] set beta 1.0
$iall writepdb "$outdir/cnt_langevin.pdb"

# ---- cell_params.tcl：盒子向量 + 中心（NAMD conf 里 source）----
# NAMD 的 cellOrigin 是「盒子中心」！按 minmax 中心算。
set c1x [expr {$bx2 - $bx1}]; set c2y [expr {$by2 - $by1}]; set c3z [expr {$bz2 - $bz1}]
set ox0 [expr {($bx1 + $bx2) / 2.0}]; set oy0 [expr {($by1 + $by2) / 2.0}]; set oz0 [expr {($bz1 + $bz2) / 2.0}]
set fp [open "$outdir/cell_params.tcl" w]
puts $fp "# 由 build_us_system.tcl 自动生成，勿手改"
puts $fp "set cell_basis_1 \"[format "%.3f" $c1x] 0.0 0.0\""
puts $fp "set cell_basis_2 \"0.0 [format "%.3f" $c2y] 0.0\""
puts $fp "set cell_basis_3 \"0.0 0.0 [format "%.3f" $c3z]\""
puts $fp "set cell_origin  \"[format "%.3f" $ox0] [format "%.3f" $oy0] [format "%.3f" $oz0]\""
close $fp

# ---- pore_info.dat：人类可读摘要 ----
set fp [open "$outdir/pore_info.dat" w]
puts $fp "target ion ($ion_type) atom index : $pot_idx"
puts $fp "target pore O indices : $target_ox"
puts $fp "tube radius R (Ang)   : [format "%.3f" $tube_R]"
puts $fp "CNT x range           : [format "%.2f %.2f" $xmin $xmax]"
puts $fp "CNT y range           : [format "%.2f %.2f" $ymin $ymax]"
puts $fp "CNT z range           : [format "%.2f %.2f" $zmin $zmax]"
puts $fp "ion z range           : [format "%.2f .. %.2f" $ion_z_max $ion_z_min]"
puts $fp "cell basis 1          : [format "%.3f" $c1x] 0 0"
puts $fp "cell basis 2          : 0 [format "%.3f" $c2y] 0"
puts $fp "cell basis 3          : 0 0 [format "%.3f" $c3z]"
puts $fp "cell origin(center)   : [format "%.3f %.3f %.3f" $ox0 $oy0 $oz0]"
close $fp

# ---- 汇总 ----
set nall [$iall num]
set nwat [[atomselect top "water"] num]
set ncat [[atomselect top "name $ion_type"] num]
set nan  [[atomselect top "name $ion_anion"] num]
puts ""
puts "============================================"
puts "Done. Final system: total=$nall  water=$nwat  $ion_type=$ncat  $ion_anion=$nan"
puts "  target ion index : $pot_idx"
puts "  target O indices : $target_ox"
puts "  cell (X Y Z)     : [format "%.2f %.2f %.2f" $c1x $c2y $c3z]"
puts "  cellOrigin       : [format "%.2f %.2f %.2f" $ox0 $oy0 $oz0]"
puts "============================================"
quit
