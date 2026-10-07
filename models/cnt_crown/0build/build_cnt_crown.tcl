# ============================================================
#  构建 CNT + 18-冠-6 孔道（在石墨烯晶格上雕刻出冠醚孔）
#
#  Ubuntu / Linux 版，移植自：
#      crown/1build/Part/build_cnt_crown.tcl  (Windows/VMD 版本)
#
#  用法：
#      vmd -dispdev none -e build_cnt_crown.tcl
#  或者直接用启动器：
#      ./run_build.sh
#
#  输出目录：
#      若设置了环境变量 $CNT_OUTDIR 就用它，否则用当前工作目录。
#      run_build.sh 会先 cd 到本脚本所在目录，
#      因此默认情况下所有输出都写在脚本旁边。
#
#  可选环境变量（都有默认值，一般无需修改）：
#      CNT_N=23            手性指数 n（armchair 时 n == m）
#      CNT_M=23            手性指数 m
#      CNT_LENGTH_NM=8.0   管长，单位 nm
#      CNT_CC_BOND=0.1418  C-C 键长，单位 nm
#      PORE_RINGS=4        沿管轴方向的孔圈数
#      PORE_PER_RING=3     每圈孔数
#      PORE_Z_START=0.1    第一圈孔的 z 比例（0~1）
#      PORE_Z_SPAN=0.8     孔分布覆盖的 z 范围比例
#      DO_SOLVATE=0        1 = 同时做溶剂化并加离子（TIP3P + KCl）
#      SOLV_PAD=10.0       水盒子 padding，单位 Å
#      ION_CONC=0.6        盐浓度，单位 mol/L
#      ION_CATION=POT      阳离子（POT=K+，SOD=Na+）
#      ION_ANION=CLA       阴离子（CLA=Cl-）
#      ION_FROM=5.0        离子与溶质的最小距离，单位 Å
#      ION_BETWEEN=5.0     离子之间的最小距离，单位 Å
#      DO_RENDER=0         1 = 渲染一张 TachyonInternal 图片
# ============================================================

catch {mol delete all}

# ---------------- 输出目录 ----------------
if {[info exists env(CNT_OUTDIR)] && $env(CNT_OUTDIR) ne ""} {
    set outdir [file normalize $env(CNT_OUTDIR)]
} else {
    set outdir [pwd]
}
file mkdir $outdir
puts "Output directory: $outdir"

set pi 3.141592653589793

# ---------------- 参数读取辅助函数 ----------------
proc getenv_def {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}

set cnt_n         [getenv_def CNT_N 23]
set cnt_m         [getenv_def CNT_M 23]
set length_nm     [getenv_def CNT_LENGTH_NM 8.0]
set cc_bond       [getenv_def CNT_CC_BOND 0.1418]
set pore_rings    [getenv_def PORE_RINGS 4]
set pore_per_ring [getenv_def PORE_PER_RING 3]
set pore_z_start  [getenv_def PORE_Z_START 0.1]
set pore_z_span   [getenv_def PORE_Z_SPAN 0.8]
set do_solvate    [getenv_def DO_SOLVATE 0]
set solv_pad      [getenv_def SOLV_PAD 10.0]
set ion_conc      [getenv_def ION_CONC 0.6]
set ion_cation    [getenv_def ION_CATION POT]
set ion_anion     [getenv_def ION_ANION CLA]
set ion_from      [getenv_def ION_FROM 5.0]
set ion_between   [getenv_def ION_BETWEEN 5.0]
set do_render     [getenv_def DO_RENDER 0]

puts "Parameters: n=$cnt_n m=$cnt_m L=$length_nm nm cc=$cc_bond nm rings=$pore_rings pores/ring=$pore_per_ring"

# --------------------------------------------------
# 过程：写一条标准 PDB ATOM 记录（segname 放在第 73-76 列）
# --------------------------------------------------
proc write_pdb_atom {fp serial aname resname chain resid x y z segname} {
    puts $fp [format "ATOM  %5d %-4s%1s%3s %1s%4d    %8.3f%8.3f%8.3f  1.00  0.00      %-4s" \
        $serial $aname "" $resname $chain $resid $x $y $z $segname]
}

