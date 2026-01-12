#!/bin/bash
#
# Merge a Ralph branch back to main
#
# Usage: merge-branch.sh <bead-id> [--no-delete]
#

set -euo pipefail

BEAD_ID="${1:-}"
NO_DELETE="${2:-}"

if [[ -z "$BEAD_ID" ]]; then
    echo "Usage: merge-branch.sh <bead-id> [--no-delete]" >&2
    exit 1
fi

BRANCH_NAME="ralph/$BEAD_ID"
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Ensure we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]]; then
    echo "[merge-branch] Switching to $MAIN_BRANCH"
    git checkout "$MAIN_BRANCH"
fi

# Pull latest
echo "[merge-branch] Pulling latest $MAIN_BRANCH"
git pull origin "$MAIN_BRANCH" --rebase || true

# Check if branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "[merge-branch] Branch $BRANCH_NAME not found" >&2
    exit 1
fi

# Attempt merge
echo "[merge-branch] Merging $BRANCH_NAME into $MAIN_BRANCH"
if git merge "$BRANCH_NAME" --no-edit; then
    echo "[merge-branch] Merge successful"

    # Delete branch unless requested to keep
    if [[ "$NO_DELETE" != "--no-delete" ]]; then
        echo "[merge-branch] Deleting branch $BRANCH_NAME"
        git branch -d "$BRANCH_NAME"
    fi

    echo "MERGE_STATUS: SUCCESS"
else
    echo "[merge-branch] Merge failed - conflict detected"
    git merge --abort
    echo "MERGE_STATUS: CONFLICT"
    exit 1
fi
