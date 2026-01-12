#!/bin/bash
#
# Setup a git worktree for a Ralph worker
#
# Usage: setup-worktree.sh <bead-id>
#

set -euo pipefail

BEAD_ID="${1:-}"

if [[ -z "$BEAD_ID" ]]; then
    echo "Usage: setup-worktree.sh <bead-id>" >&2
    exit 1
fi

WORKTREE_DIR=".worktrees"
WORKTREE_PATH="$WORKTREE_DIR/ralph-$BEAD_ID"
BRANCH_NAME="ralph/$BEAD_ID"

# Create worktrees directory if needed
mkdir -p "$WORKTREE_DIR"

# Check if worktree already exists
if [[ -d "$WORKTREE_PATH" ]]; then
    echo "[setup-worktree] Worktree already exists at $WORKTREE_PATH"
    exit 0
fi

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "[setup-worktree] Branch $BRANCH_NAME exists, creating worktree"
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
else
    echo "[setup-worktree] Creating new branch $BRANCH_NAME"
    git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
fi

# Create state directory in worktree
mkdir -p "$WORKTREE_PATH/.claude/god-ralph/logs"

echo "[setup-worktree] Worktree ready at $WORKTREE_PATH"
echo "[setup-worktree] Branch: $BRANCH_NAME"