# --------------------------------------------------
# 过程：定位一个六元环（最近碳 + 2 个最近邻 + BFS 闭合成环）
# --------------------------------------------------
proc trace_hexagon {center adj_arr coords_arr hole_pos} {
    upvar $adj_arr adj; upvar $coords_arr coords
    lassign $hole_pos hx hy hz ht; set nbrs $adj($center)
    if {[llength $nbrs] < 2} { return {} }
    set ndist {}
    foreach nb $nbrs {
        lassign [lindex $coords [expr {$nb-1}]] nx ny nz
        lappend ndist [list [expr {sqrt(($nx-$hx)**2+($ny-$hy)**2+($nz-$hz)**2)}] $nb]
    }
    set ndist [lsort -real -index 0 $ndist]
    set n1 [lindex [lindex $ndist 0] 1]; set n2 [lindex [lindex $ndist 1] 1]
    set visited [list $center]; set queue [list [list $n1 [list $n1]]]
    while {[llength $queue] > 0} {
        set front [lindex $queue 0]; set queue [lrange $queue 1 end]
        set node [lindex $front 0]; set cur [lindex $front 1]
        if {[llength $cur] == 5} { if {$node == $n2} { return [concat [list $center] $cur] }; continue }
        foreach nb $adj($node) { if {$nb in $visited} continue; lappend visited $nb; lappend queue [list $nb [concat $cur [list $nb]]] }
    }
    return {}
}

# --------------------------------------------------
# 过程：找 spoke 碳（六元环上每个原子朝外的那个邻居）
# --------------------------------------------------
proc trace_spokes {hex adj_arr} {
    upvar $adj_arr adj; set spokes {}; set hex_set {}
    foreach a $hex { lappend hex_set $a }
    foreach a $hex { foreach nb $adj($a) { if {$nb ni $hex_set && $nb ni $spokes} { lappend spokes $nb } } }
    return $spokes
}

# --------------------------------------------------
# 过程：找 bridge 碳（相邻两个 spoke 之间的 2 个碳）
# --------------------------------------------------
proc trace_bridges {spokes hex adj_arr} {
    upvar $adj_arr adj; set hex_set {}; foreach a $hex { lappend hex_set $a }
    set bridges {}; set nsp [llength $spokes]
    for {set i 0} {$i < $nsp} {incr i} {
        set s1 [lindex $spokes $i]; set s2 [lindex $spokes [expr {($i+1)%$nsp}]]
        set visited $hex_set; set queue [list [list $s1 [list $s1]]]
        while {[llength $queue] > 0} {
            set front [lindex $queue 0]; set queue [lrange $queue 1 end]
            set node [lindex $front 0]; set cur [lindex $front 1]
            if {$node == $s2 && [llength $cur] == 4} { lappend bridges [lindex $cur 1]; lappend bridges [lindex $cur 2]; break }
            if {[llength $cur] >= 4} continue
            foreach nb $adj($node) { if {$nb in $visited} continue; lappend visited $nb; lappend queue [list $nb [concat $cur [list $nb]]] }
        }
    }
    return $bridges
}

# ============================================================
# 阶段 1：生成 CNT 并雕刻出冠醚孔
# ============================================================

# ---- 第 1 步：生成 CNT ----
# 以可移植的方式加载自带的 nanotube 插件：
# 先试 package require，失败则回退到 $VMDDIR/plugins/noarch/tcl/nanotube1.6
if {[catch {package require nanotube} nt_err]} {
    if {![info exists env(VMDDIR)] || $env(VMDDIR) eq ""} {
        puts "ERROR: 'package require nanotube' failed ($nt_err) and VMDDIR is not set."
        exit 1
    }
    set nt_dir [file join $env(VMDDIR) plugins noarch tcl nanotube1.6]
    foreach f {graphene.tcl nanotube.tcl} {
        if {![file exists [file join $nt_dir $f]]} {
            puts "ERROR: nanotube plugin file not found: [file join $nt_dir $f]"
            exit 1
        }
    }
    source [file join $nt_dir graphene.tcl]
    source [file join $nt_dir nanotube.tcl]
    puts "Loaded nanotube plugin from $nt_dir"
}

::Nanotube::nanotube_core -l $length_nm -n $cnt_n -m $cnt_m -cc $cc_bond -ma C-C -b 1 -a 1 -d 1 -i 0
set all [atomselect top "all"]; $all set type CA; $all set segname CNT; $all set name C
set cnt_coords [$all get {x y z}]
set minmax [measure minmax $all]
set z_min [lindex [lindex $minmax 0] 2]; set z_max [lindex [lindex $minmax 1] 2]
set cnt_r [expr {0.5 * ([lindex [lindex $minmax 1] 0] - [lindex [lindex $minmax 0] 0])}]
set cnt_len [expr {$z_max - $z_min}]; set cnt_atoms [$all num]
puts "CNT: r=$cnt_r, L=$cnt_len, atoms=$cnt_atoms"
$all writepsf "$outdir/cnt_core.psf"; $all writepdb "$outdir/cnt_core.pdb"; mol delete top

