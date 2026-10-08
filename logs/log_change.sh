#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# log_change.sh —— 往 logs/CHANGELOG.md 追加一条带时间戳的变更记录
#
# 用法：
#   bash logs/log_change.sh <类型> <摘要> [--files "a,b"] [--source "项目路径"] [--note "补充"] [< 正文]
#
#   类型：规则 / 归档 / 修改 / 删除 / 修复
#   正文：用管道传入时会被读入，和 --note 一起写进「说明」段
#
# 例：
#   bash logs/log_change.sh 归档 "CNT1 收成 models/cnt_crown_v2" \
#        --files "models/cnt_crown_v2/README.md,README.md" \
#        --source /path/to/project
# ---------------------------------------------------------------------------
set -euo pipefail

# 定位脚本所在目录（logs/），不受调用时工作目录影响
LOGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$LOGDIR/CHANGELOG.md"

if [ ! -f "$LOG" ]; then
    echo "错误：找不到日志文件 $LOG" >&2
    exit 1
fi

TYPE="${1:-}"
SUMMARY="${2:-}"
if [ -z "$TYPE" ] || [ -z "$SUMMARY" ]; then
    echo "用法：bash logs/log_change.sh <类型> <摘要> [--files \"a,b\"] [--source 路径] [--note 说明]" >&2
    echo "  类型：规则 / 归档 / 修改 / 删除 / 修复" >&2
    exit 2
fi
shift 2

FILES=""
SOURCE=""
NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --files)  FILES="${2:-}";  shift 2 ;;
        --source) SOURCE="${2:-}"; shift 2 ;;
        --note)   NOTE="${2:-}";   shift 2 ;;
        *)        shift ;;
    esac
done

# 管道输入时读正文；交互终端下不读，避免卡住
BODY=""
if [ ! -t 0 ]; then
    BODY="$(cat)"
fi

TS="$(date '+%Y-%m-%d %H:%M:%S %z')"

{
    printf '\n## %s — [%s] %s\n' "$TS" "$TYPE" "$SUMMARY"
    printf '\n- **时间**：%s\n' "$TS"
    printf -- '- **类型**：%s\n' "$TYPE"
    if [ -n "$SOURCE" ]; then
        printf -- '- **来源项目**：%s\n' "$SOURCE"
    fi
    if [ -n "$FILES" ]; then
        printf -- '- **改动文件**：\n'
        # 逗号或换行分隔都支持，逐条变成缩进列表
        printf '%s\n' "$FILES" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*/  - /'
    fi
    if [ -n "$NOTE" ] || [ -n "$BODY" ]; then
        printf -- '- **说明**：\n'
        if [ -n "$NOTE" ]; then
            printf '  %s\n' "$NOTE"
        fi
        if [ -n "$BODY" ]; then
            printf '%s\n' "$BODY" | sed 's/^/  /'
        fi
    fi
} >> "$LOG"

echo "已写入 $LOG"
