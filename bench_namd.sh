#!/bin/bash
# ============================================================
#  bench_namd.sh —— 本机 NAMD 最优并行参数自检
#                  （首次使用先跑一次，结果全局记忆，随时可重测）
#
#  为什么需要这个脚本：
#    NAMD 的 +p 线程数、要不要 +setcpuaffinity、能开几路并发，**全是机器相关的**。
#    文档里写的 "+p32 +setcpuaffinity +devices 0" 是开发机（52 核 Xeon + RTX 4090）
#    的实测最优值，换一台机器照抄可能慢十倍，甚至因为绑核把多进程全钉到 CPU0 而假死。
#    所以规矩是：**第一次用这套 skill 先测一次**，结果写进全局记忆文件，之后所有脚本
#    直接读它；机器换了或想复核时再跑一次 --retest 即可。
#
#  全局记忆文件（本机专属，不属于仓库）：
#    ${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}
#    纯 key=value、可被 bash source。全库脚本都读它，键的含义见 machine.conf.example。
#
#  用法：
#    bash bench_namd.sh                  # 没配置→自动开测；已有配置→打印摘要 + 提示重测
#    bash bench_namd.sh --retest         # 强制重测并覆盖（旧文件备份为 .bak-时间戳）
#    bash bench_namd.sh --show           # 打印现有配置 + 推荐命令行
#    bash bench_namd.sh --print [single|conc|all]    # 只输出命令行（文档/agent 直接抄）
#    bash bench_namd.sh --env            # 只探测环境（CPU/内存/GPU/NAMD/VMD/Python），不跑基准
#    bash bench_namd.sh --quick          # 缩小线程扫描集（16/32/48），省时间
#    bash bench_namd.sh --steps N        # 每档跑多少步（默认 5000；越大越准越慢）
#    bash bench_namd.sh --cpu-only       # 无 GPU：只扫线程（要求 NAMD 是非 CUDA 版）
#    bash bench_namd.sh --devices N      # 指定 GPU 编号（默认 0）
#    bash bench_namd.sh --system a.psf a.pdb    # 换基准体系（默认示例模型 cnt_crown）
#    bash bench_namd.sh --out 路径       # 指定配置输出路径
#    bash bench_namd.sh -y               # 不再确认，直接开跑
#
#  安全性：
#    * 所有基准跑在 mktemp -d 临时目录里，跑完删除；不写项目目录、不碰任何现存 conf。
#    * 只写一个文件：全局记忆 machine.conf（外加同目录 bench.log 与旧文件备份）。
#    * 无 GPU 节点、或 NAMD 是 CUDA 版却起不来时【不写配置】，直接报错退出。
#
#  ⚠️ 在 dsh 之类沙箱里跑会失败：默认沙箱看不到 /dev/nvidia*，nvidia-smi 报
#     "couldn't communicate with the NVIDIA driver"，NAMD 直接段错误。
#     这不是配置问题，请在正常终端（或 danger-full-access 沙箱）里跑本脚本。
#     详见 WORKFLOW.md §0.1 与 §8 第 9 条。
# ============================================================
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_SYS_PSF="$SELF/models/cnt_crown/1model/system_ion.psf"
DEF_SYS_PDB="$SELF/models/cnt_crown/1model/system_ion.pdb"
DEF_FF_DIR="$SELF/models/cnt_crown/forcefield"

