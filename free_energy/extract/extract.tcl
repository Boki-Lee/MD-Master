# ======================================================================
# 提取伞形采样窗口的起始构象（基于 colvars.traj 的绝对真实距离）
# 从 SMD 轨迹里，为每个窗口中心找出 z_dist 最接近的那一帧，导出 win_XX.XX.pdb
# 参考：外部伞形采样项目模板（原项目路径已省略）
# ======================================================================
set psf          "../1model/system_ion.psf"
set dcd          "../smd/smd_output.dcd"
set colvars_file "../smd/smd_output.colvars.traj"
set outdir       "../us"

set dcdfreq      500

# ---- 读窗口中心（与 us/setup_us.sh 共用同一份 windows.txt）----
set fp [open "../us/windows.txt" r]
set target_list {}
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} { continue }
    set f [regexp -inline -all -- {\S+} $line]
    lappend target_list [lindex $f 0]
}
close $fp
puts "目标窗口数: [llength $target_list]"

mol new $psf
mol addfile $dcd waitfor all
set num_frames [molinfo top get numframes]
puts "DCD 总帧数: $num_frames"

# ---- 解析 colvars.traj：提取 (step, z_dist) ----
set fp [open $colvars_file r]
set step_z_list {}
while {[gets $fp line] >= 0} {
    if {[string match "#*" $line] || [string trim $line] eq ""} { continue }
    set fields [regexp -inline -all -- {\S+} $line]
    if {[llength $fields] >= 2} {
        lappend step_z_list [list [lindex $fields 0] [lindex $fields 1]]
    }
}
close $fp
puts "colvars 数据行: [llength $step_z_list]"

# ---- 判断 DCD 是否缺第 0 步（决定 step→frame 是否减 1）----
set expected_frames [expr {1000000 / $dcdfreq + 1}]
set offset 0
if {$num_frames < $expected_frames} { set offset -1 }

set all [atomselect top all]
puts "开始提取构象..."
foreach target $target_list {
    set min_diff 9999.0
    set best_step 0
    set actual_z 0.0
    foreach record $step_z_list {
        set step    [lindex $record 0]
        set z_dist  [lindex $record 1]
        set diff    [expr {abs($z_dist - $target)}]
        if {$diff < $min_diff} { set min_diff $diff; set best_step $step; set actual_z $z_dist }
    }
    set frame_idx [expr {int($best_step / $dcdfreq)}]
    if {$best_step > 0} { set frame_idx [expr {$frame_idx + $offset}] }
    if {$frame_idx < 0} { set frame_idx 0 }
    if {$frame_idx >= $num_frames} { set frame_idx [expr {$num_frames - 1}] }

    $all frame $frame_idx
    set filename [format "$outdir/win_%.2f.pdb" $target]
    $all writepdb $filename
    puts [format "  win_%.2f.pdb | 目标 %.2f | 实际 z %.3f | step %7s -> frame %d" \
        $target $target $actual_z $best_step $frame_idx]
}
puts "完成：所有窗口构象已写入 $outdir/"
quit
