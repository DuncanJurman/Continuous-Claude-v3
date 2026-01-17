#!/bin/bash
#
# god-ralph Agent-Scoped Stop Hook for ralph-worker
#
# This hook is defined in ralph-worker.md frontmatter and only fires
# when the ralph-worker agent attempts to exit. It implements the
# Ralph Wiggum iteration loop with per-bead session state.
#
# Flow:
# 1. Read bead_id from worktree marker file (.claude/state/god-ralph/current-bead)
# 2. Read session state from per-bead session file
# 3. Check for completion promise in transcript
# 4. If complete or max iterations: allow exit, log to JSONL
# 5. If not complete: increment iteration and block exit
#

set -euo pipefail

# === JSONL LOGGING ===
COMPLETIONS_FILE=""

log_completion() {
  local bead_id="$1" status="$2" iterations="$3" reason="${4:-}"

  # Ensure directory exists
  mkdir -p "$(dirname "$COMPLETIONS_FILE")"

  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg bid "$bead_id" \
    --arg st "$status" --argjson it "$iterations" --arg r "$reason" \
    '{timestamp: $ts, bead_id: $bid, status: $st, iterations: $it, reason: $r}' \
    >> "$COMPLETIONS_FILE"
}

# === INPUT PARSING ===
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

block_with_reason() {
    local reason="$1"
    jq -n --arg r "$reason" '{decision: "block", reason: $r}'
    exit 0
}

# === RESOLVE WORKTREE/PROJECT ROOTS (CWD-INDEPENDENT) ===
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# === FIND BEAD_ID FROM MARKER FILE ===
BEAD_ID=""
MARKER_FILE=""

if [ -n "$WORKTREE_ROOT" ] && [ -f "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" ]; then
    MARKER_FILE="$WORKTREE_ROOT/.claude/state/god-ralph/current-bead"