CONF="${MD_MASTER_MACHINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/md-master/machine.conf}"
MODE=auto
STEPS="${BENCH_STEPS:-5000}"
SMOKE_STEPS="${BENCH_SMOKE_STEPS:-20}"
TMO="${BENCH_TIMEOUT:-900}"
QUICK=0
CPU_ONLY=0
ASSUME_YES=0
DEVICES_ARG="${DEVICES_ARG:-0}"
SYS_PSF=""
SYS_PDB=""
THREAD_SET="${BENCH_THREADS:-8 16 24 32 40 48}"

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠  %s\n' "$*" >&2; }
die()  { printf '✗  %s\n' "$*" >&2; exit 1; }
hr()   { say "------------------------------------------------------------"; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- 参数
PRINT_WHAT=all
while [ $# -gt 0 ]; do
    case "$1" in
        --retest|--force) MODE=bench; shift ;;
        --show)           MODE=show; shift ;;
        --print)          MODE=print; shift
                          case "${1:-}" in ''|--*) PRINT_WHAT=all ;;
                                          *) PRINT_WHAT="$1"; shift ;; esac ;;
        --env)            MODE=env; shift ;;
        --quick)          QUICK=1; shift ;;
        --steps)          STEPS="${2:?--steps 需要一个数字}"; shift 2 ;;
        --cpu-only)       CPU_ONLY=1; shift ;;
        --devices)        DEVICES_ARG="${2:?--devices 需要一个编号}"; shift 2 ;;
        --system)         SYS_PSF="${2:?--system 需要 psf 与 pdb 两个路径}"
                          SYS_PDB="${3:?--system 需要 psf 与 pdb 两个路径}"; shift 3 ;;
        --out)            CONF="${2:?--out 需要一个路径}"; shift 2 ;;
        -y|--yes)         ASSUME_YES=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                die "未知参数：$1（用 --help 看用法）" ;;
    esac
done

# 默认基准体系
[ -n "$SYS_PSF" ] || SYS_PSF="$DEF_SYS_PSF"
[ -n "$SYS_PDB" ] || SYS_PDB="$DEF_SYS_PDB"
FF_DIR="$DEF_FF_DIR"
# --system 给了自定义体系时，力场优先用体系同级目录的 forcefield/
if [ "$SYS_PSF" != "$DEF_SYS_PSF" ]; then
    cand="$(cd "$(dirname "$SYS_PSF")/.." && pwd)/forcefield"
    [ -d "$cand" ] && FF_DIR="$cand"
fi

[ "$QUICK" = 1 ] && THREAD_SET="16 32 48"

# ---------------------------------------------------------------- 环境探测
CPU_MODEL=""; CPU_CORES=""; MEM_GB=""; HOST=""
GPU_OK=0; GPU_NAME="unknown"
NAMD=""; VMD=""; PYTHON=""
BENCH_ATOMS=0
BOX_A=""; BOX_B=""; BOX_C=""
ORG_X=""; ORG_Y=""; ORG_Z=""

detect_env() {
    HOST="$(hostname -s 2>/dev/null || hostname)"
    CPU_MODEL="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    [ -n "$CPU_MODEL" ] || CPU_MODEL="unknown"
    CPU_CORES="$(nproc 2>/dev/null || echo 1)"
    MEM_GB="$(awk '/^MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null)"
    [ -n "$MEM_GB" ] || MEM_GB=0

    # GPU：先问 nvidia-smi（最可靠），失败再用 lspci + /dev 节点兜底
    local q
    if q="$(timeout 10 nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null)" \
       && [ -n "$q" ]; then
        GPU_NAME="$(printf '%s\n' "$q" | head -1 | sed 's/, */ /g')"
        GPU_OK=1
    else
        GPU_OK=0
        if command -v lspci >/dev/null 2>&1; then
            GPU_NAME="$(lspci 2>/dev/null | grep -i 'nvidia' | head -1 | sed 's/.*: //' || true)"
        fi
        [ -n "$GPU_NAME" ] || GPU_NAME="unknown"
        # 有设备节点但没有驱动通信 = 沙箱/驱动异常，仍然算不可用
        for d in /dev/nvidia0 /dev/nvidiactl; do
            [ -e "$d" ] && GPU_NAME="$GPU_NAME (设备节点在，但驱动不可通信)"
        done
    fi

    # NAMD：环境变量 → PATH → 常见安装位置
    local c p
    for c in "${NAMD:-}" "$(command -v namd3 2>/dev/null)" "$(command -v namd2 2>/dev/null)"; do
        if [ -n "$c" ] && [ -x "$c" ]; then NAMD="$c"; break; fi
    done
    if [ -z "$NAMD" ]; then
        for p in "$HOME"/Install/Namd/*/namd3 "$HOME"/Install/Namd/*/namd2 \
                 /opt/namd*/*/namd3 /opt/namd*/*/namd2 \
                 /usr/local/bin/namd3 /usr/local/bin/namd2; do
            if [ -x "$p" ]; then NAMD="$p"; break; fi
        done
    fi

    # VMD
    for c in "${VMD:-}" "$(command -v vmd 2>/dev/null)" /usr/local/bin/vmd; do
        if [ -n "$c" ] && [ -x "$c" ]; then VMD="$c"; break; fi
    done

    # Python：优先 conda 的 MD 环境（分析脚本要 numpy/matplotlib/MDAnalysis）
    for c in "${PYTHON:-}" "$HOME/anaconda3/envs/MD/bin/python" \
             "${CONDA_PREFIX:-}/bin/python" "$(command -v python3 2>/dev/null)" \
             /usr/bin/python3; do
        if [ -n "$c" ] && [ -x "$c" ]; then
            if "$c" -c 'import numpy' >/dev/null 2>&1; then PYTHON="$c"; break; fi
            [ -n "$PYTHON" ] || PYTHON="$c"      # 没有 numpy 也先记下，后面会警告
        fi
    done
}

