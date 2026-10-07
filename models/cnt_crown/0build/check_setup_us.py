#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
静态校验：伞形采样自由能项目在跑 MD 前的自检。

用法：
    python3 check_setup.py            # 自动取脚本上一级为项目根
    python3 check_setup.py /路径/项目

检查项：
    1. 1model/ 产物齐全（system_ion、B 字段 PDB、cell_params、离子/氧序号文件）
    2. 原子数一致（psf == pdb == 三个 B 字段 pdb）
    3. 目标离子个数 / 反离子个数正确
    4. 目标孔 6 个氧的序号有效
    5. 力场 6 个文件齐全
    6. smd/smd.conf、us/template.conf 引用的文件都存在
    7. us/windows.txt 格式正确

不依赖 numpy/MDAnalysis，系统 python3 也能跑。
"""
import os
import re
import sys


def find_root():
    # 脚本在 <root>/0build/ 下，根 = 上一级
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def read_lines(path):
    with open(path, encoding="utf-8", errors="ignore") as f:
        return f.read().splitlines()


def count_pdb_atoms(path):
    n = 0
    for line in read_lines(path):
        if line.startswith(("ATOM", "HETATM")):
            n += 1
    return n


def count_psf_atoms(path):
    for line in read_lines(path):
        m = re.match(r"\s*(\d+)\s+!NATOM", line)
        if m:
            return int(m.group(1))
    return None


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else find_root()
    m1 = os.path.join(root, "1model")
    ff = os.path.join(root, "forcefield")
    ok = True

    def check(cond, msg):
        nonlocal ok
        mark = "PASS" if cond else "FAIL"
        if not cond:
            ok = False
        print(f"  [{mark}] {msg}")

    print(f"项目根目录: {root}\n")

    # ---- 1. 产物齐全 ----
    print("1) 1model/ 产物")
    files = ["system_ion.psf", "system_ion.pdb", "cnt_fixed.pdb",
             "ion_restrain.pdb", "cnt_langevin.pdb", "cell_params.tcl",
             "ion_index.dat", "ox_indices.dat", "pore_info.dat"]
    for fn in files:
        check(os.path.exists(os.path.join(m1, fn)), f"{fn}")

    # ---- 2. 原子数一致 ----
    print("\n2) 原子数一致性")
    try:
        psf_n = count_psf_atoms(os.path.join(m1, "system_ion.psf"))
        pdb_n = count_pdb_atoms(os.path.join(m1, "system_ion.pdb"))
        check(psf_n is not None, "PSF 里能读到 !NATOM")
        check(psf_n == pdb_n, f"psf({psf_n}) == pdb({pdb_n})")
        for bf in ["cnt_fixed.pdb", "ion_restrain.pdb", "cnt_langevin.pdb"]:
            n = count_pdb_atoms(os.path.join(m1, bf))
            check(n == pdb_n, f"{bf} 原子数 == system_ion ({n})")
    except FileNotFoundError:
        print("  [SKIP] 缺少 system_ion，跳过原子数检查")

    # ---- 3. 离子个数 ----
    print("\n3) 离子与目标孔")
    try:
        pot = 0
        cla = 0
        ox = 0
        for line in read_lines(os.path.join(m1, "system_ion.pdb")):
            if line.startswith(("ATOM", "HETATM")):
                name = line[12:16].strip()
                if name == "POT":
                    pot += 1
                elif name == "CLA":
                    cla += 1
                elif name == "O":
                    ox += 1
        check(pot >= 1, f"POT 数 = {pot}（应 ≥1，目标离子）")
        check(cla >= 1, f"CLA 数 = {cla}（反离子）")
        check(ox >= 6, f"冠醚氧 O 数 = {ox}（应 ≥6）")
    except FileNotFoundError:
        pass

    # ---- 4. 序号文件 ----
    print("\n4) colvars 序号文件")
    try:
        ion_idx = int(read_lines(os.path.join(m1, "ion_index.dat"))[0].strip())
        ox_idx = [int(x) for x in read_lines(os.path.join(m1, "ox_indices.dat"))[0].split()]
        check(1 <= ion_idx <= (psf_n or 10 ** 9), f"ion_index = {ion_idx}")
        check(len(ox_idx) == 6, f"ox_indices 有 {len(ox_idx)} 个（应 6）")
    except Exception:
        check(False, "ion_index.dat / ox_indices.dat 解析失败")

    # ---- 5. 力场 ----
    print("\n5) 力场")
    need_ff = ["C_O.par", "par_all36_prot.prm", "par_all36_lipid.prm",
               "par_water_ions_na.prm", "par_all36_na.prm", "toppar_all36_dphpc.str"]
    for fn in need_ff:
        check(os.path.exists(os.path.join(ff, fn)), fn)

    # ---- 6. conf 引用 ----
    print("\n6) NAMD conf 引用")
    confs = [os.path.join(root, "smd", "smd.conf"),
             os.path.join(root, "us", "template.conf")]
    for cf in confs:
        if not os.path.exists(cf):
            check(False, f"{os.path.basename(cf)} 缺失")
            continue
        txt = "\n".join(read_lines(cf))
        # 共同引用：拓扑(psf)、约束/恒温 pdb、盒子、力场
        for ref in ["../1model/system_ion.psf",
                    "../1model/cnt_fixed.pdb", "../1model/ion_restrain.pdb",
                    "../1model/cnt_langevin.pdb", "../1model/cell_params.tcl",
                    "C_O.par"]:
            check(ref in txt, f"{os.path.basename(cf)} 引用 {ref}")
        # 坐标来源不同：smd 用 system_ion.pdb；us 窗口用占位符 WINDOW_PDB_FILE
        base = os.path.basename(cf)
        if base == "smd.conf":
            check("../1model/system_ion.pdb" in txt, "smd.conf 引用 system_ion.pdb")
        else:  # template.conf
            check("WINDOW_PDB_FILE" in txt, "template.conf 用 WINDOW_PDB_FILE 占位符")
        # 坑：NAMD 3 不要写 stepsPerCycle（只看非注释行，避免误报注释里的提示）
        has_spc = any("stepspercycle" in ln.lower() and not ln.lstrip().startswith("#")
                      for ln in read_lines(cf))
        check(not has_spc, f"{os.path.basename(cf)} 没写 stepsPerCycle（NAMD3 禁）")

    # ---- 7. windows.txt ----
    print("\n7) us/windows.txt")
    try:
        nwin = 0
        for line in read_lines(os.path.join(root, "us", "windows.txt")):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            if len(p) < 2:
                check(False, f"行格式错误: {line!r}")
                continue
            float(p[0]); float(p[1])
            nwin += 1
        check(nwin > 0, f"共 {nwin} 个窗口")
    except FileNotFoundError:
        check(False, "windows.txt 缺失")

    print()
    print("=" * 50)
    print("全部通过 ✅" if ok else "存在 FAIL ❌，请先修好再跑 MD")
    print("=" * 50)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
