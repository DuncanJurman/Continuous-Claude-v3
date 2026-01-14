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
COMPLETIONS_FILE=".claude/state/god-ralph/completions.jsonl"

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
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# === PREVENT INFINITE LOOPS ===
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    # Already in a stop hook continuation, allow exit
    exit 0
fi

# === FIND BEAD_ID FROM MARKER FILE ===
# The hook runs in the worktree context (or main repo if testing)
MARKER_FILE=".claude/state/god-ralph/current-bead"

if [ ! -f "$MARKER_FILE" ]; then
    # Not in a worktree context with proper setup, allow exit
    # This can happen during testing or if session wasn't properly initialized
    exit 0
fi

BEAD_ID=$(cat "$MARKER_FILE" 2>/dev/null || echo "")

if [ -z "$BEAD_ID" ]; then
    echo "Warning: Empty bead_id in marker file" >&2
    exit 0
fi

# === FIND SESSION FILE ===
# Try symlinked sessions directory first (worktree context)
SESSION_FILE=".claude/state/god-ralph/sessions/$BEAD_ID.json"

if [ ! -f "$SESSION_FILE" ]; then
    # Fallback: try main repo location via git
    MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$MAIN_REPO" ]; then
        SESSION_FILE="$MAIN_REPO/.claude/state/god-ralph/sessions/$BEAD_ID.json"
    fi
fi

if [ ! -f "$SESSION_FILE" ]; then
    echo "Error: Session file not found for $BEAD_ID" >&2
    exit 0  # Allow exit on error
fi

# === READ SESSION STATE ===
ITERATION=$(jq -r '.iteration // 0' "$SESSION_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations // 10' "$SESSION_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise // empty' "$SESSION_FILE")
STATUS=$(jq -r '.status // "in_progress"' "$SESSION_FILE")

# Validate iteration and max_iterations are numeric
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid iteration values in session file" >&2
    exit 0
fi

# === CHECK IF ALREADY COMPLETED ===
if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
    exit 0  # Allow exit
fi

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
        jq -rs '[.[] | select(.role == "assistant")] | last | .content // empty' 2>/dev/null || echo "")

    if [ -n "$LAST_MESSAGE" ]; then
        # Look for <promise>COMPLETION_PROMISE</promise> tags in the last message
        # Use -F for fixed string matching (not regex) to avoid special char issues
        if echo "$LAST_MESSAGE" | grep -qF "<promise>$COMPLETION_PROMISE</promise>"; then
            PROMISE_FOUND=true
        fi
    fi
fi

if [ "$PROMISE_FOUND" = "true" ]; then
    # Update status to completed
    jq '.status = "completed" | .updated_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' \
        "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Log to JSONL
    log_completion "$BEAD_ID" "completed" "$ITERATION" "promise_detected"

    echo "[god-ralph] Bead $BEAD_ID completed! Promise detected." >&2
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