# ---- 第 2 步：解析 CNT 的键接关系 -> 邻接表 ----
set fp [open "$outdir/cnt_core.psf" r]; set psf_data [split [read $fp] "\n"]; close $fp
array set adj {}; set ib 0
foreach line $psf_data {
    if {[regexp {^\s*(\d+)\s+!NBOND} $line]} { set ib 1; continue }
    if {[regexp {^\s*(\d+)\s+!NTHETA} $line]} { set ib 0; continue }
    if {$ib} { set cols [regexp -inline -all {\S+} $line]; for {set j 0} {$j+1 < [llength $cols]} {incr j 2} { set a [lindex $cols $j]; set b [lindex $cols [expr {$j+1}]]; lappend adj($a) $b; lappend adj($b) $a } }
}
puts "Adjacency: [array size adj] atoms"

# ---- 第 3 步：计算孔心位置 + 图遍历（六元环 / spoke / bridge） ----
set hole_centers {}
for {set ring 0} {$ring < $pore_rings} {incr ring} {
    if {$pore_rings > 1} {
        set frac [expr {$pore_z_start + $ring*$pore_z_span/($pore_rings - 1.0)}]
    } else {
        set frac $pore_z_start
    }
    set zh [expr {$z_min + $cnt_len*$frac}]; set ao [expr {$ring*$pi/3.0}]
    for {set i 0} {$i < $pore_per_ring} {incr i} {
        set ang [expr {$ao + $i*2.0*$pi/$pore_per_ring}]
        lappend hole_centers [list [expr {$cnt_r*cos($ang)}] [expr {$cnt_r*sin($ang)}] $zh $ang]
    }
}
puts "Hole centers: [llength $hole_centers]"

set all_delete {}; set all_spokes {}; set all_bridges {}; set hi 0
foreach c $hole_centers {
    lassign $c hx hy hz ht; incr hi; set md 999; set ba 0
    for {set i 1} {$i <= $cnt_atoms} {incr i} { lassign [lindex $cnt_coords [expr {$i-1}]] ax ay az; set d [expr {sqrt(($ax-$hx)**2+($ay-$hy)**2+($az-$hz)**2)}]; if {$d < $md} { set md $d; set ba $i } }
    set hex [trace_hexagon $ba adj cnt_coords [list $hx $hy $hz $ht]]
    if {[llength $hex] != 6} { puts "  Hole $hi: FAIL"; continue }
    set spokes [trace_spokes $hex adj]; set bridges [trace_bridges $spokes $hex adj]
    puts "  Hole $hi: hex=6, spokes=[llength $spokes], bridges=[llength $bridges]"
    foreach a $hex { lappend all_delete $a }; foreach a $spokes { lappend all_spokes $a }; foreach a $bridges { lappend all_bridges $a }
}
set all_delete [lsort -unique -integer $all_delete]; set all_spokes [lsort -unique -integer $all_spokes]; set all_bridges [lsort -unique -integer $all_bridges]
puts "Summary: delete [llength $all_delete], spoke->O [llength $all_spokes], bridge->C [llength $all_bridges]"

# ---- 第 4 步：用 psfgen 删除六元环 + 清理只剩 1 根键的悬挂碳 ----
if {[llength $all_delete] > 0} {
    mol load psf "$outdir/cnt_core.psf" pdb "$outdir/cnt_core.pdb"
    set ds [atomselect top "serial [join $all_delete { }]"]; set dl [$ds get {segname resid name}]; mol delete top
    package require psfgen; resetpsf; readpsf "$outdir/cnt_core.psf"; coordpdb "$outdir/cnt_core.pdb"
    foreach a $dl { delatom [lindex $a 0] [lindex $a 1] [lindex $a 2] }
    writepsf "$outdir/cnt_pored.psf"; writepdb "$outdir/cnt_pored.pdb"
} else {
    puts "WARNING: no hexagons detected - cnt_core is used unchanged as cnt_pored"
    file copy -force "$outdir/cnt_core.psf" "$outdir/cnt_pored.psf"
    file copy -force "$outdir/cnt_core.pdb" "$outdir/cnt_pored.pdb"
}

