# ============================================================
#  make_bfactor_pdbs.tcl
#
#  给一个“已经建好”的溶剂化体系重新生成两个 NAMD 用的 B 字段 PDB，
#  不需要重建体系：
#
#      ${SYS_PREFIX}.psf  /  ${SYS_PREFIX}.pdb
#        ->  cnt_restrain.pdb   CNT 碳 B=1
#                               (NAMD: conskfile / consref / conskcol B)
#        ->  cnt_langevin.pdb   水 + 离子 B=1
#                               (NAMD: langevinFile / langevinCol B)
#
#  用法（Ubuntu / Linux）：
#      SYS_PREFIX=/path/to/system_ion vmd -dispdev none -e make_bfactor_pdbs.tcl
#
#  SYS_PREFIX 默认为 ./system_ion。两个 PDB 文件写在输入文件旁边，
#  这样它们的原子数和顺序一定与结构文件一致
#  （NAMD 会拒绝原子数对不上的 B 字段文件）。
# ============================================================

if {[info exists env(SYS_PREFIX)] && $env(SYS_PREFIX) ne ""} {
    set prefix [file normalize $env(SYS_PREFIX)]
} else {
    set prefix [file join [pwd] system_ion]
}
set psf "$prefix.psf"
set pdb "$prefix.pdb"
set outdir [file dirname $prefix]

foreach f [list $psf $pdb] {
    if {![file exists $f]} {
        puts "ERROR: input not found: $f"
        puts "       Point SYS_PREFIX at the system prefix, e.g.:"
        puts "       SYS_PREFIX=/path/to/system_ion vmd -dispdev none -e make_bfactor_pdbs.tcl"
        exit 1
    }
}

catch {mol delete all}
mol load psf $psf pdb $pdb

set all [atomselect top "all"]
puts "Input     : $psf"
puts "            $pdb"
puts "Atoms     : [$all num]"

# ---- cnt_restrain.pdb：CNT 碳 B=1 ----
# 冠醚氧（类型 OX，老模型里可能是 OS）保持 B=0，也就是自由运动；
# 水和离子同样是 B=0。
$all set beta 0.0
set c [atomselect top "segname CNT and name C"]
if {[$c num] < 100} { set c [atomselect top "segname CNT and not type OX and not type OS"] }
$c set beta 1.0
$all writepdb [file join $outdir cnt_restrain.pdb]
puts "Restraint : [file join $outdir cnt_restrain.pdb]"
puts "            B=1 on [$c num] CNT carbons (crown O / water / ions free)"

# ---- cnt_langevin.pdb：水 + 离子 B=1 ----
$all set beta 0.0
set m [atomselect top "not segname CNT"]
$m set beta 1.0
$all writepdb [file join $outdir cnt_langevin.pdb]
puts "Langevin  : [file join $outdir cnt_langevin.pdb]"
puts "            B=1 on [$m num] water/ion atoms"

quit
