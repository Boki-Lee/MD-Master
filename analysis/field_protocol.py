#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
field_protocol.py -- 本项目电场协议的公共定义（供 analysis 下各脚本 import）

协议（完整说明见 4prod/README.md）：

    轴向：恒定 5 V 直流        Ez = V_axial / Lz
    径向：从管轴向外辐射的三角波 10 V / 4 ns
          Er(r,t) = V_rad(t) / ( r · ln(R_out/r_in) )，r < r_in 处按 r_in 截断
    两者都只作用在离子上；V_rad > 0 表示电场指向"远离管轴"。

这里集中三件事，免得三个绘图脚本各抄一份波形代码、各写一个 xsc 解析器：

    1) 协议默认参数（与 4prod/field_axial_dc_radial_tri.tcl 保持一致）
    2) radial_voltage()：三角波，与 tcl 里的 triWave 同形
    3) load_field_log()：读 4prod/field_log.dat，用模拟里**实际**施加的波形
    4) read_xsc()：读 NAMD 的 .xsc（盒子 + 盒子中心 = 管轴）

★ 改协议参数时，4prod/field_axial_dc_radial_tri.tcl 和这里要一起改；
  更稳的办法是让 4prod 把波形写进 field_log.dat，脚本默认就会优先用它。
"""

import os

import numpy as np

# ---- 协议默认值（必须与 4prod/field_axial_dc_radial_tri.tcl 一致）----
# 轴向波形：'const' = 恒定直流（本项目）; 'tri' = 三角波（旧协议 / 经典 I-V 扫描）
AXIAL_MODE = 'const'
V_AXIAL = 5.0            # 轴向恒定电压 (V)，AXIAL_MODE='const' 时用
AXIAL_PERIOD = 8.0       # 轴向三角波周期 (ns)，AXIAL_MODE='tri' 时用
AXIAL_VMAX = 10.0        # 轴向三角波峰值 (V)
VMAX_RAD = 10.0          # 径向三角波峰值 (V)
PERIOD_RAD = 4.0         # 径向三角波周期 (ns)
TRI_BIPOLAR = True       # True = 双极性(向外↔向内)，False = 整流(始终向外)
R_IN = 2.0               # 径向 1/r 的内参考半径 (Å)
TUBE_R = 15.58           # 管半径 (Å)：内外分界 / 管壁

# ---- 径向电流统计用的柱面（Å）----
# 默认按本项目实测的"管壁两侧各有约 5 Å 离子排斥层"来取：
#   9 Å  = 柱心有效区边界；15.58 Å = 管壁本身；22 Å = 管外本体内边界
# （WORKFLOW 第 5 节：不能拿 r<13 当"管内"，要拿柱心对远处本体比）
SHELL_RADII = (9.0, TUBE_R, 22.0)

# ---- 常用文件路径（相对 analysis/ 运行）----
FIELD_LOG = '../4prod/field_log.dat'
XSC = '../3eq/eq.restart.xsc'


# ============================================================
# 电压波形
# ============================================================
def radial_voltage(t_ns, period=PERIOD_RAD, vmax=VMAX_RAD, bipolar=TRI_BIPOLAR):
    """径向三角波电压 V_rad(t)，与 4prod 里 triWave 的逻辑完全一致。

    t=0 → 0；t=T/4 → +vmax；t=3T/4 → −vmax；t=T → 0。
    bipolar=False 时取绝对值（整流，始终向外）。
    支持标量与数组（返回 np.ndarray）。
    """
    t = np.asarray(t_ns, dtype=float)
    tm = np.mod(t, period)
    qt = period / 4.0
    hf = period / 2.0
    V = np.where(tm < qt,
                 vmax * tm / qt,
                 np.where(tm < 3.0 * qt,
                          vmax * (1.0 - 2.0 * (tm - qt) / hf),
                          vmax * (tm - period) / qt))
    if not bipolar:
        V = np.abs(V)
    return V


def axial_voltage(t_ns, mode=AXIAL_MODE, v0=V_AXIAL,
                  period=AXIAL_PERIOD, vmax=AXIAL_VMAX):
    """轴向电压 V_axial(t)。

    mode='const'：恒定直流（本项目：5 V，用来测稳态直流电导）
    mode='tri'  ：三角波（旧协议：扫描变量，用来出经典 I-V 曲线）
    三角波形状与径向那个完全一样（同一个 radial_voltage 实现）。
    """
    t = np.asarray(t_ns, dtype=float)
    if mode == 'const':
        return np.full_like(t, v0)
    return radial_voltage(t, period, vmax, True)


def radial_field(V_rad, r, r_in=R_IN, r_out=None, L_xy=None):
    """径向电场强度 Er(r) [V/Å]；r_out=None 时取 min(Lx,Ly)/2。"""
    if r_out is None:
        r_out = 0.5 * min(L_xy)
    rr = np.maximum(np.asarray(r, dtype=float), r_in)
    return np.asarray(V_rad, dtype=float) / (rr * np.log(r_out / r_in))


# ============================================================
# 实际施加的波形：4prod/field_log.dat
# ============================================================
def load_field_log(path=FIELD_LOG):
    """读 4prod/field_log.dat（电场脚本每 printEvery 步写一行）。

    列：step  t_ns  V_axial_V  V_rad_V  Ez_V_per_A  Er_wall_V_per_A
    返回 dict(t, V_axial, V_rad, Ez, Er_wall)；文件不存在时返回 None。
    """
    if not os.path.exists(path):
        return None
    try:
        d = np.loadtxt(path)
    except Exception:
        return None
    if d.ndim == 1:
        d = d.reshape(1, -1)
    if d.shape[1] < 4:
        return None
    return dict(t=d[:, 1], V_axial=d[:, 2], V_rad=d[:, 3],
                Ez=d[:, 4] if d.shape[1] > 4 else None,
                Er_wall=d[:, 5] if d.shape[1] > 5 else None,
                path=path)


def voltage_series(t_ns, log=None, period=PERIOD_RAD, vmax=VMAX_RAD,
                   bipolar=TRI_BIPOLAR, verbose=True):
    """给一组时间点返回 (V_axial, V_rad, 是否用了 field_log)。

    优先用 field_log.dat 里**实际**施加的波形——这样即使改了周期/峰值、
    或者跑了整流模式，也不用改分析脚本。但要处理两种"覆盖不全"：

      · 日志每 printEvery 步才写一行，所以它**永远差最后小半截**轨迹；
      · 日志开头可能缺失（比如中途被删过）。

    所以做法是：**先在重叠区把日志和公式比一比**——
      - 一致（差异 < 1e-3 V）→ 说明脚本参数就是模拟用的参数，直接用公式
        （覆盖完整、还免了插值），不算警告；
      - 不一致 → 说明模拟用了别的参数，以日志为准，缺口用公式补，并说明；
      - 覆盖不到一半 → 警告并退回公式。
    """
    t = np.asarray(t_ns, dtype=float)
    V_formula = radial_voltage(t, period, vmax, bipolar)

    if log is None or len(log['t']) < 2:
        if verbose:
            print("[提示] 没读到可用的 field_log.dat，按公式重建波形"
                  "（周期 %.3f ns、峰值 %.1f V、%s）"
                  % (period, vmax, "双极性" if bipolar else "整流"))
        return axial_voltage(t), V_formula, False

    lt = np.asarray(log['t'], dtype=float)
    t0, t1 = float(lt[0]), float(lt[-1])
    inside = (t >= t0) & (t <= t1)
    cov = float(inside.mean()) if len(t) else 0.0

    dev = np.inf
    if inside.sum() >= 10:
        v_log = np.interp(t[inside], lt, log['V_rad'])
        dev = float(np.max(np.abs(v_log - V_formula[inside])))

    if cov > 0.99 and dev < 1.0e-3:
        # 日志与公式一致：脚本参数 == 模拟参数，直接用公式（无插值、无缺口）
        if verbose:
            print("波形：field_log.dat 与按参数重建的一致（重叠区最大差 %.1e V，覆盖 %.1f%%），"
                  "采用重建波形" % (dev, 100 * cov))
        return axial_voltage(t), V_formula, True

    if cov > 0.5:
        # 模拟用的参数与脚本默认不同：以日志为准，缺口用公式补
        Vrad = V_formula.copy()
        Vrad[inside] = np.interp(t[inside], lt, log['V_rad'])
        Vax = axial_voltage(t)
        Vax[inside] = np.interp(t[inside], lt, log['V_axial'])
        if verbose:
            print("[注意] field_log.dat 显示模拟用的波形与 --period/--vmax 不一致"
                  "（重叠区最大差 %.3f V），已按日志取值，缺口 %.1f%% 用公式补"
                  % (dev, 100 * (1 - cov)))
        return Vax, Vrad, True

    if verbose:
        print("[警告] %s 只覆盖 t = %.4f ~ %.4f ns，覆盖不了轨迹的 %.4f ~ %.4f ns"
              % (log.get('path', 'field_log.dat'), t0, t1, float(t.min()), float(t.max())))
        print("       退回按公式重建波形（周期 %.3f ns、峰值 %.1f V、%s）；"
              "若模拟用了别的参数请用 --period/--vmax 指定"
              % (period, vmax, "双极性" if bipolar else "整流"))
    return axial_voltage(t), V_formula, False


def scan_variable(t_ns, log=None, period=PERIOD_RAD, vmax=VMAX_RAD,
                  axial_mode=AXIAL_MODE, axial_period=AXIAL_PERIOD,
                  axial_vmax=AXIAL_VMAX, verbose=False):
    """判断"哪个电压是扫描变量"，返回 (V_scan, 名字, V_axial, V_rad)。

    优先轴向（经典 I-V 协议），其次径向（本项目：轴向直流 + 径向三角波）。
    两个都不变（纯直流）时返回名字 'none'，调用方可跳过"随电压变化"的图。
    """
    Vax, Vrad, _ = voltage_series(t_ns, log, period, vmax, verbose=verbose)
    if axial_mode == 'tri' and np.ptp(Vax) <= 1.0e-6:
        Vax = axial_voltage(t_ns, 'tri', V_AXIAL, axial_period, axial_vmax)
    if np.ptp(Vax) > 1.0e-6:
        return Vax, 'V_axial', Vax, Vrad
    if np.ptp(Vrad) > 1.0e-6:
        return Vrad, 'V_rad', Vax, Vrad
    return np.zeros_like(np.asarray(t_ns, float)), 'none', Vax, Vrad


# ============================================================
# 盒子
# ============================================================
def read_xsc(path=XSC):
    """读 NAMD 的 .xsc，返回 (Lx, Ly, Lz, ox, oy)。

    第 3 行：step a_x a_y a_z b_x b_y b_z c_x c_y c_z o_x o_y o_z ...
    注意 NAMD 里 (o_x, o_y, o_z) 是**盒子中心**；本项目管轴正好在 (o_x, o_y)。
    读不到就退回旧项目 eq 后的实测值。
    """
    if os.path.exists(path):
        for line in open(path):
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            p = s.split()
            if len(p) >= 13:
                ax, ay, az = float(p[1]), float(p[2]), float(p[3])
                bx, by, bz = float(p[4]), float(p[5]), float(p[6])
                cx, cy, cz = float(p[7]), float(p[8]), float(p[9])
                return (np.sqrt(ax * ax + ay * ay + az * az),
                        np.sqrt(bx * bx + by * by + bz * bz),
                        np.sqrt(cx * cx + cy * cy + cz * cz),
                        float(p[10]), float(p[11]))
    return 51.152, 51.144, 87.5394453258, 0.0, 0.0


def read_ions(path='../1model/ion_ids.dat'):
    """读 ion_ids.dat，返回 (ids, charges, names)。ID 是 0-based。"""
    ids, qs, names = [], [], []
    with open(path) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            p = line.split()
            ids.append(int(p[0]))
            qs.append(float(p[1]))
            names.append(p[2] if len(p) > 2 else '')
    return np.array(ids), np.array(qs), np.array(names)


def probe_dcd(path):
    """自动探测 DCD 布局：原子数、帧长、帧数、三个坐标块的文件绝对偏移。

    ★★ 这里返回的是**文件绝对偏移**（已经加上了文件头长度），不是帧内偏移。
       调用方按 `base = i * frame_len; seek(base + xabs)` 用即可。

       旧项目的版本返回的是"帧内相对偏移"，调用方又写死 HDR = 0，
       结果每帧都早读了 276 字节（= 69 个原子），拿到的其实是
       `ids - 69` 号原子的坐标——离子被换成了水分子。
       （2026-10-04 用 VMD 逐帧对照时发现，已修。）

    DCD 布局（本项目 23045 原子为例）：
        [文件头 276 B] 每帧 = [晶胞块 56 B][X 块 92188][Y 块 92188][Z 块 92188]
        每个坐标块 = 4 B 长度 + 4·NATOM 数据 + 4 B 长度
    """
    import os
    import struct
    f = open(path, 'rb')
    n = struct.unpack('<i', f.read(4))[0]
    hdr = f.read(n)
    f.read(4)
    if hdr[:4] != b'CORD':
        f.close()
        raise ValueError('不是标准 DCD 文件（magic=%r）' % hdr[:4])
    nframes = struct.unpack('<i', hdr[4:8])[0]
    n = struct.unpack('<i', f.read(4))[0]
    f.read(n)
    f.read(4)
    n = struct.unpack('<i', f.read(4))[0]
    natom = struct.unpack('<i', f.read(4))[0]
    f.read(4)
    start = f.tell()                      # ★ 第一帧的绝对起点 = 文件头长度
    coord = 4 * natom
    offs = []
    pos = start
    for _ in range(4):
        f.seek(pos)
        sz = struct.unpack('<i', f.read(4))[0]
        if sz == coord:
            offs.append(pos + 4)          # ★ 绝对偏移（含文件头）
        pos += 4 + sz + 4
    f.close()
    if len(offs) < 3:
        raise ValueError('未能在帧首找到 3 个坐标块')
    frame_len = pos - start
    # 自检：文件剩余长度应当正好是整数帧
    rest = os.path.getsize(path) - start
    if frame_len <= 0 or abs(rest / frame_len - round(rest / frame_len)) > 1e-9:
        raise ValueError('帧长自检失败：文件头后剩 %d 字节，算出帧长 %d，除不尽'
                         % (rest, frame_len))
    return natom, frame_len, nframes, offs[0], offs[1], offs[2]


def ion_radius(x, y, ox=0.0, oy=0.0, Lx=None, Ly=None):
    """离子到管轴的径向距离（x/y 做最小镜像，防止坐标被折回时算错方向）。

    NAMD 输出用 wrapAll 折回原胞、且管轴=盒子中心时，(x−ox) 本来就在
    ±Lx/2 内，最小镜像是个空操作；留着是为了坐标没折回时也正确。
    """
    dx = np.asarray(x, dtype=float) - ox
    dy = np.asarray(y, dtype=float) - oy
    if Lx:
        dx = dx - Lx * np.round(dx / Lx)
    if Ly:
        dy = dy - Ly * np.round(dy / Ly)
    return np.hypot(dx, dy)


# DCD 采样：每 FREQ 步一帧，步长 DT
DT = 2.0e-15
FREQ = 1000


def frame_times(nframes, first=0, freq=FREQ, dt=DT):
    """帧号 -> 物理时间 (ns)，与 ion-cur.tcl 的时间轴定义一致。"""
    return (first + np.arange(nframes) + 0.5) * freq * dt * 1e9


if __name__ == '__main__':
    # 直接运行本文件时做个自检：打印协议参数和一段波形
    log = load_field_log()
    print("协议：轴向恒定 %.1f V，径向三角波 %.1f V / %.1f ns（%s）"
          % (V_AXIAL, VMAX_RAD, PERIOD_RAD,
             "双极性" if TRI_BIPOLAR else "整流"))
    Lx, Ly, Lz, ox, oy = read_xsc()
    print("盒子：%.3f × %.3f × %.3f Å，管轴 (%.4f, %.4f)" % (Lx, Ly, Lz, ox, oy))
    print("径向统计柱面：%s Å" % ", ".join("%.2f" % r for r in SHELL_RADII))
    print("field_log.dat：%s" % ("已找到，绘图将用实际波形" if log else "没找到，绘图将用公式"))
    print()
    print("  t[ns]   V_rad[V]")
    for t in np.arange(0.0, 2 * PERIOD_RAD + 1e-9, PERIOD_RAD / 4):
        print("  %6.2f   %8.4f" % (t, radial_voltage(t)))
