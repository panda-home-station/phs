#!/bin/bash
# Check git status across all PHS repositories
# Usage: ./check_status.sh [--json]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REPOS=(
    ".:top"
    "webdesktop:webdesktop"
    "webui:webui"
    "middleware:middleware"
)

echo "=== PHS Repository Status ==="
echo ""

has_changes=false

for entry in "${REPOS[@]}"; do
    IFS=':' read -r dir label <<< "$entry"
    cd "$ROOT_DIR/$dir"

    if [[ "$dir" == "." ]]; then
        repo_path="$ROOT_DIR"
    else
        repo_path="$ROOT_DIR/$dir"
    fi

    # Get current branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    # Check for changes
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        status="clean"
        changes=""
    else
        status="modified"
        has_changes=true

        # Get uncommitted changes info
        staged=$(git diff --cached --name-only 2>/dev/null | wc -l)
        unstaged=$(git diff --name-only 2>/dev/null | wc -l)
        untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
        changes=" staged=$staged unstaged=$unstaged untracked=$untracked"
    fi

    echo "[$label] branch=$branch status=$status$changes"
done

echo ""
if $has_changes; then
    echo "Changes detected - commit recommended"
    exit 1
else
    echo "All repositories clean"
    exit 0
fi