print_env() {
    hr
    say "主机      : $HOST"
    say "CPU       : $CPU_MODEL（$CPU_CORES 逻辑核）"
    say "内存      : ${MEM_GB} GB"
    if [ "$GPU_OK" = 1 ]; then
        say "GPU       : $GPU_NAME  [可用]"
    else
        say "GPU       : $GPU_NAME  [不可用]"
    fi
    say "NAMD      : ${NAMD:-未找到}"
    say "VMD       : ${VMD:-未找到}"
    say "Python    : ${PYTHON:-未找到}"
    if [ -n "$PYTHON" ]; then
        say "            $("$PYTHON" -c 'import numpy; print("numpy", numpy.__version__)' 2>/dev/null || echo '缺 numpy（分析/WHAM 会失败）')"
    fi
    say "配置文件  : $CONF $([ -f "$CONF" ] && echo '（已存在）' || echo '（还没有）')"
    hr
}

# ---------------------------------------------------------------- 读基准体系
read_system() {
    [ -r "$SYS_PSF" ] || die "找不到基准体系 psf：$SYS_PSF"
    [ -r "$SYS_PDB" ] || die "找不到基准体系 pdb：$SYS_PDB"
    [ -d "$FF_DIR" ]  || die "找不到力场目录：$FF_DIR"
    BENCH_ATOMS="$(awk '/!NATOM/{print $1+0; exit}' "$SYS_PSF")"
    [ "$BENCH_ATOMS" -gt 0 ] || die "无法从 $SYS_PSF 读出原子数"

    # 盒子边长：优先 PDB 的 CRYST1；没有就用坐标极值 +2 Å
    local c1
    c1="$(awk '/^CRYST1/{printf "%.3f %.3f %.3f\n", substr($0,7,9)+0, substr($0,16,9)+0, substr($0,25,9)+0; exit}' "$SYS_PDB")"
    if [ -n "$c1" ]; then
        set -- $c1; BOX_A="$1"; BOX_B="$2"; BOX_C="$3"
    else
        c1="$(coord_extent "$SYS_PDB")"
        [ -n "$c1" ] || die "无法从 $SYS_PDB 读出坐标，PDB 里既没有 CRYST1 也没有原子坐标"
        set -- $c1; BOX_A="$1"; BOX_B="$2"; BOX_C="$3"
        warn "PDB 里没有 CRYST1，盒子用坐标极值 +2 Å 估算：$BOX_A $BOX_B $BOX_C"
    fi
    # cellOrigin = 盒子中心 = 坐标极值中点（NAMD 的 cellOrigin 是中心，不是角点！）
    local mid
    mid="$(coord_mid "$SYS_PDB")"
    [ -n "$mid" ] || die "无法从 $SYS_PDB 计算盒子中心"
    set -- $mid; ORG_X="$1"; ORG_Y="$2"; ORG_Z="$3"
}

