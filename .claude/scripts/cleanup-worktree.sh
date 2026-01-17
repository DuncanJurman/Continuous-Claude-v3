#!/bin/bash
#
# Clean up Ralph worktrees after completion
#
# Updated for per-bead session file architecture:
# - Session files: .claude/state/god-ralph/sessions/<bead-id>.json
# - Queue files: .claude/state/god-ralph/queue/<bead-id>.json
# - Marker files: {worktree}/.claude/state/god-ralph/current-bead
#
# Usage:
#   cleanup-worktree.sh <bead-id> [--keep-branch]  - Clean single worktree
#   cleanup-worktree.sh --all                       - Clean all completed/failed worktrees
#   cleanup-worktree.sh --status                    - Show worktree status
#

set -euo pipefail

# State directories
STATE_DIR=".claude/state/god-ralph"
SESSIONS_DIR="$STATE_DIR/sessions"
QUEUE_DIR="$STATE_DIR/queue"
WORKTREES_DIR=".worktrees"

# Function to clean a single worktree
cleanup_single() {
    local bead_id="$1"
    local keep_branch="${2:-}"

    local worktree_path="$WORKTREES_DIR/ralph-$bead_id"
    local branch_name="ralph/$bead_id"
    local session_file="$SESSIONS_DIR/$bead_id.json"
    local queue_file="$QUEUE_DIR/$bead_id.json"

    echo "[cleanup-worktree] Cleaning up bead: $bead_id"

    # Check if worktree exists
    if [[ -d "$worktree_path" ]]; then
        # Ensure no uncommitted changes
        pushd "$worktree_path" > /dev/null
        if [[ -n "$(git status --porcelain 2>/dev/null || echo '')" ]]; then
            echo "[cleanup-worktree] Warning: Uncommitted changes in $worktree_path"
            git status --short
            echo "[cleanup-worktree] Committing as WIP..."
            git add -A
            git commit -m "WIP: Cleanup commit for $bead_id" || true
        fi
        popd > /dev/null

        # Remove worktree
        echo "[cleanup-worktree] Removing worktree at $worktree_path"
        git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
    else
        echo "[cleanup-worktree] Worktree not found at $worktree_path (may already be cleaned)"
    fi

    # Optionally remove branch
    if [[ "$keep_branch" != "--keep-branch" ]]; then
        echo "[cleanup-worktree] Removing branch $branch_name"
        git branch -D "$branch_name" 2>/dev/null || true
    else
        echo "[cleanup-worktree] Keeping branch $branch_name"
    fi

    # Clean up per-bead session file
    if [[ -f "$session_file" ]]; then
        echo "[cleanup-worktree] Removing session file: $session_file"
        rm -f "$session_file"
    fi

    # Clean up any leftover queue file
    if [[ -f "$queue_file" ]]; then
        echo "[cleanup-worktree] Removing queue file: $queue_file"
        rm -f "$queue_file"
    fi

    echo "[cleanup-worktree] Cleaned up $bead_id"
}