for {set ci 1} {$ci <= 10} {incr ci} {
    mol delete all; mol load psf "$outdir/cnt_pored.psf" pdb "$outdir/cnt_pored.pdb"
    set fp [open "$outdir/cnt_pored.psf" r]; set lines [split [read $fp] "\n"]; close $fp
    set bp {}; set ib 0; set cl 0; set nbonds 0
    foreach line $lines {
        if {[regexp {^\s*(\d+)\s+!NBOND} $line -> nb]} { set nbonds $nb; set ib 1; continue }
        if {[regexp {^\s*(\d+)\s+!NTHETA} $line]} { set ib 0; continue }
        if {$ib} { set cols [regexp -inline -all {\S+} $line]; for {set j 0} {$j+1 < [llength $cols]} {incr j 2} { lappend bp [list [lindex $cols $j] [lindex $cols [expr {$j+1}]]]; incr cl; if {$cl >= $nbonds} { set ib 0; break } } }
    }
    set natom [[atomselect top "segname CNT"] num]; array set bcnt {}; for {set i 1} {$i <= $natom} {incr i} { set bcnt($i) 0 }
    foreach b $bp { lassign $b a bb; incr bcnt($a); incr bcnt($bb) }
    set bad {}; for {set i 1} {$i <= $natom} {incr i} { if {$bcnt($i) == 1} { lappend bad $i } }
    if {![llength $bad]} { break }
    puts "  cleanup pass $ci: removing [llength $bad] dangling atom(s)"
    set bad_sel [atomselect top "serial [join $bad { }]"]; set bad_info [$bad_sel get {segname resid name}]
    package require psfgen; resetpsf; readpsf "$outdir/cnt_pored.psf"; coordpdb "$outdir/cnt_pored.pdb"
    foreach a $bad_info { delatom [lindex $a 0] [lindex $a 1] [lindex $a 2] }
    writepsf "$outdir/cnt_pored.psf"; writepdb "$outdir/cnt_pored.pdb"
}

# ---- 第 5 步：载入挖孔后的 CNT，把 spoke 标记为 O ----
mol delete all; mol load psf "$outdir/cnt_pored.psf" pdb "$outdir/cnt_pored.pdb"
set pored_all [atomselect top "all"]; set pored_cnt_atoms [$pored_all num]; set pored_coords [$pored_all get {x y z}]

array set o2n {}; set ni 1
for {set oi 1} {$oi <= $cnt_atoms} {incr oi} { if {$oi ni $all_delete} { set o2n($oi) $ni; incr ni } else { set o2n($oi) 0 } }
set ring_is_O {}
foreach oi $all_spokes { if {$o2n($oi) > 0} { lappend ring_is_O $o2n($oi) } }
set ring_is_O [lsort -unique -integer $ring_is_O]

set fp [open "$outdir/cnt_pored.psf" r]; set lines [split [read $fp] "\n"]; close $fp
set pored_bonds {}; set ib 0; set cl 0; set nbonds 0
foreach line $lines {
    if {[regexp {^\s*(\d+)\s+!NBOND} $line -> nb]} { set nbonds $nb; set ib 1; continue }
    if {[regexp {^\s*(\d+)\s+!NTHETA} $line]} { set ib 0; continue }
    if {$ib} { set cols [regexp -inline -all {\S+} $line]; for {set j 0} {$j+1 < [llength $cols]} {incr j 2} { lappend pored_bonds [list [lindex $cols $j] [lindex $cols [expr {$j+1}]]]; incr cl; if {$cl >= $nbonds} { set ib 0; break } } }
}
mol delete top

