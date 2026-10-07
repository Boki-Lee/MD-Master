#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
plot_currents.py -- 分解并绘制 prod 轨迹的离子电流（新协议）

本项目协议：轴向恒定 5 V 直流 + 径向三角波 10 V/4 ns。

输出的电流分量：

  轴向 I_z = Σqi·Δzi /(Lz·Δt)
      按离子种类：阳离子(POT) / 阴离子(CLA) / 总
      按径向位置：管内(r<r1) / 管壁限域(r1≤r<r2) / 管外(r≥r2)

  径向 I_r(rs) = −ΔQ_in(rs)/Δt          （穿过半径 rs 圆柱面的净电流）
      rs 默认取 9 / 15.58 / 22 Å：
      9 Å = 柱心有效区，15.58 Å = 管壁（穿过去只能走冠醚孔！），22 Å = 管外本体内边界

★ 与旧版区别：旧版把轴向三角波当扫描变量画 I-V；现在轴向是恒定直流，
  径向才是扫描量。所以这里只出"电流时间序列 + 分解 + 平均值"，
  电压扫描出来的回线交给 plot_iv.py。

用法（在 analysis/ 目录下，需先 conda activate MD）：
    python plot_currents.py
    python plot_currents.py --r1 10.5 --r2 20.6      # 自定义内外分界（Å）
    python plot_currents.py --shells 9 15.58 22      # 自定义径向统计柱面
    python plot_currents.py --smooth 100             # 平滑窗口（帧数，1 帧 = 2 ps）

产物：
    current_components.dat     轴向各分量时间序列
    radial_components.dat      径向电流与柱面占据数时间序列
    fig_currents_time.png      电流-时间（物种/径向分解 + 电压参考线）
    fig_radial_time.png        径向电流与占据数随时间
    fig_current_fraction.png   各分量对总电流的平均贡献