elif [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/state/god-ralph/current-bead" ]; then
    MARKER_FILE="$PROJECT_ROOT/.claude/state/god-ralph/current-bead"
fi

if [ -n "$MARKER_FILE" ]; then
    BEAD_ID=$(cat "$MARKER_FILE" 2>/dev/null || echo "")
fi

# === FALLBACK: PARSE BEAD_ID FROM TRANSCRIPT ===
if [ -z "$BEAD_ID" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    BEAD_LINE=$(tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | \
        jq -rs '
          [ .[]
            | .content
            | if type == "string" then .
              elif type == "array" then (map(.text? // "") | join(""))
              else "" end
          ]
          | map(select(test("BEAD_ID\\s*:")))
          | last // empty
        ' 2>/dev/null || echo "")
    if [ -n "$BEAD_LINE" ]; then
        BEAD_ID=$(echo "$BEAD_LINE" | sed -nE 's/.*BEAD_ID[[:space:]]*:[[:space:]]*([A-Za-z0-9._-]+).*/\1/p')
    fi
fi

if [ -z "$BEAD_ID" ]; then
    block_with_reason "Ralph stop hook could not resolve BEAD_ID (marker missing, transcript parse failed). Run from worktree root or ensure queue/session initialization."
fi

# === FIND SESSION FILE (CWD-INDEPENDENT) ===
SESSION_FILE=""
if [ -n "$WORKTREE_ROOT" ] && [ -f "$WORKTREE_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json" ]; then
    SESSION_FILE="$WORKTREE_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
elif [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json" ]; then
    SESSION_FILE="$PROJECT_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
fi

if [ -z "$SESSION_FILE" ]; then
    block_with_reason "Ralph stop hook could not find session for $BEAD_ID. Ensure the bead was spawned via /ralph (queue file written) and the worktree exists."
fi

# === RESOLVE COMPLETIONS LOG PATH (MAIN REPO) ===
SESSIONS_DIR=$(dirname "$SESSION_FILE")
SESSIONS_TARGET="$SESSIONS_DIR"

if [ -L "$SESSIONS_DIR" ]; then
    LINK_TARGET=$(readlink "$SESSIONS_DIR" 2>/dev/null || echo "")
    if [ -n "$LINK_TARGET" ]; then
        SESSIONS_TARGET="$LINK_TARGET"
    fi
fi

MAIN_STATE_DIR=$(cd "$SESSIONS_TARGET/.." 2>/dev/null && pwd || echo "")
if [ -n "$MAIN_STATE_DIR" ]; then
    COMPLETIONS_FILE="$MAIN_STATE_DIR/completions.jsonl"
else
    COMPLETIONS_FILE=".claude/state/god-ralph/completions.jsonl"
fi

# === READ SESSION STATE ===
ITERATION=$(jq -r '.iteration // 0' "$SESSION_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations // 10' "$SESSION_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise // empty' "$SESSION_FILE")
STATUS=$(jq -r '.status // "in_progress"' "$SESSION_FILE")

# Validate iteration and max_iterations are numeric
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    block_with_reason "Invalid iteration values in session file for $BEAD_ID. Fix session JSON or respawn with spawn_mode=restart."
fi

if [ -z "$COMPLETION_PROMISE" ]; then
    block_with_reason "Missing completion_promise for $BEAD_ID. Update session or queue file and respawn."
fi

# === ALLOW EXIT FOR TERMINAL STATES ONLY ===
case "$STATUS" in
    merged|verified_passed|failed)
        exit 0
        ;;
esac

# === CHECK MAX ITERATIONS ===
if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
    # Update status to failed
    jq '.status = "failed" | .updated_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
        "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Log to JSONL
    log_completion "$BEAD_ID" "failed" "$ITERATION" "max_iterations_reached"

    echo "Max iterations ($MAX_ITERATIONS) reached for bead $BEAD_ID" >&2
    exit 0  # Allow exit
fi

# === CHECK COMPLETION PROMISE (jq + <promise> tags) ===
# Parse transcript to find promise in last assistant message
# This matches the existing stop-hook.sh approach and avoids stale matches
PROMISE_FOUND=false

if [ -n "$COMPLETION_PROMISE" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract LAST assistant message from JSONL transcript using jq
    # Take last 100 lines to avoid memory issues on large transcripts
    LAST_MESSAGE=$(tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | \
        jq -rs '
          [ .[]
            | select((.role // "") == "assistant" or (.type // "") == "assistant")
            | .content
            | if type == "string" then .
              elif type == "array" then (map(.text? // "") | join(""))
              else "" end
          ] | last // empty
        ' 2>/dev/null || echo "")

    if [ -n "$LAST_MESSAGE" ]; then
        # Look for <promise>COMPLETION_PROMISE</promise> tags in the last message
        # Use -F for fixed string matching (not regex) to avoid special char issues
        if echo "$LAST_MESSAGE" | grep -qF "<promise>$COMPLETION_PROMISE</promise>"; then
            PROMISE_FOUND=true
        fi
    fi
fi

if [ "$PROMISE_FOUND" = "true" ]; then
    # Update status to worker_complete (promise detected; awaiting verification/merge)
    jq '.status = "worker_complete" | .updated_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
        "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Log to JSONL
    log_completion "$BEAD_ID" "worker_complete" "$ITERATION" "promise_detected"

    echo "[god-ralph] Bead $BEAD_ID complete. Promise detected." >&2
    exit 0  # Allow exit - work complete!
fi

# === INCREMENT ITERATION AND BLOCK EXIT ===
NEW_ITERATION=$((ITERATION + 1))
jq '.iteration = '"$NEW_ITERATION"' | .updated_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
    "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

# Block exit and provide reason
cat << EOF
{
  "decision": "block",
  "reason": "Ralph iteration $NEW_ITERATION of $MAX_ITERATIONS for bead $BEAD_ID. Work is not complete. Continue working on the bead. Include '<promise>$COMPLETION_PROMISE</promise>' in your response when verification is complete."
}
EOF