# ---- 第 6 步：写出合并后的 PDB + 标准 PSF（system_combined） ----
# 注意：冠醚氧的原子类型用 OX，
# 这样才能匹配 crown/forcefield/C_O.par 里的 CA-OX 键/角参数
set combined_pdb "$outdir/system_combined.pdb"; set fp [open $combined_pdb w]
set serial 1; set psf_atoms {}; set psf_bonds {}
for {set i 0} {$i < $pored_cnt_atoms} {incr i} {
    set gidx [expr {$i+1}]; lassign [lindex $pored_coords $i] x y z
    if {$gidx in $ring_is_O} { write_pdb_atom $fp $serial "O" "CNT" "A" 1 $x $y $z "CNT"; lappend psf_atoms [list "CNT" 1 "CNT" "O" "OX" 0.0 15.9994]
    } else { write_pdb_atom $fp $serial "C" "CNT" "A" 1 $x $y $z "CNT"; lappend psf_atoms [list "CNT" 1 "CNT" "C" "CA" 0.0 12.0107] }
    incr serial
}
foreach b $pored_bonds { lappend psf_bonds $b }
puts $fp "END"; close $fp
set total_atoms [expr {$serial-1}]
puts "Combined PDB: $combined_pdb ($total_atoms atoms)"

set combined_psf "$outdir/system_combined.psf"; set fpo [open $combined_psf w]
puts $fpo "PSF\n\n       1 !NTITLE\n REMARKS CNT with 18-crown-6 pores\n"
puts $fpo [format "%8d !NATOM" $total_atoms]
set aidx 1
foreach at $psf_atoms { lassign $at segname resid resname name type charge mass; puts $fpo [format "%8d %-4s %-4s %-4s %-4s %-4s %10.6f %13.8f %8d" $aidx $segname $resid $resname $name $type $charge $mass 0]; incr aidx }
puts $fpo "\n[format "%8d !NBOND: bonds" [llength $psf_bonds]]"
set bcount 0; set bline ""
foreach b $psf_bonds { lassign $b a bb; append bline [format "%8d%8d" $a $bb]; incr bcount; if {$bcount % 4 == 0} { puts $fpo $bline; set bline "" } }
if {$bline ne ""} { puts $fpo $bline }
puts $fpo "\n       0 !NTHETA: angles\n\n       0 !NPHI: dihedrals\n\n       0 !NIMPHI: impropers\n\n       0 !NDON: donors\n\n       0 !NACC: acceptors\n\n       0 !NNB\n"
set nexcl [expr {int(ceil(($total_atoms+7)/8.0))+1}]
for {set i 0} {$i < $nexcl} {incr i} { puts $fpo "       0       0       0       0       0       0       0       0" }
puts $fpo "\n       1       0 !NGRP\n       1       1 [format "%8d" $total_atoms]\n"; close $fpo
puts "Model built: $combined_psf / $combined_pdb"

