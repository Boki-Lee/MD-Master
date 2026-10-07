#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
plot_iv.py -- 新协议下的 "I-V" 关系（径向回线 + 轴向直流工作点）

★ 与旧版的区别（重要）
    旧协议：轴向三角波电压是**扫描变量**，所以画 I_z–V 曲线天经地义。
    新协议：轴向是**恒定 5 V 直流**，扫描变量变成了径向三角波。于是：
      ① 径向：I_r(rs) 对 V_rad(t) 作图 —— 三角波扫出来的**回线**，
              升压支/降压支分开画，两支的差别就是滞后；
      ② 轴向：恒定 5 V 下的**直流工作点**（稳态平均电流、涨落、电导）。
    再照旧版那样拿轴向三角波去分箱，会得到一条没有物理意义的曲线。

用法（在 analysis/ 目录下，需先 conda activate MD）：
    python plot_iv.py
    python plot_iv.py --skip-ns 8 --bin-width 0.5
    python plot_iv.py --input-radial AcurrRadial.dat --input-axial AcurrTotal.dat

前置条件：先跑完 calCurr.sh（得到 AcurrRadial.dat / AcurrTotal.dat）
电压优先取 4prod/field_log.dat 里**实际**施加的波形，读不到再按参数重建。

产物：
    iv_radial.dat    每个柱面的 V-I 回线数据（升/降支分开）
    axial_dc.txt     轴向直流工作点汇总
    iv_radial.png    回线图 + 轴向电流时间序列
