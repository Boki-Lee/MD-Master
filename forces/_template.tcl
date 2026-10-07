# ============================================================
#  _template.tcl  ——  新自定义力（tclForces）写法骨架
#
#  照着这份骨架抄，改下面三块即可：
#    1) 参数区（参数 + 默认值，conf 里可预先 set 同名变量覆盖）
#    2) 一次性初始化（读离子列表/盒子/坐标登记）
#    3) calcforces（每步回调，真正加力）
#
#  【NAMD 里怎么用】在 4prod/prod.conf 里写：
#        tclForces        on
#        tclForcesScript  ../forces/field_xxx.tcl        # 或本骨架改名
#    若要覆盖参数（不直接改脚本），用块形式：
#        tclForcesScript {
#            set ionFile "../1model/ion_ids.dat"
#            set myParam  123.0
#            source ../forces/field_xxx.tcl
#        }
#
#  【关键规矩】（踩坑总结，务必遵守）
#    1. 想拿坐标，必须先在脚本顶层 `addatom $id` 登记，
#       再在 calcforces 里 `loadcoords p` 取；取到的是"上一步"坐标。
#    2. 热路径（calcforces 每步都跑）里不要调用 proc，表达式全部内联，
#       否则每个离子每步多几十微秒开销。
#    3. 跨周期性边界要用最小镜像折回，否则离子被 NAMD 折回原胞时坐标跳一个盒子长。
#    4. 1/r、1/r^2 之类场在 r->0 会发散，必须做截断（rt 加 1e-30 或 max(r,r_in)）。
#    5. 力要有界、别 NaN；给所有从文件读的数值兜底。
#    6. 离线自检：`tclsh selftest_field.tcl`（source 本脚本核对的公式和 NAMD 里跑的一致）。
# ============================================================


# ============================================================
#  1. 参数区：conf 里预先 set 同名变量即可覆盖（info exists 保护默认值）
# ============================================================

# 单位换算：1 V/Å = 23.06054917 kcal/(mol·Å·e)
if {![info exists eFieldFactor]} { set eFieldFactor 23.06054917 }

# —— 你的场参数（举例，改成你要的）——
if {![info exists vAxial]}      { set vAxial      5.0 }   ;# 轴向电压 V
if {![info exists periodRad]}   { set periodRad   4.0 }   ;# 周期 ns
if {![info exists vmaxRad]}     { set vmaxRad     10.0 }  ;# 峰值电压 V

# 积分步长（fs）：必须与 conf 里 timestep 一致
if {![info exists dtFs]}        { set dtFs        2.0 }

# 诊断输出：每隔多少步打印一行；<=0 只打印第 0 步
if {![info exists printEvery]}  { set printEvery  25000 }

# 数据文件（相对 4prod/ 运行目录）
if {![info exists ionFile]}     { set ionFile     "../1model/ion_ids.dat" }
if {![info exists xscFile]}     { set xscFile     "../3eq/eq.restart.xsc" }

# 读不到 xsc 时的兜底盒子尺寸
if {![info exists fallbackLz]}  { set fallbackLz  87.539 }
if {![info exists fallbackLxy]} { set fallbackLxy 51.15 }


# ============================================================
#  2. 纯数学函数（不依赖 NAMD，离线自检也调用这几个）
# ============================================================

# 从 NAMD 的 .xsc 文件读盒子，返回 {Lx Ly Lz ox oy skew}，失败返回 {}
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
        set skew [expr {abs($ay)+abs($az)+abs($bx)+abs($bz)+abs($cx)+abs($cy)}]
        return [list $Lx $Ly $Lz $ox $oy $skew]
    }
    return {}
}

# 最小镜像：把沿盒子边位移 d 折进 [-L/2, L/2)
proc minImage {d L} {
    if {$L <= 0.0} { return $d }
    return [expr {$d - $L * floor($d / $L + 0.5)}]
}


# ============================================================
#  3. 模式判断：NAMD 里才有 addatom；没有就进"自检模式"
# ============================================================
if {[info commands addatom] eq ""} {

    puts "\[_template.tcl\] no NAMD 'addatom' command -> selftest mode"
    puts "\[_template.tcl\] params and math procs defined; no atom registered, no force applied."

} else {

    # ---------------- 3.1 读盒子 ----------------
    set _box [readXscBox $xscFile]
    if {[llength $_box] >= 6} {
        set Lx [lindex $_box 0]; set Ly [lindex $_box 1]; set Lz [lindex $_box 2]
        set _ox [lindex $_box 3]; set _oy [lindex $_box 4]
        set _skew [lindex $_box 5]
        print "field: box from $xscFile -> Lx=[format %.3f $Lx] Ly=[format %.3f $Ly] Lz=[format %.3f $Lz]"
    } else {
        set Lx $fallbackLxy; set Ly $fallbackLxy; set Lz $fallbackLz
        set _ox 0.0; set _oy 0.0
        print "field: ERROR cannot read $xscFile; using fallback box"
    }

    # ---------------- 3.2 读离子列表并登记坐标请求 ----------------
    if {![file exists $ionFile]} {
        error "field: ion list not found: $ionFile (run from 4prod/ ?)"
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

    # ---------------- 3.3 预计算常量（把每步都能算的提到这里）----------------
    set EzConst [expr {$eFieldFactor * $vAxial / $Lz}]   ;# 轴向场常数

    # 扁平离子表：每 3 个元素 = 一个离子 {id q 常量}
    set ionPairs {}
    foreach id $ionIDs q $ionCharges {
        lappend ionPairs $id $q [expr {$q * $EzConst}]
    }

    print "field: ============================================================"
    print "field: loaded $nIon ions, Lz=[format %.3f $Lz]"
    print "field: ============================================================"

    # ---------------- 3.4 每步回调（热路径：内联表达式，不调 proc）----------------
    proc calcforces {} {
        global vAxial periodRad vmaxRad dtFs printEvery
        global Lx Ly Lz ionPairs EzConst

        set step [getstep]
        set t_ns [expr {$step * $dtFs * 1.0e-6}]

        # —— 在这里算你想要的力；下面是"纯轴向匀强场"的最小例子 ——
        loadcoords p

        foreach {id q fzConst} $ionPairs {
            if {![info exists p($id)]} continue
            # 纯轴向：Fz = q * Ez；x/y 方向无外力
            addforce $id [list 0.0 0.0 $fzConst]
        }

        # —— 诊断输出（不在热路径预算内）——
        if {$step == 0 || ($printEvery > 0 && $step % $printEvery == 0)} {
            print "field: step=$step t=[format %.4f $t_ns] ns"
        }
    }
}