# 坐标极值 → 边长（+2 Å 余量）
coord_extent() {
    awk '/^(ATOM|HETATM)/{
            x=substr($0,31,8)+0; y=substr($0,39,8)+0; z=substr($0,47,8)+0
            if(!n){x0=x1=x;y0=y1=y;z0=z1=z;n=1}
            else{if(x<x0)x0=x; if(x>x1)x1=x; if(y<y0)y0=y; if(y>y1)y1=y; if(z<z0)z0=z; if(z>z1)z1=z}
         }
         END{ if(!n) exit 1; printf "%.3f %.3f %.3f\n", x1-x0+2, y1-y0+2, z1-z0+2 }' "$1"
}

# 坐标极值中点
coord_mid() {
    awk '/^(ATOM|HETATM)/{
            x=substr($0,31,8)+0; y=substr($0,39,8)+0; z=substr($0,47,8)+0
            if(!n){x0=x1=x;y0=y1=y;z0=z1=z;n=1}
            else{if(x<x0)x0=x; if(x>x1)x1=x; if(y<y0)y0=y; if(y>y1)y1=y; if(z<z0)z0=z; if(z>z1)z1=z}
         }
         END{ if(!n) exit 1; printf "%.3f %.3f %.3f\n", (x0+x1)/2, (y0+y1)/2, (z0+z1)/2 }' "$1"
}

# ---------------------------------------------------------------- 基准 conf
write_conf() {
    local path="$1" steps="$2" p
    {
        printf '# 由 bench_namd.sh 自动生成，仅用于本机性能基准（用完即删）\n'
        printf 'structure          %s\n' "$SYS_PSF"
        printf 'coordinates        %s\n' "$SYS_PDB"
        printf 'set temperature    300\n'
        printf 'set outputname     bench\n'
        printf 'paraTypeCharmm     on\n'
        for p in par_all36_prot.prm par_all36_lipid.prm par_water_ions_na.prm \
                 par_all36_na.prm toppar_all36_dphpc.str C_O.par; do
            [ -f "$FF_DIR/$p" ] && printf 'parameters         %s/%s\n' "$FF_DIR" "$p"
        done
        printf 'outputName         $outputname\n'
        printf 'binaryoutput       yes\n'
        printf 'restartfreq        100000000\n'
        printf 'dcdfreq            100000000\n'
        printf 'xstFreq            100000000\n'
        printf 'outputEnergies      %s\n' "$steps"
        printf 'firsttimestep      0\n'
        printf 'exclude            scaled1-4\n'
        printf '1-4scaling         1.0\n'
        printf 'cutoff             12.0\n'
        printf 'switching          on\n'
        printf 'switchdist         10.0\n'
        printf 'pairlistdist       14.0\n'
        printf 'PME                yes\n'
        printf 'PMEGridSpacing     1.0\n'
        printf 'timestep           2.0\n'
        printf 'rigidBonds         all\n'
        printf 'nonbondedFreq      1\n'
        printf 'fullElectFrequency 2\n'
        printf 'langevin           on\n'
        printf 'langevinTemp       300\n'
        printf 'langevinDamping    1.0\n'
        printf 'cellBasisVector1   %s 0.0 0.0\n' "$BOX_A"
        printf 'cellBasisVector2   0.0 %s 0.0\n' "$BOX_B"
        printf 'cellBasisVector3   0.0 0.0 %s\n' "$BOX_C"
        printf 'cellOrigin         %s %s %s\n' "$ORG_X" "$ORG_Y" "$ORG_Z"
        printf 'run                %s\n' "$steps"
    } > "$path"
}

# 从 NAMD 日志里取 "PERFORMANCE: ... averaging X ns/day"
parse_nsday() {
    # NAMD 日志里两种写法都见过：
    #     PERFORMANCE: 5000  averaging 115.8 ns/day, ...      （逐段统计）
    #     Performance:      115.8 ns/day, ...                 （结尾汇总）
    # 统一大写化再匹配，免得只认对一种大小写（踩过）。
    awk 'toupper($0) ~ /PERFORMANCE:/ {
             if (match($0, /[0-9.]+[ ]*ns\/day/)) { v=substr($0, RSTART, RLENGTH); sub(/[ ]*ns\/day/, "", v) }
         }
         END{ if (v!="") print v }' "$1"
}

