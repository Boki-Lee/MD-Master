#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
plot_concentration.py -- 管内 / 管壁 / 管外的离子浓度（新协议）

浓度定义：c [mol/L] = 1660.5 × n / V[Å³]   （1 Å³ = 1e-27 L）

区域划分（按离子到管轴的径向距离 r，沿整个盒子高度统计）：

    管内   r <  r_in      圆柱体积 π·r_in²·L
    管壁   r_in ≤ r < r_out   圆环体积 π(r_out²−r_in²)·L
    管外   r ≥ r_out      盒子体积 − π·r_out²·L

★ 默认分区改成 r_in = 9 Å、r_out = 22 Å，这是本项目自己的实测结论
  （WORKFLOW 第 5 节）：管壁两侧各有约 5 Å 的离子排斥层，
  拿 r<13 Å 当"管内"会算出假的"贫化 20%"，必须用柱心对远处本体比。

★ 新协议要点：径向三角波会把离子在径向上重新排布，所以除了时间平均的 c(r)，
  这里还把帧按 V_rad 分箱，给出**不同径向电压下的 c(r) 曲线族**——
  这是新协议下最该看的一张图。

用法（在 analysis/ 目录下，需先 conda activate MD）：
    python plot_concentration.py
    python plot_concentration.py --r-in 9 --r-out 22 --max-frames 2000

产物：
    concentration_summary.txt        汇总表（各区域浓度、选择性、电荷平衡）
    concentration_timeseries.dat     各区域个数与浓度随时间
    concentration_radial.dat         径向浓度分布（时间平均）
    concentration_radial_byV.dat     径向浓度分布（按 V_rad 分箱）
    concentration_z.dat              管内轴向浓度分布
    fig_conc_time.png / fig_conc_radial.png / fig_conc_z.png / fig_conc_voltage.png
