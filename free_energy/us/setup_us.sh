#!/bin/bash
# ============================================================
#  批量生成 US 窗口的 .colvars 和 .conf
#  输入：windows.txt（中心+弹簧常数）、template.conf、../1model 里的原子序号
# ============================================================
set -e
cd "$(dirname "$0")"

if [ ! -f ../1model/ion_index.dat ] || [ ! -f ../1model/ox_indices.dat ]; then
    echo "ERROR: 先跑 0build（cd ../0build && ./run_build_us.sh）"
    exit 1
fi

ION=$(cat ../1model/ion_index.dat)
OX=$(cat ../1model/ox_indices.dat)
echo ">> ion index=$ION   target pore O indices: $OX"

count=0
while read -r z k; do
    case "$z" in ''|\#*) continue ;; esac
    win=$(printf "%.2f" "$z")

    # 生成窗口 colvars（固定中心，不拉伸）
    cat <<EOF > us_${win}.colvars
colvarsTrajFrequency 500
colvarsRestartFrequency 5000
colvar {
  name z_dist
  distanceZ {
    main { atomNumbers { $ION } }
    ref  { atomNumbers { $OX } }
  }
}
harmonic {
  colvars z_dist
  centers ${win}
  forceConstant ${k}
}
EOF

    # 替换模板占位符生成窗口 conf
    sed -e "s/WINDOW_PDB_FILE/win_${win}.pdb/g" \
        -e "s/WINDOW_OUT_NAME/us_${win}/g" \
        -e "s/WINDOW_COLVARS_FILE/us_${win}.colvars/g" \
        template.conf > us_${win}.conf

    count=$((count+1))
done < windows.txt

echo "======================================================"
echo "生成完成，共 $count 个窗口（us_XX.XX.colvars + us_XX.XX.conf）"
echo "======================================================"