# 墙钟换算 ns/day（日志里没有 PERFORMANCE 行时的兜底）：$1=起始秒 $2=结束秒 $3=步数
wall_nsday() {
    awk -v t0="$1" -v t1="$2" -v s="$3" 'BEGIN{ d=t1-t0; if (d<=0) exit 1; printf "%.2f", s*2/1e6*86400/d }'
}

# 跑 benchmark：jobs 个进程并发，每个 +p$nt $aff +devices $DEVICES_ARG
# 成功时输出 "总ns/day|每进程ns/day 列表"；失败返回非 0
run_jobs() {
    local tag="$1" nt="$2" aff="$3" njobs="$4" steps="$5"
    local wd="$TMP/$tag" i
    local -a dirs=() pids=()
    for ((i=0; i<njobs; i++)); do
        dirs+=("$wd/$i")
        mkdir -p "${dirs[$i]}"
        write_conf "${dirs[$i]}/bench.conf" "$steps"
    done

    local t0 t1
    t0="$(date +%s.%N)"
    for ((i=0; i<njobs; i++)); do
        ( cd "${dirs[$i]}" && timeout "$TMO" "$NAMD" +p"$nt" $aff +devices "$DEVICES_ARG" \
              bench.conf > bench.log 2>&1 ) &
        pids+=($!)
    done
    local rc=0
    for ((i=0; i<njobs; i++)); do
        wait "${pids[$i]}" || rc=1
    done
    t1="$(date +%s.%N)"

    local total="0" per="" v
    for ((i=0; i<njobs; i++)); do
        if grep -qE 'FATAL ERROR|CUDA error|Segmentation' "${dirs[$i]}/bench.log" 2>/dev/null; then rc=1; fi
        v="$(parse_nsday "${dirs[$i]}/bench.log")"
        if [ -z "$v" ]; then
            # 太短没打出 PERFORMANCE 行时用墙钟兜底（仅退出码正常时可信）
            [ "$rc" = 0 ] && v="$(wall_nsday "$t0" "$t1" "$steps")"
        fi
        if [ -z "$v" ]; then
            warn "基准 [$tag] 第 $((i+1)) 个进程没跑出性能数据，日志末尾："
            tail -12 "${dirs[$i]}/bench.log" 2>/dev/null | sed 's/^/      /' >&2
            return 1
        fi
        total="$(awk -v a="$total" -v b="$v" 'BEGIN{printf "%.2f", a+b}')"
        per="$per $v"
    done
    [ "$rc" = 0 ] || { warn "基准 [$tag] 有进程异常退出（见 bench.log）"; return 1; }
    # ⚠️ 进度信息只能走 stderr：本函数的 stdout 是返回值，调用方用 $(...) 捕获
    printf '   [bench] %s ： 共 %s ns/day （每进程%s ）\n' "$tag" "$total" "$per" >&2
    echo "$total|$per"
}

