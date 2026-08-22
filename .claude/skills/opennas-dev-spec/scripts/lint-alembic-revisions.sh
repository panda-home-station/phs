#!/usr/bin/env bash
# lint-alembic-revisions.sh — 检测手写 / 非 hex 的 alembic revision id
#
# 配合开发规范 §1 一起使用 (rules.md)。
# 真随机 hex 12 字符 unique-char-count 通常 6-10,
# 手写整齐 hex 12 字符 unique-char-count == 12 (无碰撞)。
#
# Usage:
#   bash scripts/lint-alembic-revisions.sh                              # 默认扫描 26.0/
#   bash scripts/lint-alembic-revisions.sh --dir alembic/versions/26.0/ # 自定义路径
#   bash scripts/lint-alembic-revisions.sh --strict                    # 任何 hand-written hex 都 fail
#   bash scripts/lint-alembic-revisions.sh --with-detail               # 列出每个 id 的 unique 数
#
# Exit code:
#   0  通过
#   1  发现手写 / 非 hex

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# 寻找 alembic 目录
find_alembic_dir() {
    local candidates=(
        "middleware/src/middlewared/middlewared/alembic/versions"
        "src/middlewared/middlewared/alembic/versions"
        "middlewared/alembic/versions"
        "alembic/versions"
    )
    for c in "${candidates[@]}"; do
        if [[ -d "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

# defaults
DIR=""
STRICT=0
WITH_DETAIL=0
VERSIONS_SUBDIR="26.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        --with-detail) WITH_DETAIL=1; shift ;;
        --26.0) VERSIONS_SUBDIR="26.0"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$DIR" ]]; then
    if ! DIR=$(find_alembic_dir); then
        echo "❌ 找不到 alembic/versions 目录。在 OpenNAS 根目录跑,或者用 --dir 指定" >&2
        exit 2
    fi
fi

ALEMBIC_VERSIONS="$DIR/$VERSIONS_SUBDIR"
if [[ ! -d "$ALEMBIC_VERSIONS" ]]; then
    echo "❌ 目录不存在: $ALEMBIC_VERSIONS" >&2
    exit 2
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Alembic revision id lint                                       ║"
echo "║ 规则: 详见 $SKILL_DIR/rules.md §1                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo
echo "扫描目录: $ALEMBIC_VERSIONS"
echo

ALL_IDS=$(grep -rh "^revision = '" "$ALEMBIC_VERSIONS" 2>/dev/null | \
          sed -E "s/.*'([0-9a-f]+)'.*/\1/" | sort -u)

TOTAL=0
HAND_WRITTEN=0
NON_HEX=0
declare -a HAND_LIST
declare -a NON_HEX_LIST

for id in $ALL_IDS; do
    TOTAL=$((TOTAL + 1))
    # 是否非 hex
    if [[ ! "$id" =~ ^[0-9a-f]{12}$ ]]; then
        NON_HEX=$((NON_HEX + 1))
        NON_HEX_LIST+=("$id")
        continue
    fi
    # unique-char-count
    u=$(echo -n "$id" | grep -oE '[0-9a-f]' | sort -u | wc -l)
    if [[ $WITH_DETAIL -eq 1 ]]; then
        marker=''
        [[ $u -eq 12 ]] && marker='  ⚠HAND-WRITTEN'
        printf '  %s  unique=%d%s\n' "$id" "$u" "$marker"
    fi
    if [[ $u -eq 12 ]]; then
        HAND_WRITTEN=$((HAND_WRITTEN + 1))
        HAND_LIST+=("$id")
    fi
done

echo
echo "────────────────────────────────────────────────────────────────"
echo "统计:"
echo "  total revisions:  $TOTAL"
echo "  hand-written:     $HAND_WRITTEN"
echo "  non-hex:          $NON_HEX"
echo

if [[ $NON_HEX -gt 0 ]]; then
    echo "❌ 发现非 hex placeholder:"
    for id in "${NON_HEX_LIST[@]}"; do
        echo "    $id"
    done
    echo
    echo "  这些都是 ghost 节点。修复: 用 alembic revision -m 重新生成,或者整个文件删掉。"
    echo
fi

ALLOW_KNOWN=(
    "c7d8e9f0a1b2"  # 2026-03-27 container_name.py down_revision
    "a4b1e7f9c2d5"  # 2026-02-25 smb-minimum-protocol.py down_revision
    "a8f5d9e2c1b7"  # 2026-02-12 split_dataset_paths.py down_revision
    "c3f8d9e2a4b1"  # 2025-10-13 add_mac_to_vm_nics.py (上游手写, 已 shipped)
)
NEW_HAND=()
for id in "${HAND_LIST[@]}"; do
    skip=0
    for known in "${ALLOW_KNOWN[@]}"; do
        [[ "$id" == "$known" ]] && skip=1 && break
    done
    [[ $skip -eq 0 ]] && NEW_HAND+=("$id")
done

if [[ ${#NEW_HAND[@]} -gt 0 ]]; then
    echo "❌ 发现新的手写 hex id(不是 allow-list 里的历史包袱):"
    for id in "${NEW_HAND[@]}"; do
        echo "    $id"
    done
    echo
    echo "  修复: 改成 alembic revision 生成的随机 hex。"
    echo "       bash middleware/src/middlewared/middlewared/alembic/replace_revision.sh \\"
    echo "         <old_id> <file>"
    echo "       然后下游文件的 down_revision 也同步,DB:"
    echo "         sudo sqlite3 /data/freenas-v1.db \\"
    echo "           \"UPDATE alembic_version SET version_num='<new_id>'\""
    echo
elif [[ $HAND_WRITTEN -gt 0 ]]; then
    echo "✓ 仅历史 3 个 hand-written id (allow-list):"
    for id in "${HAND_LIST[@]}"; do
        echo "    $id"
    done
    echo
    echo "  这些已 shipped,只在 down_revision 引用,无法 rename。"
    echo "  详见 rules.md §1 '当前链上历史包袱'。"
    echo
fi

# Exit code
if [[ $NON_HEX -gt 0 ]]; then
    exit 1
fi
if [[ $STRICT -eq 1 ]] && [[ $HAND_WRITTEN -gt 0 ]]; then
    echo "❌ --strict 模式下,任何 hand-written id 都 fail"
    exit 1
fi
exit 0