"""

import argparse
import os
import sys

import numpy as np

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams['font.sans-serif'] = ['Noto Sans CJK SC', 'Droid Sans Fallback',
                                       'WenQuanYi Zen Hei', 'DejaVu Sans']
    plt.rcParams['axes.unicode_minus'] = False
    HAS_MPL = True
except ImportError:
    HAS_MPL = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import field_protocol as fp


def load_two_col(path):
    d = np.loadtxt(path)
    if d.ndim == 1:
        d = d.reshape(1, -1)
    return d[:, 0], d[:, 1]


def load_radial(path, shells_file):
    """读 AcurrRadial.dat：t + N 个 I_r + N 个 N_in。"""
    d = np.loadtxt(path)
    if d.ndim == 1:
        d = d.reshape(1, -1)
    t = d[:, 0]
    if os.path.exists(shells_file):
        shells = [float(x) for x in open(shells_file).read().split()]
    else:
        n = (d.shape[1] - 1) // 2
        shells = list(fp.SHELL_RADII[:n])
        print("[提示] 找不到 %s，按默认柱面 %s 解析" % (shells_file, shells))
    nsh = len(shells)
    if d.shape[1] < 1 + 2 * nsh:
        raise ValueError("AcurrRadial.dat 只有 %d 列，按 %d 个柱面至少需要 %d 列"
                         % (d.shape[1], nsh, 1 + 2 * nsh))
    Ir = d[:, 1:1 + nsh]
    Nin = d[:, 1 + nsh:1 + 2 * nsh]
    return t, shells, Ir, Nin


def branch_mask(V, t):
    """按电压的升降分两支（三角波的上升段/下降段）。"""
    dV = np.gradient(V, t)
    scale = np.median(np.abs(dV[dV != 0])) if np.any(dV != 0) else 1.0
    thr = 0.05 * scale
    return dV > thr, dV < -thr


def binned_loop(V, I, bins):
    """把 I 按 V 分箱，返回 (箱中心, 均值, 标准差, 点数)。"""
    c = 0.5 * (bins[:-1] + bins[1:])
    m = np.full(len(c), np.nan)
    s = np.full(len(c), np.nan)
    n = np.zeros(len(c), dtype=int)
    for i in range(len(c)):
        sel = (V >= bins[i]) & (V < bins[i + 1])
        n[i] = int(sel.sum())
        if n[i] > 0:
            m[i] = I[sel].mean()
            s[i] = I[sel].std()
    return c, m, s, n


def slope(V, I):
    """线性拟合斜率 dI/dV，返回 (斜率, 斜率的标准误)。样本太少返回 (nan, nan)。"""
    ok = np.isfinite(V) & np.isfinite(I)
    if ok.sum() < 3:
        return np.nan, np.nan
    x, y = V[ok], I[ok]
    if np.ptp(x) < 1e-9:
        return np.nan, np.nan
    p, cov = np.polyfit(x, y, 1, cov=True)
    return float(p[0]), float(np.sqrt(cov[0, 0]))


def main():
    ap = argparse.ArgumentParser(description="新协议 I-V：径向回线 + 轴向直流工作点")
    ap.add_argument('--input-radial', default='AcurrRadial.dat')
    ap.add_argument('--input-axial', default='AcurrTotal.dat')
    ap.add_argument('--shells-file', default='radial_shells.txt')
    ap.add_argument('--field-log', default=fp.FIELD_LOG)
    ap.add_argument('--period', type=float, default=fp.PERIOD_RAD, help='径向三角波周期 (ns)，仅在没读到 field_log 时用')
    ap.add_argument('--vmax', type=float, default=fp.VMAX_RAD, help='径向三角波峰值 (V)，同上')
    ap.add_argument('--vaxial', type=float, default=fp.V_AXIAL, help='轴向恒定电压 (V)')
    ap.add_argument('--axial-mode', choices=('const', 'tri'), default=fp.AXIAL_MODE,
                    help="轴向波形：const=恒定直流（本项目）; tri=三角波（旧协议，扫描变量）")
    ap.add_argument('--axial-period', type=float, default=fp.AXIAL_PERIOD,
                    help='轴向三角波周期 (ns)，仅 --axial-mode tri 时用')
    ap.add_argument('--axial-vmax', type=float, default=fp.AXIAL_VMAX,
                    help='轴向三角波峰值 (V)，仅 --axial-mode tri 时用')
    ap.add_argument('--bin-width', type=float, default=0.5, help='电压分箱宽度 (V)')
    ap.add_argument('--skip-ns', type=float, default=0.0, help='轴向直流统计跳过前多少 ns 的瞬态')
    args = ap.parse_args()

    if not os.path.exists(args.input_radial):
        print("错误：找不到 %s，请先运行 calCurr.sh（新版会把径向电流写进这个文件）"
              % args.input_radial)
        sys.exit(1)

    t, shells, Ir, Nin = load_radial(args.input_radial, args.shells_file)
    log = fp.load_field_log(args.field_log)
    V_ax, V_rad, from_log = fp.voltage_series(
        t, log, period=args.period, vmax=args.vmax, verbose=True)
    # 轴向是"恒定直流"还是"三角波扫描变量"？决定要不要出经典 I-V 曲线
    axial_scanned = float(np.ptp(V_ax)) > 1.0e-6
    if not axial_scanned and args.axial_mode == 'tri':
        V_ax = fp.axial_voltage(t, 'tri', args.vaxial, args.axial_period, args.axial_vmax)
        axial_scanned = True
        print("轴向：按三角波处理（周期 %.2f ns、峰值 %.1f V）—— 出经典 I-V 曲线"
              % (args.axial_period, args.axial_vmax))
    elif axial_scanned:
        print("轴向：检测到电压在变（%.2f ~ %.2f V）—— 出经典 I-V 曲线"
              % (V_ax.min(), V_ax.max()))
    else:
        print("轴向：恒定 %.2f V —— 出直流工作点" % V_ax.mean())

    print("读入 %d 个采样点，时间 %.3f ~ %.3f ns（每点 %.1f ps）"
          % (len(t), t[0], t[-1], (t[1] - t[0]) * 1000))
    print("电压来源：%s" % ("4prod/field_log.dat（实际施加的波形）" if from_log else "按参数重建"))
    print("径向三角波：参数峰值 %.1f V、周期 %.2f ns（本段数据实际扫到 |V_rad| ≤ %.2f V）"
          % (args.vmax, args.period, np.abs(V_rad).max()))
    print("径向统计柱面：%s Å" % ", ".join("%.2f" % r for r in shells))
    print()
    quantum = 1.60217733e-10 / (fp.DT * fp.FREQ)
    print("注意：径向电流用 I_r = −ΔQ_in/Δt 统计，最小量子 = 1 个电荷 / 采样间隔")
    print("      = %.2f nA（%.0f ps 采样），所以单帧曲线是尖峰状的；"
          % (quantum, fp.FREQ * fp.DT * 1e12))
    print("      下面的回线是把成千上万个采样点按电压分箱平均出来的。")
    if (t[-1] - t[0]) < args.period:
        print("[警告] 数据只有 %.2f ns，不足一个径向周期（%.2f ns），回线画不完整"
              % (t[-1] - t[0], args.period))
    print()

    # ================= 轴向（扫描时才出 I-V）=================
    axial_iv = None
    if axial_scanned and os.path.exists(args.input_axial):
        ta, Ia = load_two_col(args.input_axial)
        Va = np.interp(ta, t, V_ax)          # 用与电流同一套时间轴上的电压
        bins_a = np.arange(Va.min() - args.bin_width,
                           Va.max() + args.bin_width + 1e-9, args.bin_width)
        ca, ma, sa, na = binned_loop(Va, Ia, bins_a)
        g_a, e_a = slope(ca, ma)
        print()
        print("=== 轴向 I-V 曲线（三角波扫描）===")
        print("  电位窗 %.2f ~ %.2f V，共 %d 个箱；拟合电导 %+.4f ± %.4f nA/V"
              % (ca[0], ca[-1], len(ca), g_a, e_a))
        np.savetxt('iv_axial.dat', np.column_stack([ca, ma, sa, na]),
                   header='V_axial(V)  I_total(nA)  std(nA)  n',
                   fmt='%.4f  %.6f  %.6f  %d')
        print("  轴向 I-V 数据已写出: iv_axial.dat")
        axial_iv = (ca, ma, sa)

    # ================= 径向回线 =================
    bins = np.arange(-np.abs(V_rad).max() - args.bin_width,
                     np.abs(V_rad).max() + args.bin_width + 1e-9, args.bin_width)
    rise, fall = branch_mask(V_rad, t)

    out = [bins[:-1] + args.bin_width / 2]
    header = ['V_rad(V)']
    loops = {}
    print("=== 径向 I_r–V_rad 回线 ===")
    for j, rs in enumerate(shells):
        I = Ir[:, j]
        c_r, m_r, s_r, n_r = binned_loop(V_rad[rise], I[rise], bins)
        c_f, m_f, s_f, n_f = binned_loop(V_rad[fall], I[fall], bins)
        loops[rs] = (c_r, m_r, s_r, c_f, m_f, s_f)
        out += [m_r, s_r, m_f, s_f]
        header += ['I_r%.2f_rise' % rs, 'std_rise', 'I_r%.2f_fall' % rs, 'std_fall']
        # 拟合电导（带标准误，这样一眼能看出是真信号还是噪声）
        g_all, e_all = slope(V_rad, I)
        g_rise, e_rise = slope(c_r, m_r)
        g_fall, e_fall = slope(c_f, m_f)
        area = float(np.trapezoid(I, V_rad))     # ∮I dV，回线的有向面积
        print("  r = %5.2f Å : 占据数 %.1f 个 | 电导(整圈) %+8.3f ± %.3f nA/V"
              % (rs, Nin[:, j].mean(), g_all, e_all))
        print("              升压支 %+8.3f ± %.3f，降压支 %+8.3f ± %.3f nA/V"
              % (g_rise, e_rise, g_fall, e_fall))
        print("              回线面积 ∮I_r dV_rad = %+.1f nA·V" % area)
        print("              单帧 |I_r| 最大 %.1f nA，非零采样占 %.1f%%"
              % (np.abs(I).max(), 100.0 * np.mean(np.abs(I) > 1e-9)))

    np.savetxt('iv_radial.dat', np.column_stack(out),
               header='  '.join(header), fmt='%.4f ' + ' %.6f' * (len(header) - 1))
    print("\n回线数据已写出: iv_radial.dat")

    # ================= 轴向直流工作点 =================
    lines = []
    def P(s):
        print(s)
        lines.append(s)

    P("")
    P("=" * 68)
    if axial_scanned:
        P("轴向：三角波扫描，工作点概念不适用（见上面的 I-V 曲线）")
    else:
        P("轴向直流工作点（V_axial = %.2f V，恒定）" % args.vaxial)
    P("=" * 68)
    if os.path.exists(args.input_axial) and not axial_scanned:
        ta, Ia = load_two_col(args.input_axial)
        sel = ta >= args.skip_ns
        if sel.sum() < 10:
            sel = np.ones_like(ta, dtype=bool)
        Ia_s = Ia[sel]
        mean_I = Ia_s.mean()
        sem = Ia_s.std(ddof=1) / np.sqrt(len(Ia_s)) if len(Ia_s) > 1 else np.nan
        P("  统计区间        : %.3f ~ %.3f ns（%d 个采样点）"
          % (ta[sel][0], ta[sel][-1], len(Ia_s)))
        P("  平均轴向电流    : %+.4f nA  (标准差 %.3f，均值标准误 %.4f)"
          % (mean_I, Ia_s.std(ddof=1), sem))
        P("  轴向电导 G_z    : %+.4f nS   (= I / %.2f V)" % (mean_I / args.vaxial, args.vaxial))
        P("  等效电阻        : %s" % ("%.2f GΩ" % (1e3 / (mean_I / args.vaxial))
                                      if abs(mean_I) > 1e-9 else "∞（电流太小）"))
        P("  电流范围        : %+.3f ~ %+.3f nA" % (Ia_s.min(), Ia_s.max()))
    elif not axial_scanned:
        P("  [跳过] 找不到 %s（只跑了径向那部分？）" % args.input_axial)

    for j, rs in enumerate(shells):
        P("  柱面 r=%.2f Å 平均占据 %.2f 个离子（%.2f ~ %.2f）"
          % (rs, Nin[:, j].mean(), Nin[:, j].min(), Nin[:, j].max()))
    with open('axial_dc.txt', 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print("\n轴向汇总已写出: axial_dc.txt")

    # ================= 出图 =================
    if not HAS_MPL:
        print("提示：没有 matplotlib，跳过画图。")
        return

    if axial_iv is not None:
        fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))
        ca, ma, sa = axial_iv
        axes[0].errorbar(ca, ma, yerr=sa, fmt='o-', ms=4, capsize=3,
                         color='steelblue', lw=1.6)
        axes[0].axhline(0, color='gray', ls='--', lw=0.6)
        axes[0].axvline(0, color='gray', ls='--', lw=0.6)
        axes[0].set_xlabel('轴向电压 $V_{axial}$ (V)')
        axes[0].set_ylabel('轴向电流 $I_z$ (nA)')
        axes[0].set_title('轴向 I-V 曲线（三角波扫描）')
        axes[0].grid(alpha=0.3)
        ax = axes[1]
    else:
        fig = plt.figure(figsize=(14, 9))
        gs = fig.add_gridspec(2, 2, height_ratios=[1.15, 1], hspace=0.32, wspace=0.22)
        ax = fig.add_subplot(gs[0, :])
    colors = ['tab:green', 'tab:purple', 'tab:orange', 'tab:cyan', 'tab:brown']
    for j, rs in enumerate(shells):
        c_r, m_r, s_r, c_f, m_f, s_f = loops[rs]
        col = colors[j % len(colors)]
        ax.errorbar(c_r, m_r, yerr=s_r, fmt='o-', ms=3.5, lw=1.6, capsize=2,
                    color=col, label='r = %.2f Å  升压支' % rs)
        ax.errorbar(c_f, m_f, yerr=s_f, fmt='s--', ms=3.5, lw=1.6, capsize=2,
                    color=col, alpha=0.6, label='r = %.2f Å  降压支' % rs)
    ax.axhline(0, color='gray', ls='--', lw=0.6)
    ax.axvline(0, color='gray', ls='--', lw=0.6)
    ax.set_xlabel('径向电压 $V_{rad}$ (V)')
    ax.set_ylabel('径向电流 $I_r$ (nA)')
    ax.set_title('径向 I–V 回线（柱面穿越计数，按电压分箱平均；实线=升压支，虚线=降压支）')
    ax.legend(fontsize=8, ncol=2)
    ax.grid(alpha=0.3)

    # 左下 / 右下：只有"轴向恒定"时才画时间序列
    #（轴向是扫描变量时，上面 1×2 的右图已经是径向回线了）
    if axial_iv is None:
        ax = fig.add_subplot(gs[1, 0])
        if os.path.exists(args.input_axial):
            ta, Ia = load_two_col(args.input_axial)
            w = max(1, len(ta) // 200)
            sm = np.convolve(Ia, np.ones(w) / w, mode='same')
            ax.plot(ta, Ia, color='tab:blue', lw=0.4, alpha=0.3)
            ax.plot(ta, sm, color='tab:blue', lw=1.8,
                    label='$I_z$（%d 点平滑）' % w)
            ax.axhline(mean_I, color='black', ls='--', lw=1.2,
                       label='稳态平均 %+.3f nA' % mean_I)
            ax.legend(fontsize=9)
        ax.axhline(0, color='gray', lw=0.6)
        ax.set_xlabel('时间 (ns)')
        ax.set_ylabel('轴向电流 $I_z$ (nA)')
        ax.set_title('轴向直流电流（$V_{axial}$ = %.1f V 恒定）' % args.vaxial)
        ax.grid(alpha=0.3)

        ax = fig.add_subplot(gs[1, 1])
        ax2 = ax.twinx()
        mid = shells.index(fp.TUBE_R) if fp.TUBE_R in shells else len(shells) // 2
        w = max(5, min(len(t) // 500, 50))
        Ism = np.convolve(Ir[:, mid], np.ones(w) / w, mode='same')
        ax.plot(t, Ir[:, mid], color='tab:purple', lw=0.4, alpha=0.25)
        ax.plot(t, Ism, color='tab:purple', lw=1.6,
                label='$I_r$(r=%.2f Å) 平滑' % shells[mid])
        ax.axhline(0, color='gray', lw=0.6)
        ax2.plot(t, V_rad, color='tab:red', lw=1.2, alpha=0.8, label='$V_{rad}(t)$')
        ax.set_xlabel('时间 (ns)')
        ax.set_ylabel('径向电流 (nA)', color='tab:purple')
        ax2.set_ylabel('$V_{rad}$ (V)', color='tab:red')
        ax.set_title('径向电流时间序列（r = %.2f Å 柱面）' % shells[mid])
        ax.grid(alpha=0.3)

    # 轴向是扫描变量时沿用旧脚本的图名，方便老用户找
    outfig = 'iv_curve.png' if axial_iv is not None else 'iv_radial.png'
    fig.savefig(outfig, dpi=150, bbox_inches='tight')
    print("图已保存: %s" % outfig)


if __name__ == '__main__':
    main()