# Function to show status of all worktrees
show_status() {
    echo "=== Ralph Worktree Status ==="
    echo ""

    # Show sessions directory status
    echo "Sessions directory: $SESSIONS_DIR"
    if [[ -d "$SESSIONS_DIR" ]]; then
        local session_count
        session_count=$(find "$SESSIONS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "  Active sessions: $session_count"

        if [[ $session_count -gt 0 ]]; then
            echo ""
            echo "  Session Details:"
            for session_file in "$SESSIONS_DIR"/*.json; do
                [[ -f "$session_file" ]] || continue
                local bead_id status iteration max_iterations
                bead_id=$(jq -r '.bead_id // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
                status=$(jq -r '.status // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
                iteration=$(jq -r '.iteration // "?"' "$session_file" 2>/dev/null || echo "?")
                max_iterations=$(jq -r '.max_iterations // "?"' "$session_file" 2>/dev/null || echo "?")
                echo "    $bead_id: $status (iteration $iteration/$max_iterations)"
            done
        fi
    else
        echo "  (directory not found)"
    fi

    echo ""

    # Show queue status
    echo "Queue directory: $QUEUE_DIR"
    if [[ -d "$QUEUE_DIR" ]]; then
        local queue_count
        queue_count=$(find "$QUEUE_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "  Pending spawns: $queue_count"

        if [[ $queue_count -gt 0 ]]; then
            echo "  (These are beads waiting to be spawned)"
            for queue_file in "$QUEUE_DIR"/*.json; do
                [[ -f "$queue_file" ]] || continue
                local bead_id
                bead_id=$(basename "$queue_file" .json)
                echo "    - $bead_id"
            done
        fi
    else
        echo "  (directory not found)"
    fi

    echo ""

    # Show worktrees status
    echo "Worktrees directory: $WORKTREES_DIR"
    if [[ -d "$WORKTREES_DIR" ]]; then
        local worktree_count=0
        for worktree in "$WORKTREES_DIR"/ralph-*; do
            [[ -d "$worktree" ]] || continue
            worktree_count=$((worktree_count + 1))

            local bead_id marker_file session_file status iteration max_iterations
            bead_id=$(basename "$worktree" | sed 's/^ralph-//')
            marker_file="$worktree/.claude/state/god-ralph/current-bead"
            session_file="$SESSIONS_DIR/$bead_id.json"

            if [[ -f "$session_file" ]]; then
                status=$(jq -r '.status // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
                iteration=$(jq -r '.iteration // "?"' "$session_file" 2>/dev/null || echo "?")
                max_iterations=$(jq -r '.max_iterations // "?"' "$session_file" 2>/dev/null || echo "?")
                echo "    $bead_id: $status (iteration $iteration/$max_iterations)"
            elif [[ -f "$marker_file" ]]; then
                echo "    $bead_id: worktree exists, no session file"
            else
                echo "    $bead_id: orphaned worktree (no marker file)"
            fi
        done

        if [[ $worktree_count -eq 0 ]]; then
            echo "  (no worktrees found)"
        else
            echo ""
            echo "  Total worktrees: $worktree_count"
        fi
    else
        echo "  (directory not found)"
    fi

    echo ""
}

# Function to clean all completed/failed worktrees
cleanup_all() {
    echo "=== Cleaning Completed/Failed Worktrees ==="

    local cleaned=0
    local skipped=0

    # Clean based on session files
    if [[ -d "$SESSIONS_DIR" ]]; then
        for session_file in "$SESSIONS_DIR"/*.json; do
            [[ -f "$session_file" ]] || continue

            local bead_id status
            bead_id=$(jq -r '.bead_id // empty' "$session_file" 2>/dev/null || echo "")
            status=$(jq -r '.status // "unknown"' "$session_file" 2>/dev/null || echo "unknown")

            if [[ -z "$bead_id" ]]; then
                continue
            fi

            case "$status" in
                merged|completed|failed)
                    echo ""
                    echo "Cleaning $bead_id (status: $status)..."
                    cleanup_single "$bead_id"
                    cleaned=$((cleaned + 1))
                    ;;
                *)
                    echo "Skipping $bead_id (status: $status)"
                    skipped=$((skipped + 1))
                    ;;
            esac
        done
    fi

    # Also check for orphaned worktrees (no session file)
    if [[ -d "$WORKTREES_DIR" ]]; then
        for worktree in "$WORKTREES_DIR"/ralph-*; do
            [[ -d "$worktree" ]] || continue

            local bead_id session_file
            bead_id=$(basename "$worktree" | sed 's/^ralph-//')
            session_file="$SESSIONS_DIR/$bead_id.json"

            if [[ ! -f "$session_file" ]]; then
                echo ""
                echo "Cleaning orphaned worktree: $bead_id..."
                cleanup_single "$bead_id"
                cleaned=$((cleaned + 1))
            fi
        done
    fi

    echo ""
    echo "=== Summary ==="
    echo "Cleaned: $cleaned"
    echo "Skipped (in progress): $skipped"
}

# Main dispatch
case "${1:-}" in
    --all)
        cleanup_all
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        echo "Usage:"
        echo "  cleanup-worktree.sh <bead-id> [--keep-branch]  - Clean single worktree"
        echo "  cleanup-worktree.sh --all                       - Clean all completed/failed"
        echo "  cleanup-worktree.sh --status                    - Show worktree status"
        echo ""
        echo "Per-bead files cleaned:"
        echo "  - .claude/state/god-ralph/sessions/<bead-id>.json"
        echo "  - .claude/state/god-ralph/queue/<bead-id>.json"
        echo "  - .worktrees/ralph-<bead-id>/"
        echo "  - Branch: ralph/<bead-id>"
        ;;
    "")
        echo "Error: Missing argument. Use --help for usage." >&2
        exit 1
        ;;
    *)
        cleanup_single "$1" "${2:-}"
        ;;
esac

echo ""
echo "[cleanup-worktree] Done"