# ---------------------------------------------------------------- 配置读写
write_machine_conf() {
    local dir tmp bak
    dir="$(dirname "$CONF")"
    mkdir -p "$dir" || die "无法创建配置目录：$dir"
    tmp="$CONF.tmp.$$"
    bak=""
    if [ -f "$CONF" ]; then
        bak="$CONF.bak-$(date '+%Y%m%d-%H%M%S')"
        cp -p "$CONF" "$bak"
    fi
    {
        printf '# machine.conf —— MD 全局机器记忆（由 bench_namd.sh 自动生成，请勿手改）\n'
        printf '# 生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf '# 重测：bash <md-master>/bench_namd.sh --retest\n'
        printf '# 位置：%s（可用环境变量 MD_MASTER_MACHINE_CONF 覆盖）\n' "$CONF"
        # ⚠️ 字符串型取值必须加引号：CPU 型号/日期里带空格和括号，不加引号
        #    会让 `. machine.conf` 把这些内容当命令执行（实测踩过）。
        printf 'MACHINE_ID="%s"\n'         "$HOST"
        printf 'BENCH_DATE="%s"\n'         "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf 'BENCH_ATOMS=%s\n'          "$BENCH_ATOMS"
        printf 'CPU_MODEL="%s"\n'          "$CPU_MODEL"
        printf 'CPU_CORES=%s\n'            "$CPU_CORES"
        printf 'MEM_GB=%s\n'               "$MEM_GB"
        printf 'GPU_OK=%s\n'               "$GPU_OK"
        printf 'GPU_NAME="%s"\n'           "$GPU_NAME"
        printf ': "${NAMD:="%s"}"\n'       "$NAMD"
        printf ': "${VMD:="%s"}"\n'        "${VMD:-}"
        printf ': "${PYTHON:="%s"}"\n'     "${PYTHON:-}"
        printf ': "${DEVICES:=%s}"\n'      "$DEVICES_ARG"
        printf 'SINGLE_NTHREADS=%s\n'      "$BEST_NT"
        printf 'SINGLE_AFFINITY="%s"\n'    "$BEST_AFF"
        printf 'SINGLE_NS_PER_DAY=%s\n'    "$BEST_ND"
        printf 'CONC_MAX_JOBS=%s\n'        "$CONC_JOBS"
        printf 'CONC_NTHREADS=%s\n'        "$CONC_NT"
        printf 'CONC_NS_PER_DAY=%s\n'      "$CONC_ND"
        printf 'ANALYSIS_JOBS=%s\n'        "$ANALYSIS_JOBS"
    } > "$tmp" || die "写 $tmp 失败"
    mv -f "$tmp" "$CONF" || die "移动 $tmp → $CONF 失败"
    [ -n "$bak" ] && say "（旧配置已备份：$bak）"
}

print_cmds() {
    local what="${1:-all}"
    local nt aff dev cj cnt
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        . "$CONF"
    fi
    nt="${SINGLE_NTHREADS:-8}"; aff="${SINGLE_AFFINITY:-}"; dev="${DEVICES:-0}"
    cj="${CONC_MAX_JOBS:-1}";   cnt="${CONC_NTHREADS:-$nt}"
    case "$what" in
        single)
            printf '%s +p%s %s +devices %s\n' "${NAMD:-namd3}" "$nt" "$aff" "$dev" ;;
        conc)
            printf 'MAX_JOBS=%s NTHREADS=%s   # 并发时严禁 +setcpuaffinity\n' "$cj" "$cnt" ;;
        all|*)
            say "# 单进程顺序跑（min / eq / prod / smd）："
            printf '  %s +p%s %s +devices %s xxx.conf > xxx.log 2>&1\n' "${NAMD:-namd3}" "$nt" "$aff" "$dev"
            say "# 多窗口并发（US）："
            printf '  MAX_JOBS=%s NTHREADS=%s ./run_all.sh\n' "$cj" "$cnt"
            say "# 分析脚本并发（VMD 数，取决于内存）："
            printf '  ANALYSIS_JOBS=%s bash calCurr.sh %s 10000\n' "${ANALYSIS_JOBS:-8}" "${ANALYSIS_JOBS:-8}"
            ;;
    esac
}

show_conf() {
    [ -f "$CONF" ] || { warn "还没有配置：$CONF（先跑 bash $0）"; return 1; }
    say "配置文件：$CONF"
    hr
    grep -v '^#' "$CONF" | sed '/^[[:space:]]*$/d' \
        | sed -e 's/^: "${\([A-Z_]*\):=\(.*\)}"$/\1=\2/' -e 's/^/  /'
    hr
    say "推荐命令："
    print_cmds all | sed 's/^/  /'
    hr
    say "重测：bash $0 --retest"
}

