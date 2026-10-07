# ============================================================
#  triangle_field.tcl -- 用 tclForces 实现三角波循环电压
#
#  NAMD 每个时间步都会调用一次 calcforces：
#    1) 首次调用时读入离子列表和盒子 z 长度
#    2) 按当前时间算出电压 V(t)（三角波：0 → +Vmax → −Vmax → 0）
#    3) 换算成 z 方向电场力 Fz = q × eFieldFactor × V / Lz，逐个离子 addforce
#
#  依赖（相对于运行目录 prod/）：
#      ../1model/ion_ids.dat         每行：离子ID 电荷 名称（ID 从 0 开始）
#      ../3eq/eq.restart.xsc   从中读取 z 方向盒子长度
# ============================================================

# 电场换算因子：1 V/Å 相当于 23.06054917 kcal/(mol·Å·e)
set eFieldFactor 23.06054917
# 三角波周期，单位 ns
set period_ns  8.0
# 三角波峰值电压，单位 V
set vmax       10.0
# 首次调用标记（1=首次，0=非首次）
set firstCall  1
# 离子 ID 列表（ion_ids.dat 第 1 列）
set ionIDs     {}
# 离子电荷列表（ion_ids.dat 第 2 列）
set ionCharges {}
# z 方向盒子长度（从 xsc 文件读取）
set lengthZ    0.0
# 离子 ID/电荷数据文件的路径
set ionFile    "../1model/ion_ids.dat"

# 定义 tclForces 力计算函数（NAMD 每步调用一次）
proc calcforces {} {
    # 声明本函数用到的全局变量
    global eFieldFactor period_ns vmax firstCall ionIDs ionCharges lengthZ ionFile

    # ---------- 首次调用：做一次性初始化 ----------
    if {$firstCall} {
        set firstCall 0

        # 从平衡态的 xsc 文件读取 z 方向盒子长度
        set xsc_name "../3eq/eq.restart.xsc"
        # 主文件不存在就试备用的 .old 文件
        if {![file exists $xsc_name]} { set xsc_name "../3eq/eq.restart.xsc.old" }
        if {[file exists $xsc_name]} {
            set fp [open $xsc_name r]
            set lines [split [read $fp] "\n"]
            close $fp
            # 第 3 行：步数 + 9 个盒子矢量分量 + 3 个原点分量
            if {[llength $lines] >= 3} {
                set data [lindex $lines 2]
                # 第 10 列（索引 9）就是 c_z，即 z 方向盒子长度
                set lz [lindex $data 9]
                if {$lz ne ""} { set lengthZ $lz }
            }
        }
        # 读不到就用 eq 平衡后的实际盒子长度兜底
        if {$lengthZ <= 0.0} {
            set lengthZ 87.539
            print "WARNING: Cannot read xsc, using default lengthZ=$lengthZ"
        }

        # 从文件加载离子 ID 和电荷列表
        if {[file exists $ionFile]} {
            set fp [open $ionFile r]
            set data [split [read $fp] "\n"]
            close $fp
            set count 0
            foreach line $data {
                # 去掉首尾空白
                set line [string trim $line]
                # 跳过空行和注释行
                if {$line eq ""} continue
                if {[string index $line 0] eq "#"} continue
                # 取出该行所有非空白字段（ID 和电荷）
                set parts [regexp -inline -all {\S+} $line]
                if {[llength $parts] >= 2} {
                    lappend ionIDs [lindex $parts 0]
                    lappend ionCharges [lindex $parts 1]
                    incr count
                }
            }
            print "tclForces: Loaded $count ions, lengthZ=$lengthZ, period=$period_ns ns, Vmax=$vmax V"
        } else {
            print "tclForces: ERROR ion_ids.dat not found at $ionFile"
        }
    }

    # ---------- 每次调用：算当前电压并加力 ----------
    # 当前步数
    set step [getstep]
    # 换算成时间（ns）：每步 2 fs = 2.0e-6 ns
    set t_ns [expr {$step * 2.0e-6}]

    # 已完成的整周期数
    set n_p  [expr {int(floor($t_ns / $period_ns))}]
    # 当前周期内的余数时间（0 ~ period_ns）
    set tmod [expr {$t_ns - $n_p * $period_ns}]
    # 四分之一周期（上升段时间跨度）
    set qt   [expr {$period_ns / 4.0}]
    # 半周期（下降段时间跨度）
    set hf   [expr {$period_ns / 2.0}]

    # 三角波电压：三段线性
    if {$tmod < $qt} {
        # 第一段：0 → +Vmax
        set V [expr {$vmax * $tmod / $qt}]
    } elseif {$tmod < [expr {3.0 * $qt}]} {
        # 第二段：+Vmax → −Vmax
        set V [expr {$vmax * (1.0 - 2.0 * ($tmod - $qt) / $hf)}]
    } else {
        # 第三段：−Vmax → 0
        set V [expr {$vmax * ($tmod - $period_ns) / $qt}]
    }

    # z 方向电场强度，单位 kcal/(mol·Å·e)
    set Ez [expr {$eFieldFactor * $V / $lengthZ}]

    # 遍历所有离子，施加 z 方向的电场力
    set n [llength $ionIDs]
    for {set i 0} {$i < $n} {incr i} {
        set id [lindex $ionIDs $i]
        set q  [lindex $ionCharges $i]
        # Fz = q × Ez，x/y 方向无外力
        set fz [expr {$q * $Ez}]
        addforce $id "0.0 0.0 $fz"
    }
}