# ============================================================
# 阶段 2（可选）：溶剂化 + 加离子  ->  system_solv / system_ion
# ============================================================
if {$do_solvate} {
    puts ""
    puts "===== PHASE 2: solvation + ionization ====="
    # 把整个阶段 2 包在 catch 里：一旦出错立刻报错退出，
    # 避免 VMD 出错后仍继续往下跑、最后还打印 "Done" 误导人
    if {[catch {

    mol delete all; mol load psf "$outdir/system_combined.psf" pdb "$outdir/system_combined.pdb"
    set ca [atomselect top all]; puts "System atoms: [$ca num]"
    set orig_coords [$ca get {x y z}]

    set mm [measure minmax $ca]
    set xmin [lindex [lindex $mm 0] 0]; set xmax [lindex [lindex $mm 1] 0]
    set ymin [lindex [lindex $mm 0] 1]; set ymax [lindex [lindex $mm 1] 1]
    set zmin [lindex [lindex $mm 0] 2]; set zmax [lindex [lindex $mm 1] 2]
    set wx1 [expr {$xmin - $solv_pad}]; set wx2 [expr {$xmax + $solv_pad}]
    set wy1 [expr {$ymin - $solv_pad}]; set wy2 [expr {$ymax + $solv_pad}]
    set wz1 [expr {$zmin - $solv_pad}]; set wz2 [expr {$zmax + $solv_pad}]
    puts "Water box: x [list $wx1 $wx2] y [list $wy1 $wy2] z [list $wz1 $wz2]"

    package require solvate
    solvate "$outdir/system_combined.psf" "$outdir/system_combined.pdb" -o "$outdir/system_solv" \
        -minmax [list [list $wx1 $wy1 $wz1] [list $wx2 $wy2 $wz2]]
    # solvate/psfgen 会把 CNT 坐标清零 -> 用先前存下的原坐标拷回去
    mol delete all; mol load psf "$outdir/system_solv.psf" pdb "$outdir/system_solv.pdb"
    set sc [atomselect top "segname CNT"]; $sc set {x y z} $orig_coords
    [atomselect top "all"] writepdb "$outdir/system_solv.pdb"
    puts "Solvated + coords fixed"

    package require autoionize
    autoionize -psf "$outdir/system_solv.psf" -pdb "$outdir/system_solv.pdb" \
        -o "$outdir/system_ion" -sc $ion_conc \
        -cation $ion_cation -anion $ion_anion \
        -from $ion_from -between $ion_between
    # autoionize 同样会清零 CNT 坐标 -> 再修一次
    mol delete all; mol load psf "$outdir/system_ion.psf" pdb "$outdir/system_ion.pdb"
    set ic [atomselect top "segname CNT"]; $ic set {x y z} $orig_coords
    set iall [atomselect top "all"]; $iall writepdb "$outdir/system_ion.pdb"
    puts "Ions added + coords fixed"

    # ---- NAMD 用的 B 字段 PDB（langevinCol B / conskcol B） ----
    # 两个文件的原子必须与 system_ion.psf 完全一致、顺序相同，
    # 否则 NAMD 会以“原子数不对”为由拒绝读取。
    #   cnt_restrain.pdb : CNT 碳 B=1（被约束），
    #                      冠醚氧 B=0（保持自由），水/离子 B=0
    #   cnt_langevin.pdb : 水 + 离子 B=1（施加恒温），CNT B=0
    $iall set beta 0.0
    set c_carbon [atomselect top "segname CNT and not type OX"]
    $c_carbon set beta 1.0
    $iall writepdb "$outdir/cnt_restrain.pdb"
    $iall set beta 0.0
    set mobile [atomselect top "not segname CNT"]
    $mobile set beta 1.0
    $iall writepdb "$outdir/cnt_langevin.pdb"
    puts "B-factor PDBs: cnt_restrain.pdb (CNT C=1, crown O=0), cnt_langevin.pdb (water/ions=1)"

    set nall [$iall num]
    set nwat [[atomselect top "water"] num]
    set no   [[atomselect top "type OX"] num]
    set ncat [[atomselect top "name $ion_cation"] num]
    set nan  [[atomselect top "name $ion_anion"] num]
    puts "Final system: total=$nall  water=$nwat  crown-O=$no  $ion_cation=$ncat  $ion_anion=$nan"
    set cell [molinfo top get {a b c}]
    puts "Cell (a b c) = [format "%.2f %.2f %.2f" [lindex $cell 0] [lindex $cell 1] [lindex $cell 2]]"
    } err]} { puts "ERROR in PHASE 2: $err"; exit 1 }
}

# ============================================================
# 阶段 3（可选）：渲染一张快照
# ============================================================
if {$do_render} {
    puts ""
    puts "===== PHASE 3: rendering ====="
    if {$do_solvate} {
        mol delete all; mol load psf "$outdir/system_ion.psf" pdb "$outdir/system_ion.pdb"
    } else {
        mol delete all; mol load psf "$outdir/system_combined.psf" pdb "$outdir/system_combined.pdb"
    }
    mol delrep 0 top
    mol selection {type CA}; mol material Diffuse; mol representation VDW 1.0 12.0; mol color Name; mol addrep top
    mol selection {type OX}; mol material Diffuse; mol representation VDW 1.0 22.0; mol color ColorID 1; mol addrep top
    if {$do_solvate} {
        mol selection {water}; mol material Transparent; mol representation Lines; mol color ColorID 15; mol addrep top
        mol selection {segname ION}; mol material Diffuse; mol representation VDW 1.0 12.0; mol color Name; mol addrep top
    }
    rotate x by 20; rotate y by 40; color Display Background white
    render TachyonInternal "$outdir/system_final.bmp"
    puts "Rendered: $outdir/system_final.bmp"
}

puts ""
puts "============================================"
puts "Done. Output files in: $outdir"
puts "  cnt_core.psf/pdb         -- raw generated CNT"
puts "  cnt_pored.psf/pdb        -- after carving the pores"
puts "  system_combined.psf/pdb  -- CNT + crown-6 (final model)"
if {$do_solvate} {
    puts "  system_solv.psf/pdb      -- solvated"
    puts "  system_ion.psf/pdb       -- solvated + ions (MD-ready)"
    puts "  cnt_restrain.pdb         -- B=1 on CNT carbons  (NAMD conskfile/conskcol B)"
    puts "  cnt_langevin.pdb         -- B=1 on water/ions  (NAMD langevinFile/langevinCol B)"
}
puts "============================================"
quit
