#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自实现 WHAM：从伞形采样窗口算 PMF（仅依赖 numpy）。

用法：
    python wham.py metadata.txt -T 300 --bin 0.01 -o pmf.txt

metadata.txt 每行三列：数据文件  窗口中心(Å)  弹簧常数(kcal/mol/Å²)
数据文件两列：step  z(反应坐标) —— 取第 2 列。

说明：本脚本给出 PMF 点估计；若要严格误差棒，建议装 PyMBAR
      （conda install --override-channels -c conda-forge pymbar）。
"""
import argparse
import numpy as np

kB = 0.00198720425864083  # kcal/mol/K


def main():
    ap = argparse.ArgumentParser(description="WHAM 计算 PMF")
    ap.add_argument("metadata", help="metadata.txt")
    ap.add_argument("-T", type=float, default=300.0, help="温度 K")
    ap.add_argument("--bin", type=float, default=0.01, help="分箱宽度 Å")
    ap.add_argument("-o", "--out", default="pmf.txt")
    ap.add_argument("--tol", type=float, default=1e-7)
    ap.add_argument("--maxiter", type=int, default=100000)
    args = ap.parse_args()

    beta = 1.0 / (kB * args.T)

    # ---- 读 metadata ----
    metas = []
    with open(args.metadata) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            if len(p) < 3:
                continue
            metas.append((p[0], float(p[1]), float(p[2])))
    if not metas:
        raise SystemExit("metadata 为空")

    # ---- 读各窗口反应坐标（第 2 列）----
    series = []
    for fn, center, k in metas:
        try:
            d = np.loadtxt(fn)
        except Exception as e:
            print(f"警告：读 {fn} 失败（{e}），跳过")
            continue
        if d.ndim == 1:
            xi = d
        else:
            xi = d[:, 1]
        if xi.size < 2:
            print(f"警告：{fn} 数据太少，跳过")
            continue
        series.append((xi, center, k))
    if not series:
        raise SystemExit("没有可用数据")

    # ---- 分箱 ----
    lo = min(xi.min() for xi, _, _ in series)
    hi = max(xi.max() for xi, _, _ in series)
    edges = np.arange(lo, hi + args.bin, args.bin)
    centers = 0.5 * (edges[:-1] + edges[1:])
    nbins = len(centers)

    counts = np.zeros((len(series), nbins))
    for i, (xi, _, _) in enumerate(series):
        counts[i], _ = np.histogram(xi, bins=edges)

    n_i = np.array([len(xi) for xi, _, _ in series], dtype=float)

    # 偏置势 W[i,k] = 0.5 k_i (ξ_k - ξ_i0)^2
    W = np.zeros((len(series), nbins))
    for i, (_, center, k) in enumerate(series):
        W[i] = 0.5 * k * (centers - center) ** 2

    # ---- WHAM 迭代 ----
    F = np.zeros(len(series))
    for it in range(args.maxiter):
        denom = np.sum(n_i[:, None] * np.exp(beta * (F[:, None] - W)), axis=0)
        P = counts.sum(axis=0) / denom
        P /= P.sum()
        newF = -np.log(np.sum(P[None, :] * np.exp(-beta * W), axis=1)) / beta
        diff = np.max(np.abs(newF - F))
        F = newF
        if diff < args.tol:
            print(f"WHAM 收敛：迭代 {it + 1} 次，ΔF = {diff:.3e}")
            break
    else:
        print(f"警告：{args.maxiter} 次未收敛，ΔF = {diff:.3e}")

    # 只有被采样到的 bin（总计数>0）才有定义；空 bin 置 NaN
    total = counts.sum(axis=0)
    with np.errstate(divide="ignore", invalid="ignore"):
        pmf = np.where(total > 0, -np.log(P) / beta, np.nan)
    pmf -= np.nanmin(pmf)  # 以最低点为 0

    np.savetxt(args.out, np.column_stack([centers, pmf]),
               fmt="%.6f", header="z(A)  PMF(kcal/mol)")
    nvalid = int(np.isfinite(pmf).sum())
    print(f"PMF 写入 {args.out}：{nvalid}/{nbins} 个有效 bin，范围 {lo:.2f} ~ {hi:.2f} Å")


if __name__ == "__main__":
    main()