# ---------------------------------------------------------------- 主流程
detect_env
[ "$MODE" = env ] && { print_env; exit 0; }
if [ "$MODE" = show ]; then print_env; show_conf; exit $?; fi
if [ "$MODE" = print ]; then
    [ -f "$CONF" ] || die "还没有配置：$CONF（先在正常终端跑 bash $0）"
    print_cmds "$PRINT_WHAT"
    exit 0
fi

if [ "$MODE" = auto ] && [ -f "$CONF" ]; then
    print_env
    say "✓ 已存在机器配置，直接使用（不会重复测试）。"
    # 配置里的主机名跟当前对不上 = 换了机器，参数很可能不再适用
    conf_host="$(sed -n 's/^MACHINE_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONF" | head -1)"
    if [ -n "$conf_host" ] && [ "$conf_host" != "$HOST" ]; then
        warn "配置里的主机是「$conf_host」，当前是「$HOST」—— 换机器了？建议重测：bash $0 --retest"
    fi
    show_conf
    exit 0
fi

# ---- 到这里说明要跑基准 ----
print_env
[ -n "$NAMD" ] || die "没找到 NAMD（namd3/namd2）。请装好后重跑，或用 NAMD=/path/to/namd3 bash $0"
[ -x "$NAMD" ] || die "NAMD 不可执行：$NAMD"
if [ -n "$PYTHON" ] && ! "$PYTHON" -c 'import numpy' >/dev/null 2>&1; then
    warn "Python 缺 numpy，只影响分析与 WHAM，不影响本次基准"
fi

if [ "$GPU_OK" != 1 ] && [ "$CPU_ONLY" != 1 ]; then
    say "✗ 没检测到可用 GPU（nvidia-smi 报：驱动不可通信）。"
    say "  NAMD 的 CUDA 版必须有 GPU 设备节点 /dev/nvidia* 才能启动，否则直接段错误。"
    say "  常见原因与处理："
    say "    1) 在 dsh 之类沙箱里跑 —— 默认沙箱看不到 /dev，请在**正常终端**里重跑本脚本"
    say "       （参见 WORKFLOW.md §8 第 9 条）；"
    say "    2) 驱动没装好 —— 修复后重跑；"
    say "    3) 手上只有 multicore（非 CUDA）版 NAMD —— 加 --cpu-only 只测线程数。"
    exit 1
fi

read_system
say "基准体系   : $SYS_PSF（$BENCH_ATOMS 原子）"
say "盒子       : $BOX_A × $BOX_B × $BOX_C ，中心 ($ORG_X, $ORG_Y, $ORG_Z)"
say "每档步数   : $STEPS（可用 --steps 调大）"
if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    printf '开始自检？预计 1~3 分钟 [Y/n] '
    read -r ans
    case "${ans:-y}" in [Nn]*) die "已取消" ;; esac
fi

# 临时工作区与留档日志都放用户目录下（不用 /tmp：有的容器/沙箱里 /tmp 跨进程不可靠）
BENCH_BASE="${BENCH_TMPDIR:-${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/md-master}}"
mkdir -p "$BENCH_BASE" || die "无法创建临时目录 $BENCH_BASE"
TMP="$(mktemp -d "$BENCH_BASE/bench.XXXXXX")" || die "无法在 $BENCH_BASE 下建临时目录"
cleanup() { if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then rm -rf "$TMP"; fi; }
trap cleanup EXIT
BENCH_LOG="$BENCH_BASE/bench.log"
say "（完整日志留档：$BENCH_LOG，每次自检覆盖）"
exec > >(tee "$BENCH_LOG") 2>&1        # 屏幕与日志文件同时留档

hr
say "[0/4] 冒烟测试：$SMOKE_STEPS 步，确认 NAMD 能在这台机器上起来 ..."
if ! run_jobs smoke 8 "" 1 "$SMOKE_STEPS" >/dev/null; then
    say "✗ 冒烟测试失败：NAMD 起不来。日志末尾："
    tail -20 "$TMP/smoke/0/bench.log" 2>/dev/null | sed 's/^/      /'
    say "提示：CUDA error cudaGetDeviceCount = 没有可用 GPU 节点；"
    say "      unknown atom type / 缺参数 = 力场不匹配；详见 WORKFLOW.md §10 排错速查表。"
    exit 1