"""

import argparse
import os
import sys

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# 中文字体：系统装了 Noto Sans CJK（没有则退回 DejaVu Sans，中文会显示成方块）
plt.rcParams['font.sans-serif'] = ['Noto Sans CJK SC', 'Droid Sans Fallback',
                                   'WenQuanYi Zen Hei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_protocol as fp

def _tex(vname):
    """把 'V_rad' / 'V_axial' 变成 mathtext 的 '$V_{rad}$' / '$V_{axial}$'"""
    return '$V_{%s}$' % vname[2:] if vname.startswith('V_') else vname


DT = fp.DT
FREQ = fp.FREQ

DCD = '../4prod/prod_full.dcd'
IONFILE = '../1model/ion_ids.dat'
XSC = '../3eq/eq.restart.xsc'


def smooth(y, w):
    """滑动平均。★ 窗口必须夹到数据长度以内：
    np.convolve(mode='same') 在 w > len(y) 时会返回长度 w 的数组，
    画图时就会报 x/y 维度不一致。"""
    n = len(y)
    w = max(1, min(int(w), n))
    if w <= 1:
        return y
    return np.convolve(y, np.ones(w) / w, mode='same')


def main():
    ap = argparse.ArgumentParser(description="分解离子电流并绘图（轴向 DC + 径向 AC）")
    ap.add_argument('--dcd', default=DCD)
    ap.add_argument('--ionfile', default=IONFILE)
    ap.add_argument('--xsc', default=XSC)
    ap.add_argument('--field-log', default=fp.FIELD_LOG)
    ap.add_argument('--r1', type=float, default=10.5, help='管内/管壁分界半径 (Å)')
    ap.add_argument('--r2', type=float, default=20.6, help='管壁/管外分界半径 (Å)')
    ap.add_argument('--shells', type=float, nargs='+', default=list(fp.SHELL_RADII),
                    help='径向电流统计的柱面半径 (Å)')
    ap.add_argument('--smooth', type=int, default=100, help='平滑窗口（帧数）')
    ap.add_argument('--axial-mode', choices=('const', 'tri'), default=fp.AXIAL_MODE,
                    help="轴向波形：const=恒定直流; tri=三角波（经典 I-V 扫描）")
    ap.add_argument('--axial-period', type=float, default=fp.AXIAL_PERIOD)
    ap.add_argument('--axial-vmax', type=float, default=fp.AXIAL_VMAX)
    ap.add_argument('--period', type=float, default=fp.PERIOD_RAD)
    ap.add_argument('--vmax', type=float, default=fp.VMAX_RAD)
    ap.add_argument('--vaxial', type=float, default=fp.V_AXIAL)
    ap.add_argument('--skip-ns', type=float, default=4.0, help='统计平均值时跳过前多少 ns')
    ap.add_argument('--max-frames', type=int, default=0, help='只扫前多少帧（0=全部，调试用）')
    args = ap.parse_args()

    natom, frame_len, nframe, xrel, yrel, zrel = fp.probe_dcd(args.dcd)
    Lx, Ly, Lz, ox, oy = fp.read_xsc(args.xsc)
    ids, q, names = fp.read_ions(args.ionfile)
    is_pot = (names == 'POT')
    is_cla = (names == 'CLA')

    curr_factor     = 1.60217733e-10 / (Lz * DT * FREQ)   # 轴向：nA per (e·Å)
    curr_rad_factor = 1.60217733e-10 / (DT * FREQ)        # 径向：nA per (e/Δt)

    print("轨迹: %s" % args.dcd)
    print("  %d 原子/帧，%d 帧，每帧 %.1f ps" % (natom, nframe, FREQ * DT * 1e12))
    print("盒子: Lx=%.3f Ly=%.3f Lz=%.3f，管轴 (%.3f, %.3f)" % (Lx, Ly, Lz, ox, oy))
    print("离子: %d 个（POT %d，CLA %d）" % (len(ids), is_pot.sum(), is_cla.sum()))
    print("轴向分区: 管内 r<%.1f / 管壁 %.1f~%.1f / 管外 r≥%.1f Å"
          % (args.r1, args.r1, args.r2, args.r2))
    print("径向柱面: %s Å" % ", ".join("%.2f" % r for r in args.shells))

    shells = list(args.shells)
    nsh = len(shells)

    # ---- 逐帧扫描 ----
    t_list = []
    acc = {k: [] for k in ('pot', 'cla', 'tot', 'inside', 'wall', 'outside',
                           'pot_in', 'pot_out', 'cla_in', 'cla_out')}
    cnt = {k: [] for k in ('in', 'wall', 'out')}
    irad = [[] for _ in range(nsh)]
    nrad = [[] for _ in range(nsh)]
    prev_qin = None
    prev_z = None

    scan = min(nframe, args.max_frames) if args.max_frames else nframe
    fh = open(args.dcd, 'rb')
    for i in range(scan):
        base = i * frame_len
        fh.seek(base + xrel); x = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        fh.seek(base + yrel); y = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        fh.seek(base + zrel); z = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        r = fp.ion_radius(x, y, ox, oy, Lx, Ly)

        # ---- 径向：柱面内净电荷 ----
        qin = np.array([q[r < rs].sum() for rs in shells])
        nin = np.array([(r < rs).sum() for rs in shells])
        if prev_qin is not None:
            for j in range(nsh):
                irad[j].append(-(qin[j] - prev_qin[j]) * curr_rad_factor)
                nrad[j].append(nin[j])
        prev_qin = qin

        if prev_z is not None:
            dz = z - prev_z
            dz -= Lz * np.round(dz / Lz)          # 最小镜像修正
            per = q * dz * curr_factor            # 每个离子贡献 (nA)

            m_in = r < args.r1
            m_out = r >= args.r2
            m_wall = ~(m_in | m_out)

            t_list.append(i * FREQ * DT * 1e9)     # ns
            acc['pot'].append(per[is_pot].sum())
            acc['cla'].append(per[is_cla].sum())
            acc['tot'].append(per.sum())
            acc['inside'].append(per[m_in].sum())
            acc['wall'].append(per[m_wall].sum())
            acc['outside'].append(per[m_out].sum())
            acc['pot_in'].append(per[m_in & is_pot].sum())
            acc['pot_out'].append(per[m_out & is_pot].sum())
            acc['cla_in'].append(per[m_in & is_cla].sum())
            acc['cla_out'].append(per[m_out & is_cla].sum())
            cnt['in'].append(m_in.sum()); cnt['wall'].append(m_wall.sum()); cnt['out'].append(m_out.sum())
        prev_z = z
    fh.close()

    t = np.array(t_list)
    d = {k: np.array(v) for k, v in acc.items()}
    Ir = np.array(irad)          # (nsh, n)
    Nr = np.array(nrad)
    print("扫完 %d 帧（%.1f ns）" % (len(t), t[-1]))

    # ---- 电压（优先用 field_log 的实际波形）----
    log = fp.load_field_log(args.field_log)
    V_scan, vname, V_ax, V_rad = fp.scan_variable(
        t, log, args.period, args.vmax, axial_mode=args.axial_mode,
        axial_period=args.axial_period, axial_vmax=args.axial_vmax, verbose=True)
    print("扫描变量: %s（按它做电压分箱）" % vname)

    # ---- 数据文件 ----
    np.savetxt('current_components.dat',
               np.column_stack([t, d['pot'], d['cla'], d['tot'],
                                d['inside'], d['wall'], d['outside'],
                                d['pot_in'], d['pot_out'], d['cla_in'], d['cla_out']]),
               header=('t(ns)  I_POT  I_CLA  I_total  I_inside  I_wall  I_outside  '
                       'I_POT_in  I_POT_out  I_CLA_in  I_CLA_out   [nA, 轴向]'),
               fmt='%.4f ' + ' %.6f' * 10)
    np.savetxt('radial_components.dat',
               np.column_stack([t] + [Ir[j] for j in range(nsh)] + [Nr[j] for j in range(nsh)]),
               header=('t(ns)  ' + '  '.join('I_r(%.2f)' % s for s in shells)
                       + '  ' + '  '.join('N_in(%.2f)' % s for s in shells)),
               fmt='%.4f ' + ' %.6f' * nsh + ' %6.0f' * nsh)
    print("时间序列已写出: current_components.dat / radial_components.dat")

    # ---- 平均占据数 ----
    print()
    print("=== 平均离子占据数（时间平均）===")
    print("  管内(r<%.1f)     : %6.1f 个" % (args.r1, np.mean(cnt['in'])))
    print("  管壁(%.1f~%.1f)  : %6.1f 个" % (args.r1, args.r2, np.mean(cnt['wall'])))
    print("  管外(r≥%.1f)     : %6.1f 个" % (args.r2, np.mean(cnt['out'])))
    for j, rs in enumerate(shells):
        print("  柱面 r=%.2f Å 内  : %6.2f 个（%.0f ~ %.0f）"
              % (rs, Nr[j].mean(), Nr[j].min(), Nr[j].max()))

    # ---- 稳态平均值 ----
    sel = t >= args.skip_ns
    if sel.sum() < 10:
        sel = np.ones_like(t, dtype=bool)
    print()
    print("=== 稳态平均电流（跳过前 %.1f ns，取 %d 个采样点）===" % (args.skip_ns, sel.sum()))
    print("  轴向（V_axial = %.2f V 恒定）：" % args.vaxial)
    for k, lb in (('pot', 'K+'), ('cla', 'Cl-'), ('tot', '总'),
                  ('inside', '管内'), ('wall', '管壁'), ('outside', '管外')):
        v = d[k][sel]
        sem = v.std(ddof=1) / np.sqrt(len(v)) if len(v) > 1 else np.nan
        print("    %-6s %+8.3f ± %.3f nA" % (lb, v.mean(), sem))
    print("  径向（柱面穿越）：")
    for j, rs in enumerate(shells):
        v = Ir[j][sel]
        sem = v.std(ddof=1) / np.sqrt(len(v)) if len(v) > 1 else np.nan
        print("    r=%5.2f Å  %+9.3f ± %.3f nA（单帧量子 %.1f nA）"
              % (rs, v.mean(), sem, curr_rad_factor))

    # ================= 图 1：轴向电流时间序列 =================
    fig, axes = plt.subplots(3, 1, figsize=(13, 10), sharex=True)

    ax = axes[0]
    ax.plot(t, d['pot'], color='tab:red', lw=0.4, alpha=0.25)
    ax.plot(t, d['cla'], color='tab:blue', lw=0.4, alpha=0.25)
    ax.plot(t, smooth(d['pot'], args.smooth), color='tab:red', lw=1.8, label='阳离子 K$^+$')
    ax.plot(t, smooth(d['cla'], args.smooth), color='tab:blue', lw=1.8, label='阴离子 Cl$^-$')
    ax.plot(t, smooth(d['tot'], args.smooth), color='black', lw=2.0, label='总电流')
    ax.axhline(0, color='gray', ls='--', lw=0.6)
    ax.set_ylabel('轴向电流 (nA)')
    ax.set_title('轴向电流分解（按种类）：恒定 $V_{axial}$ = %.1f V，细线=原始，粗线=%d 帧平滑'
                 % (args.vaxial, args.smooth))
    ax.legend(loc='upper right', ncol=3, fontsize=9)
    ax.grid(alpha=0.3)

    ax = axes[1]
    ax.plot(t, d['inside'], color='tab:green', lw=0.4, alpha=0.25)
    ax.plot(t, d['outside'], color='tab:orange', lw=0.4, alpha=0.25)
    ax.plot(t, smooth(d['inside'], args.smooth), color='tab:green', lw=1.8,
            label='管内 (r < %.1f Å)' % args.r1)
    ax.plot(t, smooth(d['wall'], args.smooth), color='tab:purple', lw=1.8,
            label='管壁限域 (%.1f ≤ r < %.1f Å)' % (args.r1, args.r2))
    ax.plot(t, smooth(d['outside'], args.smooth), color='tab:orange', lw=1.8,
            label='管外 (r ≥ %.1f Å)' % args.r2)
    ax.axhline(0, color='gray', ls='--', lw=0.6)
    ax.set_ylabel('轴向电流 (nA)')
    ax.set_title('轴向电流分解（按径向位置）')
    ax.legend(loc='upper right', ncol=3, fontsize=9)
    ax.grid(alpha=0.3)

    ax = axes[2]
    ax.plot(t, V_scan, color='tab:red', lw=1.2, label='%s(t)（参考）' % _tex(vname))
    if np.ptp(V_ax) < 1e-6:
        ax.axhline(args.vaxial, color='black', ls='--', lw=1.2,
                   label='$V_{axial}$ = %.1f V（恒定）' % args.vaxial)
    ax.set_xlabel('时间 (ns)')
    ax.set_ylabel('电压 (V)')
    ax.set_title('施加的电压（扫描变量：%s）' % vname)
    ax.legend(loc='upper right', ncol=2, fontsize=9)
    ax.grid(alpha=0.3)

    fig.tight_layout(); fig.savefig('fig_currents_time.png', dpi=150)
    print("图已保存: fig_currents_time.png")

    # ================= 图 2：径向电流 =================
    colors = ['tab:green', 'tab:purple', 'tab:orange', 'tab:cyan', 'tab:brown']
    fig, axes = plt.subplots(3, 1, figsize=(13, 10), sharex=True)

    ax = axes[0]
    for j, rs in enumerate(shells):
        ax.plot(t, smooth(Ir[j], args.smooth), color=colors[j % len(colors)], lw=1.5,
                label='r = %.2f Å' % rs)
    ax.axhline(0, color='gray', ls='--', lw=0.6)
    ax.set_ylabel('径向电流 (nA)')
    ax.set_title('径向电流 $I_r = -\\Delta Q_{in}/\\Delta t$（%d 帧平滑；单帧量子 %.0f nA，'
                 '所以必须平滑/分箱才有意义）' % (args.smooth, curr_rad_factor))
    ax.legend(fontsize=9, ncol=3); ax.grid(alpha=0.3)

    ax = axes[1]
    for j, rs in enumerate(shells):
        ax.plot(t, Nr[j], color=colors[j % len(colors)], lw=0.8, alpha=0.7,
                label='N(r < %.2f Å)' % rs)
    ax.set_ylabel('柱面内离子数')
    ax.set_title('柱面内的离子数（径向"呼吸"）')
    ax.legend(fontsize=9, ncol=3); ax.grid(alpha=0.3)

    ax = axes[2]
    ax.plot(t, V_scan, color='tab:red', lw=1.2)
    ax.set_xlabel('时间 (ns)')
    ax.set_ylabel('%s (V)' % _tex(vname))
    ax.set_title('扫描电压（参考）')
    ax.grid(alpha=0.3)

    fig.tight_layout(); fig.savefig('fig_radial_time.png', dpi=150)
    print("图已保存: fig_radial_time.png")

    # ================= 图 3：平均贡献 =================
    fig, axes = plt.subplots(1, 3, figsize=(15, 4.8))

    ax = axes[0]
    vals = [d['pot'][sel].mean(), d['cla'][sel].mean(), d['tot'][sel].mean()]
    errs = [d['pot'][sel].std(ddof=1) / np.sqrt(sel.sum()),
            d['cla'][sel].std(ddof=1) / np.sqrt(sel.sum()),
            d['tot'][sel].std(ddof=1) / np.sqrt(sel.sum())]
    ax.bar(['K$^+$', 'Cl$^-$', '总'], vals, yerr=errs, capsize=4,
           color=['tab:red', 'tab:blue', 'black'])
    ax.axhline(0, color='gray', lw=0.6)
    ax.set_ylabel('平均轴向电流 (nA)')
    ax.set_title('轴向电流（按种类）')
    ax.grid(alpha=0.3, axis='y')

    ax = axes[1]
    vals = [d['inside'][sel].mean(), d['wall'][sel].mean(), d['outside'][sel].mean()]
    errs = [d['inside'][sel].std(ddof=1) / np.sqrt(sel.sum()),
            d['wall'][sel].std(ddof=1) / np.sqrt(sel.sum()),
            d['outside'][sel].std(ddof=1) / np.sqrt(sel.sum())]
    ax.bar(['管内', '管壁', '管外'], vals, yerr=errs, capsize=4,
           color=['tab:green', 'tab:purple', 'tab:orange'])
    ax.axhline(0, color='gray', lw=0.6)
    ax.set_ylabel('平均轴向电流 (nA)')
    ax.set_title('轴向电流（按径向位置）')
    ax.grid(alpha=0.3, axis='y')

    ax = axes[2]
    vals = [Ir[j][sel].mean() for j in range(nsh)]
    errs = [Ir[j][sel].std(ddof=1) / np.sqrt(sel.sum()) for j in range(nsh)]
    ax.bar(['%.1f' % rs for rs in shells], vals, yerr=errs, capsize=4,
           color=[colors[j % len(colors)] for j in range(nsh)])
    ax.axhline(0, color='gray', lw=0.6)
    ax.set_xlabel('柱面半径 (Å)')
    ax.set_ylabel('平均径向电流 (nA)')
    ax.set_title('径向净电流（交流驱动下应接近 0）')
    ax.grid(alpha=0.3, axis='y')

    fig.tight_layout(); fig.savefig('fig_current_fraction.png', dpi=150)
    print("图已保存: fig_current_fraction.png")


if __name__ == '__main__':
    main()
