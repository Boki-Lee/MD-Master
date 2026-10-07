#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
画 PMF 曲线（依赖 numpy + matplotlib，用 conda 环境 MD）。

用法：
    python plot_pmf.py pmf.txt -o pmf.png
"""
import argparse
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pmf", nargs="?", default="pmf.txt")
    ap.add_argument("-o", "--out", default="pmf.png")
    ap.add_argument("--title", default="PMF of K+ through CNT crown-ether pore")
    args = ap.parse_args()

    d = np.loadtxt(args.pmf)
    z, pmf = d[:, 0], d[:, 1]

    # 去掉 nan（窗口间采样空隙），并以体相 z≈+12 为参考零点
    valid = ~np.isnan(pmf)
    z, pmf = z[valid], pmf[valid]
    bulk_ref = pmf[np.argmin(np.abs(z - 12.0))]
    pmf = pmf - bulk_ref

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot(z, pmf, lw=2, color="tab:blue")
    ax.axvline(0.0, ls="--", lw=1, color="gray", label="pore center (z=0)")

    # 标注势垒峰
    ipk = int(np.argmax(pmf))
    ax.annotate(f"barrier {pmf[ipk]:.1f} kcal/mol",
                xy=(z[ipk], pmf[ipk]), xytext=(z[ipk] + 1.2, pmf[ipk] - 2.0),
                arrowprops=dict(arrowstyle="->", color="tab:red"),
                color="tab:red", fontsize=11)

    ax.set_xlabel("z (A)   [bulk outside > 0, tube interior < 0]")
    ax.set_ylabel("PMF (kcal/mol)")
    ax.set_title(args.title)
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(args.out, dpi=150)
    print(f"图片已保存：{args.out}")


if __name__ == "__main__":
    main()