fi
say "      冒烟通过。"

hr
say "[1/4] 扫线程数（不绑核，各档独立跑）..."
CANDS=""
for t in $THREAD_SET; do
    [ "$t" -le "$CPU_CORES" ] && CANDS="$CANDS $t"
done
# 基准集全被核数过滤掉的小机器：补上"核数/半核数/四分之一"，保证有可比档位
if [ "$(printf '%s\n' $CANDS | sed '/^$/d' | wc -l)" -lt 3 ]; then
    for t in "$CPU_CORES" "$((CPU_CORES/2))" "$((CPU_CORES/4))"; do
        [ "$t" -ge 1 ] && [ "$t" -le "$CPU_CORES" ] && CANDS="$CANDS $t"
    done
fi
CANDS="$(printf '%s\n' $CANDS | sort -n -u | tr '\n' ' ')"

BEST_NT=1; BEST_ND=0; BEST_AFF=""
for t in $CANDS; do
    r="$(run_jobs "p$t" "$t" "" 1 "$STEPS")" || continue
    nd="${r%%|*}"
    if awk -v a="$nd" -v b="$BEST_ND" 'BEGIN{exit !(a>b)}'; then
        BEST_ND="$nd"; BEST_NT="$t"
    fi
done
[ "$BEST_ND" != 0 ] || die "所有线程档位都失败，无法确定最优参数。请先手动跑一次 min.conf 排查。"
say "  → 不绑核最优：+p$BEST_NT = $BEST_ND ns/day"

hr
say "[2/4] 在 +p$BEST_NT 上验证 +setcpuaffinity ..."
if r="$(run_jobs "p${BEST_NT}-aff" "$BEST_NT" "+setcpuaffinity" 1 "$STEPS")"; then
    nd_aff="${r%%|*}"
    if awk -v a="$nd_aff" -v b="$BEST_ND" 'BEGIN{exit !(a>b)}'; then
        say "  → 绑核更快：$nd_aff > $BEST_ND，采用 +setcpuaffinity"
        BEST_AFF="+setcpuaffinity"; BEST_ND="$nd_aff"
    else
        say "  → 绑核没更快（$nd_aff ≤ $BEST_ND），不加 +setcpuaffinity"
    fi
else
    warn "绑核档位失败，按不加绑核处理"
fi

hr
say "[3/4] 扫并发（并发一律不绑核）..."
CONC_JOBS=1; CONC_NT="$BEST_NT"; CONC_ND="$BEST_ND"
for jobs in 2 3; do
    for t in "$BEST_NT" "$((BEST_NT/2))"; do
        [ "$t" -ge 1 ] || continue
        [ "$t" -le "$CPU_CORES" ] || continue
        r="$(run_jobs "c${jobs}p$t" "$t" "" "$jobs" "$STEPS")" || continue
        nd="${r%%|*}"
        if awk -v a="$nd" -v b="$CONC_ND" 'BEGIN{exit !(a>b)}'; then
            CONC_JOBS="$jobs"; CONC_NT="$t"; CONC_ND="$nd"
        fi
    done
done
if [ "$CONC_JOBS" = 1 ]; then
    say "  → 并发没有更快，建议顺序跑（MAX_JOBS=1）"
else
    say "  → 并发最优：$CONC_JOBS 路 × +p$CONC_NT = $CONC_ND ns/day 合计（不绑核）"
fi

# 分析脚本并发数：按内存缩放（每个 VMD 约 1~2 GB，留一半余量）
ANALYSIS_JOBS="$(awk -v m="$MEM_GB" 'BEGIN{ j=int(m/4); if (j<2) j=2; if (j>16) j=16; print j }')"

hr
say "[4/4] 写入全局机器记忆 ..."
write_machine_conf
say "✓ 已写入：$CONF"
hr
show_conf || true
say "以后所有脚本都会自动读这份配置；换机器或想复核时跑：bash $0 --retest"