"""

import argparse
import os
import sys

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

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

CONV = 1660.5          # n / V[Å³] -> mol/L


def main():
    ap = argparse.ArgumentParser(description='管内/管外离子浓度分析（新协议）')
    ap.add_argument('--dcd', default=DCD)
    ap.add_argument('--ionfile', default=IONFILE)
    ap.add_argument('--xsc', default=XSC)
    ap.add_argument('--field-log', default=fp.FIELD_LOG)
    ap.add_argument('--r-in', type=float, default=9.0, help='管内半径 (Å)')
    ap.add_argument('--r-out', type=float, default=22.0, help='管外起始半径 (Å)')
    ap.add_argument('--axial-mode', choices=('const', 'tri'), default=fp.AXIAL_MODE,
                    help="轴向波形：const=恒定直流; tri=三角波（经典 I-V 扫描）")
    ap.add_argument('--axial-period', type=float, default=fp.AXIAL_PERIOD)
    ap.add_argument('--axial-vmax', type=float, default=fp.AXIAL_VMAX)
    ap.add_argument('--period', type=float, default=fp.PERIOD_RAD)
    ap.add_argument('--vmax', type=float, default=fp.VMAX_RAD)
    ap.add_argument('--max-frames', type=int, default=0, help='只扫前多少帧（0=全部）')
    args = ap.parse_args()

    natom, frame_len, nframe, xrel, yrel, zrel = fp.probe_dcd(args.dcd)
    Lx, Ly, Lz, ox, oy = fp.read_xsc(args.xsc)
    V_box = Lx * Ly * Lz
    V_in = np.pi * args.r_in ** 2 * Lz
    V_out = V_box - np.pi * args.r_out ** 2 * Lz
    V_wall = V_box - V_in - V_out

    print("盒子: %.3f x %.3f x %.3f = %.0f Å³，管轴 (%.3f, %.3f)"
          % (Lx, Ly, Lz, V_box, ox, oy))
    print("区域体积: 管内 %.0f Å³   管壁 %.0f Å³   管外 %.0f Å³" % (V_in, V_wall, V_out))
    print("  按 0.6 M 估算，管内应约 %.1f 个离子，管外应约 %.1f 个"
          % (0.6 * V_in / CONV, 0.6 * V_out / CONV))

    ids, q, names = fp.read_ions(args.ionfile)
    is_k = (names == 'POT')
    is_cl = (names == 'CLA')
    print("离子: K+ %d 个，Cl- %d 个" % (is_k.sum(), is_cl.sum()))

    scan = min(nframe, args.max_frames) if args.max_frames else nframe

    # 电压：先算好整条时间轴，方便逐帧分箱
    t_all = fp.frame_times(scan)
    log = fp.load_field_log(args.field_log)
    V_scan, vname, V_ax, V_rad = fp.scan_variable(
        t_all, log, args.period, args.vmax, axial_mode=args.axial_mode,
        axial_period=args.axial_period, axial_vmax=args.axial_vmax, verbose=True)
    print("扫描变量: %s（按它做电压分箱）" % vname)

    # 径向分布：整体 + 按 V_rad 分箱
    rbins = np.arange(0, 26.0, 0.5)
    rk = np.zeros(len(rbins) - 1)
    rcl = np.zeros(len(rbins) - 1)
    vbin = np.arange(-args.vmax, args.vmax + 1e-9, args.vmax / 2.5)   # 5 段
    vcen = 0.5 * (vbin[:-1] + vbin[1:])
    nvb = len(vcen)
    rk_v = np.zeros((nvb, len(rbins) - 1))
    rcl_v = np.zeros((nvb, len(rbins) - 1))
    nv = np.zeros(nvb, dtype=int)

    zbins = np.arange(-4, 84.5, 2.0)
    zk = np.zeros(len(zbins) - 1)
    zcl = np.zeros(len(zbins) - 1)

    t_list = []
    nk_in, ncl_in, nk_out, ncl_out, nk_wall, ncl_wall = [], [], [], [], [], []

    fh = open(args.dcd, 'rb')
    for i in range(scan):
        base = i * frame_len
        fh.seek(base + xrel); x = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        fh.seek(base + yrel); y = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        fh.seek(base + zrel); z = np.frombuffer(fh.read(4 * natom), dtype='<f4')[ids]
        r = fp.ion_radius(x, y, ox, oy, Lx, Ly)

        m_in = r < args.r_in
        m_out = r >= args.r_out
        m_wall = ~(m_in | m_out)

        t_list.append(i * FREQ * DT * 1e9)
        nk_in.append((m_in & is_k).sum());    ncl_in.append((m_in & is_cl).sum())
        nk_wall.append((m_wall & is_k).sum()); ncl_wall.append((m_wall & is_cl).sum())
        nk_out.append((m_out & is_k).sum());  ncl_out.append((m_out & is_cl).sum())

        # 径向分布（只用盒子内切圆范围，保证圆环完整落在盒内）
        rk += np.histogram(r[is_k], bins=rbins)[0]
        rcl += np.histogram(r[is_cl], bins=rbins)[0]
        # 管内轴向分布
        zk += np.histogram(z[is_k & m_in], bins=zbins)[0]
        zcl += np.histogram(z[is_cl & m_in], bins=zbins)[0]

        # 按此刻的径向电压分箱
        j = np.searchsorted(vbin, V_scan[i], side='right') - 1
        if 0 <= j < nvb:
            nv[j] += 1
            rk_v[j] += np.histogram(r[is_k], bins=rbins)[0]
            rcl_v[j] += np.histogram(r[is_cl], bins=rbins)[0]
    fh.close()

    t = np.array(t_list)
    print("扫完 %d 帧（%.1f ns）" % (len(t), t[-1]))

    series = dict(nk_in=np.array(nk_in), ncl_in=np.array(ncl_in),
                  nk_wall=np.array(nk_wall), ncl_wall=np.array(ncl_wall),
                  nk_out=np.array(nk_out), ncl_out=np.array(ncl_out))
    for key, vol in (('_in', V_in), ('_wall', V_wall), ('_out', V_out)):
        series['ck' + key] = series['nk' + key] * CONV / vol
        series['ccl' + key] = series['ncl' + key] * CONV / vol

    # ---- 汇总 ----
    lines = []
    def P(s):
        print(s)
        lines.append(s)

    P("")
    P("=" * 68)
    P("离子浓度汇总（0 ~ %.1f ns 平均）" % t[-1])
    P("=" * 68)
    P("%-8s %10s %12s %12s %12s" % ("区域", "体积(Å³)", "c(K+) M", "c(Cl-) M", "c(总) M"))
    for label, key, vol in (("管内", "_in", V_in), ("管壁", "_wall", V_wall), ("管外", "_out", V_out)):
        ck, ccl = series['ck' + key], series['ccl' + key]
        P("%-8s %10.0f %7.3f±%-4.3f %7.3f±%-4.3f %7.3f"
          % (label, vol, ck.mean(), ck.std(), ccl.mean(), ccl.std(), (ck + ccl).mean()))
    P("")
    P("--- 管内 vs 管外 ---")
    P("  K+  管内/管外 = %.3f" % (series['ck_in'].mean() / series['ck_out'].mean()))
    P("  Cl- 管内/管外 = %.3f" % (series['ccl_in'].mean() / series['ccl_out'].mean()))
    P("  （默认分区 r_in=%.1f / r_out=%.1f Å 就是本项目推荐的「柱心 vs 远处本体」）"
      % (args.r_in, args.r_out))
    P("")
    P("--- 管内电荷平衡 ---")
    P("  管内平均: K+ %.2f 个，Cl- %.2f 个，净电荷 %+.3f e"
      % (series['nk_in'].mean(), series['ncl_in'].mean(),
         series['nk_in'].mean() - series['ncl_in'].mean()))
    P("")
    P("--- 径向电压对管内离子数的影响 ---")
    for j in range(nvb):
        if nv[j] == 0:
            continue
        sel = (V_scan >= vbin[j]) & (V_scan < vbin[j + 1])
        P("  V_rad ∈ [%+5.1f, %+5.1f) V : %5d 帧，管内 K+ %.2f 个，Cl- %.2f 个"
          % (vbin[j], vbin[j + 1], nv[j],
             series['nk_in'][sel].mean(), series['ncl_in'][sel].mean()))
    with open('concentration_summary.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')

    # ---- 数据文件 ----
    np.savetxt('concentration_timeseries.dat',
               np.column_stack([t, series['nk_in'], series['ncl_in'],
                                series['ck_in'], series['ccl_in'],
                                series['nk_out'], series['ncl_out'],
                                series['ck_out'], series['ccl_out']]),
               header=('t(ns)  nK_in nCl_in cK_in(M) cCl_in(M)  '
                       'nK_out nCl_out cK_out(M) cCl_out(M)'),
               fmt='%.4f ' + ' %.4f' * 8)

    rc = 0.5 * (rbins[:-1] + rbins[1:])
    dv = np.pi * (rbins[1:] ** 2 - rbins[:-1] ** 2) * Lz
    np.savetxt('concentration_radial.dat',
               np.column_stack([rc, rk / scan * CONV / dv, rcl / scan * CONV / dv,
                                dv, rk, rcl]),
               header='r(A)  cK(M)  cCl(M)  dV(A^3)  sumK  sumCl',
               fmt='%.3f  %.5f  %.5f  %.1f  %.0f  %.0f')

    byv = [rc]
    hdr = ['r(A)']
    for j in range(nvb):
        c = np.where(nv[j] > 0, 1.0 / max(nv[j], 1), 0.0)
        byv += [rk_v[j] * c * CONV / dv, rcl_v[j] * c * CONV / dv]
        hdr += ['cK_V%+.1f' % vcen[j], 'cCl_V%+.1f' % vcen[j]]
    np.savetxt('concentration_radial_byV.dat', np.column_stack(byv),
               header='  '.join(hdr), fmt='%.3f ' + ' %.5f' * (len(hdr) - 1))

    zc = 0.5 * (zbins[:-1] + zbins[1:])
    dvz = np.pi * args.r_in ** 2 * (zbins[1] - zbins[0])
    np.savetxt('concentration_z.dat',
               np.column_stack([zc, zk / scan * CONV / dvz, zcl / scan * CONV / dvz]),
               header='z(A)  cK(M)  cCl(M)', fmt='%.2f  %.5f  %.5f')
    print("分布数据已写出: concentration_radial.dat / concentration_radial_byV.dat / concentration_z.dat")

    # ---- 图 1：浓度随时间 ----
    fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
    w = max(1, min(100, len(t) // 10))
    sm = lambda y: np.convolve(y, np.ones(w) / w, mode='same')
    for ax, key, lab, rr in ((axes[0], '_in', '管内', args.r_in),
                             (axes[1], '_out', '管外', args.r_out)):
        ax.plot(t, series['ck' + key], color='tab:red', lw=0.4, alpha=0.25)
        ax.plot(t, series['ccl' + key], color='tab:blue', lw=0.4, alpha=0.25)
        ax.plot(t, sm(series['ck' + key]), color='tab:red', lw=2, label='K$^+$')
        ax.plot(t, sm(series['ccl' + key]), color='tab:blue', lw=2, label='Cl$^-$')
        ax.axhline(0.6, color='gray', ls='--', lw=0.8, label='初始 0.6 M')
        ax.set_ylabel('浓度 (mol/L)')
        ax.legend(ncol=3, fontsize=9); ax.grid(alpha=0.3)
        ax2 = ax.twinx()
        ax2.plot(t, V_scan, color='tab:red', lw=0.8, alpha=0.35)
        ax2.set_ylabel('%s (V)' % _tex(vname), color='tab:red', alpha=0.6)
    axes[0].set_title('%s离子浓度随时间（r < %.1f Å）' % (lab, rr))
    axes[1].set_title('%s离子浓度随时间（r ≥ %.1f Å）' % (lab, rr))
    axes[1].set_xlabel('时间 (ns)')
    fig.tight_layout(); fig.savefig('fig_conc_time.png', dpi=150)
    print("图已保存: fig_conc_time.png")

    # ---- 图 2：径向浓度分布（平均 + 按电压分箱）----
    fig, axes = plt.subplots(1, 2, figsize=(15, 5.5))
    ax = axes[0]
    ax.step(rc, rk / scan * CONV / dv, where='mid', color='tab:red', lw=2, label='K$^+$')
    ax.step(rc, rcl / scan * CONV / dv, where='mid', color='tab:blue', lw=2, label='Cl$^-$')
    ax.axhline(0.6, color='gray', ls='--', lw=0.8, label='初始 0.6 M')
    ax.axvline(fp.TUBE_R, color='k', ls=':', lw=1.2)
    ax.text(fp.TUBE_R + 0.3, ax.get_ylim()[1] * 0.9, '管壁 %.2f Å' % fp.TUBE_R, fontsize=9)
    ax.axvspan(0, args.r_in, color='tab:green', alpha=0.10)
    ax.axvspan(args.r_out, rbins[-1], color='tab:orange', alpha=0.10)
    ax.set_xlabel('到管轴的径向距离 r (Å)'); ax.set_ylabel('浓度 (mol/L)')
    ax.set_title('径向离子浓度分布（时间平均）')
    ax.legend(fontsize=9); ax.grid(alpha=0.3)

    ax = axes[1]
    cmap = plt.get_cmap('coolwarm')
    for j in range(nvb):
        if nv[j] == 0:
            continue
        c = cmap((vcen[j] + args.vmax) / (2 * args.vmax))
        ax.step(rc, rk_v[j] / nv[j] * CONV / dv, where='mid', color=c, lw=1.8,
                label='$V_{rad}$ ≈ %+.1f V（%d 帧）' % (vcen[j], nv[j]))
    ax.axhline(0.6, color='gray', ls='--', lw=0.8)
    ax.axvline(fp.TUBE_R, color='k', ls=':', lw=1.2)
    ax.set_xlabel('到管轴的径向距离 r (Å)'); ax.set_ylabel('c(K$^+$) (mol/L)')
    ax.set_title('K$^+$ 径向分布随径向电压的变化\n（径向场把离子往外推/往里拉，就看这张）')
    ax.legend(fontsize=8); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig('fig_conc_radial.png', dpi=150)
    print("图已保存: fig_conc_radial.png")

    # ---- 图 3：管内轴向分布 ----
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.step(zc, zk / scan * CONV / dvz, where='mid', color='tab:red', lw=2, label='K$^+$')
    ax.step(zc, zcl / scan * CONV / dvz, where='mid', color='tab:blue', lw=2, label='Cl$^-$')
    ax.axhline(0.6, color='gray', ls='--', lw=0.8, label='初始 0.6 M')
    ax.axvline(0, color='k', ls=':', lw=1)
    ax.axvline(79.82, color='k', ls=':', lw=1)
    ax.set_xlabel('z (Å)'); ax.set_ylabel('浓度 (mol/L)')
    ax.set_title('管内轴向离子浓度分布（r < %.1f Å）' % args.r_in)
    ax.legend(fontsize=9); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig('fig_conc_z.png', dpi=150)
    print("图已保存: fig_conc_z.png")

    # ---- 图 4：管内浓度随径向电压 ----
    ck_v, ccl_v, ntot_v, ck_e, ccl_e, nt_e = [], [], [], [], [], []
    for j in range(nvb):
        sel = (V_scan >= vbin[j]) & (V_scan < vbin[j + 1])
        if sel.sum() == 0:
            ck_v.append(np.nan); ccl_v.append(np.nan); ntot_v.append(np.nan)
            ck_e.append(np.nan); ccl_e.append(np.nan); nt_e.append(np.nan)
            continue
        ck_v.append(series['ck_in'][sel].mean()); ccl_v.append(series['ccl_in'][sel].mean())
        ntot_v.append((series['nk_in'][sel] + series['ncl_in'][sel]).mean())
        ck_e.append(series['ck_in'][sel].std(ddof=1) / np.sqrt(sel.sum()))
        ccl_e.append(series['ccl_in'][sel].std(ddof=1) / np.sqrt(sel.sum()))
        nt_e.append((series['nk_in'][sel] + series['ncl_in'][sel]).std(ddof=1) / np.sqrt(sel.sum()))

    fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))
    ax = axes[0]
    ax.errorbar(vcen, ck_v, yerr=ck_e, fmt='o-', color='tab:red', lw=1.8, ms=5, capsize=3, label='K$^+$')
    ax.errorbar(vcen, ccl_v, yerr=ccl_e, fmt='s-', color='tab:blue', lw=1.8, ms=5, capsize=3, label='Cl$^-$')
    ax.axhline(0.6, color='gray', ls='--', lw=0.8)
    ax.set_xlabel('径向电压 $V_{rad}$ (V)'); ax.set_ylabel('管内浓度 (mol/L)')
    ax.set_title('管内浓度随径向电压变化（r < %.1f Å）' % args.r_in)
    ax.legend(fontsize=9); ax.grid(alpha=0.3)

    ax = axes[1]
    ax.errorbar(vcen, ntot_v, yerr=nt_e, fmt='o-', color='tab:green', lw=1.8, ms=5, capsize=3)
    ax.set_xlabel('径向电压 $V_{rad}$ (V)'); ax.set_ylabel('管内离子总数')
    ax.set_title('管内离子总数随径向电压变化')
    ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig('fig_conc_voltage.png', dpi=150)
    print("图已保存: fig_conc_voltage.png")


if __name__ == '__main__':
    main()
