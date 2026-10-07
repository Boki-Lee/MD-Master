#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态校验 CNT1 目录下的 NAMD 配置（七文件夹结构）：

   1) 配置里引用的文件是否都存在（含 tclForcesScript）
   2) 续算文件链是否完整（2min → 3eq → 4prod）
   3) PSF / PDB / B 字段文件的原子数是否一致
   4) 盒子是否与 CRYST1 一致；原子是否都在盒内
   5) PSF 里出现的键、角类型是否都能在力场参数文件中找到
   6) ★ 径向电场专项：管轴位置 vs 盒子中心、ion_ids.dat 与 PSF 的离子是否对得上

第 6 条是本项目新增的：径向电场以管轴为中心，如果管轴和 NAMD 的盒子中心
（PERIODIC CELL CENTER）不重合，力就会整体偏心；ion_ids.dat 的 ID 对错了
则会悄悄给错的原子加力。这两件事光看配置发现不了，必须静态算一遍。

用法（在项目根目录）：
    python3 0build/check_setup.py
"""
import glob
import os
import re
import sys

# 项目根目录 = 本脚本所在目录（0build/）的上一级 —— 换项目不用改这里
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M1 = os.path.join(ROOT, "1model")
PSF = os.path.join(M1, "system_ion.psf")
PDB = os.path.join(M1, "system_ion.pdb")
RESTRAIN = os.path.join(M1, "cnt_restrain.pdb")
LANGEVIN = os.path.join(M1, "cnt_langevin.pdb")
IONIDS = os.path.join(M1, "ion_ids.dat")
FFDIR = os.path.join(ROOT, "forcefield")
# 自动收集三个阶段下所有 *.conf（含续算用的 prod2.conf 之类）
CONFS = []
for _d in ("2min", "3eq", "4prod"):
    _p = os.path.join(ROOT, _d)
    if os.path.isdir(_p):
        CONFS += sorted(glob.glob(os.path.join(_p, "*.conf")))

PAR_FILES = [
    "par_all36_prot.prm", "par_all36_lipid.prm", "par_water_ions_na.prm",
    "par_all36_na.prm", "C_O.par",
]

ok = True


def fail(msg):
    global ok
    ok = False
    print("  [失败] " + msg)


def good(msg):
    print("  [通过] " + msg)


def note(msg):
    print("      " + msg)


def read(path, **kw):
    return open(path, encoding="utf-8", errors="ignore", **kw).read()


# ============================================================
# 1) 配置文件引用的文件
# ============================================================
print("=== 1) 配置文件引用的文件 ===")
ref_keys = ("parameters", "structure", "coordinates", "langevinFile",
            "consref", "conskfile", "tclForcesScript")
for conf in CONFS:
    if not os.path.exists(conf):
        fail("缺配置文件 %s" % conf)
        continue
    cdir = os.path.dirname(conf)
    cname = os.path.relpath(conf, ROOT)
    text = read(conf)
    refs = re.findall(r"^\s*(?:%s)\s+(\S+)" % "|".join(ref_keys), text, re.M)
    if not refs:
        fail("%s 里没解析到任何文件引用" % cname)
    for rel in refs:
        target = os.path.normpath(os.path.join(cdir, rel))
        if os.path.exists(target):
            good("%-16s -> %s" % (os.path.basename(conf), rel))
        else:
            fail("%-16s -> %s 不存在（解析为 %s）" % (os.path.basename(conf), rel, target))

for f in ["system_ion.psf", "system_ion.pdb", "cnt_restrain.pdb",
          "cnt_langevin.pdb", "ion_ids.dat"]:
    if not os.path.exists(os.path.join(M1, f)):
        fail("1model/ 缺 %s" % f)

# ============================================================
# 2) 续算文件链
# ============================================================
print()
print("=== 2) 续算文件链（2min → 3eq → 4prod）===")
for conf in CONFS:
    text = read(conf)
    cdir = os.path.dirname(conf)
    m = re.search(r"^\s*set\s+inputname\s+(\S+)", text, re.M)
    if not m:
        # 续算配置常常直接写 binCoordinates / extendedSystem，不写 inputname
        mb = re.search(r"^\s*binCoordinates\s+(\S+)", text, re.M)
        me = re.search(r"^\s*extendedSystem\s+(\S+)", text, re.M)
        if mb:
            need = [mb.group(1)] + ([me.group(1)] if me else [])
            miss = [f for f in need if not os.path.exists(os.path.normpath(os.path.join(cdir, f)))]
            if miss:
                fail("%-10s 续算文件缺失: %s" % (os.path.basename(conf), ", ".join(miss)))
            else:
                good("%-10s 从 %s 续算" % (os.path.basename(conf), mb.group(1)))
        else:
            note("%-10s 没有 inputname/binCoordinates（第一步，符合预期）" % os.path.basename(conf))
        continue
    base = os.path.normpath(os.path.join(cdir, m.group(1)))
    found_new = all(os.path.exists(base + s) for s in (".restart.coor", ".restart.vel", ".restart.xsc"))
    found_old = all(os.path.exists(base + s + ".old") for s in (".restart.coor", ".restart.vel", ".restart.xsc"))
    if found_new:
        good("%-10s 从 %s.restart.* 续算" % (os.path.basename(conf), m.group(1)))
    elif found_old:
        good("%-10s 从 %s.restart.*.old 续算（新文件还没生成）" % (os.path.basename(conf), m.group(1)))
    elif os.path.basename(conf) == "prod.conf":
        # 4prod 是最终要跑的那一步，它的前置必须有
        fail("%-10s 找不到 %s.restart.coor/vel/xsc（也没有 .old）" % (os.path.basename(conf), m.group(1)))
    else:
        note("[提示] %-10s 的前置 %s.restart.* 还不存在 —— 这一步还没跑过。"
             % (os.path.basename(conf), m.group(1)))
        note("       CNT1 的平衡态是从旧项目导入的（3eq/eq.restart.*），")
        note("       只想跑 4prod 的话不用管；要自己重跑 min/eq 就先跑 2min。")

# ============================================================
# 3) 原子数一致性
# ============================================================
print()
print("=== 3) 原子数一致性 ===")


def natom_pdb(path):
    n = 0
    for line in open(path, errors="ignore"):
        if line.startswith(("ATOM", "HETATM")):
            n += 1
    return n


psf_natom = None
for line in open(PSF, errors="ignore"):
    m = re.match(r"\s*(\d+)\s+!NATOM", line)
    if m:
        psf_natom = int(m.group(1))
        break
counts = {"system_ion.psf": psf_natom, "system_ion.pdb": natom_pdb(PDB),
          "cnt_restrain.pdb": natom_pdb(RESTRAIN), "cnt_langevin.pdb": natom_pdb(LANGEVIN)}
for k, v in counts.items():
    print("      %-18s %s 原子" % (k, v))
if len(set(counts.values())) == 1:
    good("四个文件的原子数完全一致")
else:
    fail("原子数不一致，NAMD 会拒绝读取 B 字段文件")

# ============================================================
# 4) 盒子
# ============================================================
print()
print("=== 4) 盒子与 CRYST1 / xsc 一致性 ===")
cryst = None
for line in open(PDB, errors="ignore"):
    if line.startswith("CRYST1"):
        cryst = [float(line[6:15]), float(line[15:24]), float(line[24:33])]
        break
if cryst is None:
    fail("system_ion.pdb 里没有 CRYST1 记录")
else:
    good("CRYST1 = %.3f %.3f %.3f" % tuple(cryst))

for conf in CONFS:
    text = read(conf)
    vecs = re.findall(r"^\s*cellBasisVector[123]\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)", text, re.M)
    if not vecs:
        note("%-10s 未写 cellBasisVector（从 .xsc 续算文件读取，符合预期）" % os.path.basename(conf))
        continue
    got = [float(v[i]) for i, v in enumerate(vecs)]
    if cryst and all(abs(a - b) < 1e-3 for a, b in zip(got, cryst)):
        good("%-10s box = %.3f %.3f %.3f，与 CRYST1 一致" % (os.path.basename(conf), *got))
    else:
        fail("%-10s box = %s，与 CRYST1 %s 不一致" % (os.path.basename(conf), got, cryst))

    # NAMD 的 cellOrigin 是「盒子中心」，不是角点。据此算出真实盒子范围，
    # 再检查所有原子是否都在盒内（有原子在盒外时 NAMD 会包裹输出，
    # 可能把水和碳管错开半个盒子，看起来像"碳管一半没在水里"）。
    mo = re.search(r"^\s*cellOrigin\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)", text, re.M)
    center = [float(mo.group(i)) for i in (1, 2, 3)] if mo else [0.0, 0.0, 0.0]
    lo = [center[i] - got[i] / 2.0 for i in range(3)]
    hi = [center[i] + got[i] / 2.0 for i in range(3)]
    nout, first = 0, None
    for pdbfile in (PDB, RESTRAIN, LANGEVIN):
        for line in open(pdbfile, errors="ignore"):
            if not line.startswith(("ATOM", "HETATM")):
                continue
            xyz = [float(line[30:38]), float(line[38:46]), float(line[46:54])]
            if not all(lo[i] - 1e-6 <= xyz[i] <= hi[i] + 1e-6 for i in range(3)):
                nout += 1
                if first is None:
                    first = (os.path.basename(pdbfile), xyz)
    if nout == 0:
        good("盒子中心 (%.3f, %.3f, %.3f) → z ∈ [%.2f, %.2f]，全部原子都在盒内"
             % (center[0], center[1], center[2], lo[2], hi[2]))
    else:
        fail("有 %d 个原子在盒子外，NAMD 会包裹输出、可能造成水和碳管错位（首个 %s: %s）"
             % (nout, first[0], " ".join("%.2f" % v for v in first[1])))

# 4prod 真正继承的是 eq 的 xsc，单独读出来看看
XSC = os.path.join(ROOT, "3eq", "eq.restart.xsc")
xsc_box = xsc_org = None
if os.path.exists(XSC):
    for line in open(XSC, errors="ignore"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        p = s.split()
        if len(p) >= 13:
            ax = [float(p[1]), float(p[2]), float(p[3])]
            by = [float(p[4]), float(p[5]), float(p[6])]
            cz = [float(p[7]), float(p[8]), float(p[9])]
            xsc_box = [sum(v * v for v in ax) ** 0.5, sum(v * v for v in by) ** 0.5,
                       sum(v * v for v in cz) ** 0.5]
            xsc_org = [float(p[10]), float(p[11]), float(p[12])]
            break
if xsc_box:
    good("4prod 继承的 xsc 盒子 = %.3f %.3f %.3f，origin = (%.3f, %.3f, %.3f)"
         % (xsc_box[0], xsc_box[1], xsc_box[2], xsc_org[0], xsc_org[1], xsc_org[2]))
else:
    fail("读不到 %s 的盒子信息" % XSC)

# ============================================================
# 5) 力场参数覆盖
# ============================================================
print()
print("=== 5) PSF 中的键/角类型在力场中的覆盖情况 ===")
types = {}
psf_rows = {}
bonds, angles = [], []
section = None
for line in open(PSF, errors="ignore"):
    if "!NATOM" in line:
        section = "natom"; continue
    if "!NBOND" in line:
        section = "nbond"; continue
    if "!NTHETA" in line:
        section = "ntheta"; continue
    if re.search(r"!(NPHI|NIMPHI|NDON|NACC|NNB|NGRP|MOLNT)", line):
        section = None; continue
    p = line.split()
    if section == "natom" and len(p) >= 8:
        types[p[0]] = p[5]
        psf_rows[int(p[0])] = {"seg": p[1], "resid": p[2], "resname": p[3],
                               "aname": p[4], "type": p[5], "charge": float(p[6])}
    elif section == "nbond":
        for i in range(0, len(p) - 1, 2):
            bonds.append((p[i], p[i + 1]))
    elif section == "ntheta":
        for i in range(0, len(p) - 2, 3):
            angles.append((p[i], p[i + 1], p[i + 2]))

print("      原子类型: " + ", ".join(sorted(set(types.values()))))
bond_types = set()
for a, b in bonds:
    bond_types.add(tuple(sorted((types[a], types[b]))))
angle_types = set()
for a, b, c in angles:
    angle_types.add((types[a], types[b], types[c]))
print("      键类型 %d 种，角类型 %d 种" % (len(bond_types), len(angle_types)))

par_bonds, par_angles, masses = set(), set(), set()
for fn in PAR_FILES:
    path = os.path.join(FFDIR, fn)
    if not os.path.exists(path):
        fail("缺力场文件 %s" % fn); continue
    sec = None
    for line in open(path, errors="ignore"):
        s = line.strip()
        if not s or s.startswith(("*", "!")):
            continue
        up = s.upper()
        if up.startswith("BOND"):
            sec = "BOND"; continue
        if up.startswith("ANGLE"):
            sec = "ANGLE"; continue
        if up.startswith("DIHEDRAL") or up.startswith("IMPROPER") or up.startswith("NONBONDED") \
           or up.startswith("NBFIX") or up.startswith("HBOND") or up.startswith("END"):
            sec = None; continue
        if up.startswith("MASS"):
            p = s.split()
            if len(p) >= 3:
                masses.add(p[2])
            continue
        if up.startswith(("ATOM", "RESI", "GROUP", "PRES", "BONDED", "PATCH", "DEFA", "AUTOGEN")):
            if up.startswith("ATOM"):
                p = s.split()
                if len(p) >= 2:
                    masses.add(p[1])
            continue
        p = s.split()
        if sec == "BOND" and len(p) >= 2:
            par_bonds.add(tuple(sorted((p[0], p[1]))))
        elif sec == "ANGLE" and len(p) >= 3:
            par_angles.add((p[0], p[1], p[2]))
            par_angles.add((p[2], p[1], p[0]))

missing = sorted(t for t in bond_types if t not in par_bonds)
if missing:
    fail("以下键类型在力场里找不到参数: %s" % ", ".join("-".join(t) for t in missing))
else:
    good("所有 %d 种键类型都有参数" % len(bond_types))

missing = sorted(t for t in angle_types if t not in par_angles)
if missing:
    fail("以下角类型在力场里找不到参数: %s" % ", ".join("-".join(t) for t in missing))
else:
    good("所有 %d 种角类型都有参数" % len(angle_types))

for t in sorted(set(types.values())):
    if t not in masses:
        note("[提示] 类型 %s 在力场里没有 MASS 定义（NAMD 用 PSF 里的质量，一般无碍）" % t)

# ============================================================
# 6) 径向电场专项
# ============================================================
print()
print("=== 6) 径向电场专项（管轴 / ion_ids / 场强量级）===")

# 6a) 管轴：用 CNT 段原子的 x/y 包围盒中心当轴心，和盒子中心比
axis = None
cxs, cys, czs = [], [], []
for line in open(PDB, errors="ignore"):
    if line.startswith(("ATOM", "HETATM")) and line[17:21].strip() == "CNT":
        cxs.append(float(line[30:38]))
        cys.append(float(line[38:46]))
        czs.append(float(line[46:54]))
if cxs:
    axis = [(min(cxs) + max(cxs)) / 2.0, (min(cys) + max(cys)) / 2.0]
    tube_r = max(max(cxs) - min(cxs), max(cys) - min(cys)) / 2.0
    good("CNT 段原子 %d 个，管轴 = (%.4f, %.4f)，管半径 = %.2f Å，管长 = %.2f Å"
         % (len(cxs), axis[0], axis[1], tube_r, max(czs) - min(czs)))
else:
    fail("system_ion.pdb 里找不到 segname=CNT 的原子，无法定位管轴")
    tube_r = None

if axis and xsc_org:
    dx = axis[0] - xsc_org[0]
    dy = axis[1] - xsc_org[1]
    off = (dx * dx + dy * dy) ** 0.5
    if off < 0.05:
        good("管轴与盒子中心 (x,y) 重合（偏差 %.4f Å）→ 径向电场以盒子中心为轴是正确的" % off)
    else:
        fail("管轴 (%0.4f, %0.4f) 与盒子中心 (%0.4f, %0.4f) 偏差 %.3f Å！"
             % (axis[0], axis[1], xsc_org[0], xsc_org[1], off)
             + " 必须在 4prod/field_axial_dc_radial_tri.tcl 里显式设 axisX/axisY")

# 6b) 电场脚本参数
FIELD = os.path.join(ROOT, "4prod", "field_axial_dc_radial_tri.tcl")
if os.path.exists(FIELD):
    ftxt = read(FIELD)
    # 只看真正的代码行：注释里也有 "set vmaxRad 8.0" 这种示例，不能被骗
    code_lines = [l for l in ftxt.splitlines() if not l.lstrip().startswith("#")]
    code_txt = "\n".join(code_lines)

    def tcl_default(name):
        m = re.search(r"set\s+%s\s+([-\d.eE]+)" % name, code_txt)
        return float(m.group(1)) if m else None
    vax = tcl_default("vAxial"); vmax = tcl_default("vmaxRad")
    per = tcl_default("periodRad"); rin = tcl_default("rIn")
    rtu = tcl_default("tubeR")
    note("电场脚本默认参数：vAxial=%s V, vmaxRad=%s V, periodRad=%s ns, rIn=%s Å" % (vax, vmax, per, rin))
    if rtu is not None and tube_r is not None and abs(rtu - tube_r) > 0.5:
        fail("脚本里的 tubeR=%.2f 与实际管半径 %.2f Å 不符（这个只影响日志里的 Er 列，但别留错）"
             % (rtu, tube_r))
    elif rtu is not None:
        good("脚本里的 tubeR=%.2f 与实际管半径 %.2f Å 一致" % (rtu, tube_r))
    if all(v is not None for v in (vax, vmax, rin)) and xsc_box:
        import math
        r_out = min(xsc_box[0], xsc_box[1]) / 2.0
        lnr = math.log(r_out / rin)
        ez = vax / xsc_box[2]
        erw = vmax / (tube_r * lnr) if tube_r else float("nan")
        eri = vmax / (rin * lnr)
        note("按 xsc 盒子算出的量级：")
        note("    轴向 Ez = %.5f V/Å" % ez)
        note("    径向峰值 Er：r_in 处 %.4f V/Å，管壁处 %.4f V/Å（= %.2f × Ez）"
             % (eri, erw, erw / ez))
        note("    单电荷离子最大径向力 = %.2f kcal/(mol·Å)（在 r ≤ rIn 处）"
             % (eri * 23.06054917))
        if erw / ez > 3.0:
            note("[注意] 径向场比轴向强 %.1f 倍，属于强驱动；想与轴向可比就把 vmaxRad 降到约 %.2f V"
                 % (erw / ez, ez * tube_r * lnr))
else:
    fail("缺 4prod/field_axial_dc_radial_tri.tcl")

# 6c) ion_ids.dat 与 PSF 的离子是否对得上
if os.path.exists(IONIDS) and psf_rows:
    rows = []
    for line in open(IONIDS, errors="ignore"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        p = s.split()
        if len(p) >= 2:
            rows.append((int(p[0]), float(p[1]), p[2] if len(p) > 2 else ""))
    # ★ ion_ids.dat 是 0-based（NAMD tclForces 的 addforce 用 0-based），
    #   而 PSF 的原子编号是 1-based，所以查表要用 id+1，差一位就会查成前一个原子
    #   （典型症状：第一个离子被当成它前面那个水的氢，电荷 0.417 对不上）
    bad_id = [r for r in rows if (r[0] + 1) not in psf_rows]
    bad_q = [r for r in rows if (r[0] + 1) in psf_rows
             and abs(psf_rows[r[0] + 1]["charge"] - r[1]) > 1e-6]
    bad_nm = [r for r in rows if (r[0] + 1) in psf_rows and r[2]
              and psf_rows[r[0] + 1]["resname"] != r[2]]
    psf_ions = [i for i, v in psf_rows.items() if v["type"] in ("POT", "SOD", "CLA", "CES")]
    npos = sum(1 for r in rows if r[1] > 0)
    nneg = sum(1 for r in rows if r[1] < 0)
    print("      ion_ids.dat: %d 个离子（%d 正 / %d 负）；PSF 里共 %d 个离子型原子"
          % (len(rows), npos, nneg, len(psf_ions)))
    if bad_id:
        fail("ion_ids.dat 里有 %d 个 ID 超出 PSF 范围（第一个 %d）" % (len(bad_id), bad_id[0][0]))
    elif bad_q:
        fail("ion_ids.dat 有 %d 个电荷与 PSF 不一致（第一个 ID=%d，文件 %+.2f vs PSF 第 %d 号原子 %+.2f）"
             % (len(bad_q), bad_q[0][0], bad_q[0][1], bad_q[0][0] + 1,
                psf_rows[bad_q[0][0] + 1]["charge"]))
    elif bad_nm:
        fail("ion_ids.dat 有 %d 个名字与 PSF 不一致（第一个 ID=%d）" % (len(bad_nm), bad_nm[0][0]))
    elif len(rows) != len(psf_ions):
        fail("ion_ids.dat 有 %d 个离子，但 PSF 里有 %d 个，NAMD 会给漏掉的离子加零力"
             % (len(rows), len(psf_ions)))
    else:
        good("ion_ids.dat 的 %d 个 ID / 电荷 / 名字与 PSF 完全一致（0-based，顺序无关）" % len(rows))
        note("ID 范围 %d ~ %d（0-based），对应 PSF 第 %d ~ %d 号原子（1-based），%s ~ %s"
             % (min(r[0] for r in rows), max(r[0] for r in rows),
                min(r[0] for r in rows) + 1, max(r[0] for r in rows) + 1,
                psf_rows[rows[0][0] + 1]["resname"], psf_rows[rows[-1][0] + 1]["resname"]))
else:
    fail("ion_ids.dat 不存在或 PSF 没解析出原子")

# ============================================================
print()
print("=== 结论 ===")
print("  静态校验全部通过，可以按 2min → 3eq → 4prod 跑（3eq 已有现成平衡态，可直接跑 4prod）"
      if ok else "  存在上述问题，需要处理后才能跑 NAMD")
sys.exit(0 if ok else 1)
