#!/bin/bash
#
# god-ralph PreToolUse Hook for Task Tool
#
# This hook intercepts Task tool calls to ensure ralph-worker agents
# are spawned in isolated git worktrees with per-bead session state.
#
# Flow:
# 1. Extract bead_id from Task prompt (looks for "BEAD_ID: xxx" marker)
# 2. Read spawn params from per-bead queue file (.claude/god-ralph/spawn-queue/<bead-id>.json)
# 3. Create worktree based on worktree_policy
# 4. Create per-bead session file (.claude/god-ralph/sessions/<bead-id>.json)
# 5. Create marker file in worktree (.claude/god-ralph/current-bead)
# 6. Return updatedInput with worktree context
#
# Parallel-Safe Design:
# - Each bead has its own queue file (no shared state)
# - Each bead has its own session file (no race conditions)
# - Marker file in worktree enables stop hook to find session
#

set -euo pipefail

# === HELPER: Return deny JSON (standardized error handling) ===
deny_with_reason() {
    local reason="$1"
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
    exit 0  # Exit 0 with JSON, not exit 2
}

# === INPUT PARSING ===
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')

# Only process Task tool calls
if [ "$TOOL_NAME" != "Task" ]; then
    # Not a Task tool call, allow without modification
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# Get subagent type
SUBAGENT_TYPE=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // empty')

# Only process ralph-worker spawns
if [ "$SUBAGENT_TYPE" != "ralph-worker" ]; then
    # Not a ralph-worker, allow without modification
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# === PROJECT ROOT DETECTION ===
# Use CLAUDE_PROJECT_DIR if available, fallback to git, then pwd
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"

if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_ROOT" ]; then
    echo "Warning: Could not determine project root, using pwd" >&2
    PROJECT_ROOT=$(pwd)
fi

GOD_RALPH_DIR="$PROJECT_ROOT/.claude/god-ralph"
SESSIONS_DIR="$GOD_RALPH_DIR/sessions"
SPAWN_QUEUE_DIR="$GOD_RALPH_DIR/spawn-queue"
LOG_DIR="$GOD_RALPH_DIR/logs"

# Setup logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/worktree-hook.log"

log_msg() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" >> "$LOG_FILE"
}

# === BEAD_ID EXTRACTION FROM PROMPT (macOS-compatible) ===
PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty')

# Primary: Look for BEAD_ID: marker (portable grep -E + sed -E)
# This regex matches: BEAD_ID: followed by alphanumeric-with-dashes
BEAD_ID=$(echo "$PROMPT" | grep -E 'BEAD_ID:[[:space:]]*[a-zA-Z0-9-]+' | \
          sed -E 's/.*BEAD_ID:[[:space:]]*([a-zA-Z0-9-]+).*/\1/' | head -1)

if [ -z "$BEAD_ID" ]; then
    # Fallback: try to find beads-XXX pattern (alphanumeric, not just numeric)
    BEAD_ID=$(echo "$PROMPT" | grep -Eo 'beads-[a-zA-Z0-9-]+' | head -1)
fi

if [ -z "$BEAD_ID" ]; then
    log_msg "ERROR: Could not extract bead_id from prompt"
    deny_with_reason "Could not extract bead_id from prompt. Include 'BEAD_ID: <id>' in the prompt."
fi

log_msg "Extracted bead_id: $BEAD_ID"

# === READ PER-BEAD SPAWN QUEUE FILE ===
QUEUE_FILE="$SPAWN_QUEUE_DIR/$BEAD_ID.json"
if [ ! -f "$QUEUE_FILE" ]; then
    log_msg "ERROR: Spawn queue file not found at $QUEUE_FILE"
    deny_with_reason "Spawn queue file not found at $QUEUE_FILE. Orchestrator must write spawn params before calling Task."
fi

WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$QUEUE_FILE")
WORKTREE_POLICY=$(jq -r '.worktree_policy // "none"' "$QUEUE_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations // 10' "$QUEUE_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise // "BEAD COMPLETE"' "$QUEUE_FILE")

log_msg "Read spawn params: policy=$WORKTREE_POLICY, path=$WORKTREE_PATH, max_iter=$MAX_ITERATIONS"

# === WORKTREE POLICY CHECK ===
if [ "$WORKTREE_POLICY" = "none" ]; then
    # No worktree needed, just clean up queue file and allow
    log_msg "Policy 'none': passing through without worktree"
    rm -f "$QUEUE_FILE"
    echo '{"hookSpecificOutput": {"permissionDecision": "allow"}}'
    exit 0
fi

# Policy "required" or "optional" - proceed with worktree creation
if [ -z "$WORKTREE_PATH" ]; then
    # Default worktree path if not specified
    WORKTREE_PATH=".worktrees/ralph-$BEAD_ID"
fi

# === CONSTRUCT FULL WORKTREE PATH ===
if [[ "$WORKTREE_PATH" = /* ]]; then
    FULL_WORKTREE_PATH="$WORKTREE_PATH"
else
    FULL_WORKTREE_PATH="$PROJECT_ROOT/$WORKTREE_PATH"
fi

BRANCH_NAME="ralph/$BEAD_ID"

log_msg "Creating/reusing worktree at $FULL_WORKTREE_PATH"

# === CREATE WORKTREE ===
mkdir -p "$(dirname "$FULL_WORKTREE_PATH")"

if [ -d "$FULL_WORKTREE_PATH" ]; then
    log_msg "Worktree already exists, reusing: $FULL_WORKTREE_PATH"
else
    # Create the worktree
    CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)

    if git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" "$CURRENT_BRANCH" >> "$LOG_FILE" 2>&1; then
        log_msg "Created worktree with new branch: $BRANCH_NAME"
    elif git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" "$BRANCH_NAME" >> "$LOG_FILE" 2>&1; then
        log_msg "Created worktree with existing branch: $BRANCH_NAME"
    else
        WORKTREE_ERROR=$(git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" 2>&1 || true)
        log_msg "ERROR: Failed to create worktree: $WORKTREE_ERROR"
        rm -f "$QUEUE_FILE"
        deny_with_reason "Failed to create worktree for bead $BEAD_ID: $WORKTREE_ERROR"
    fi
fi

# === CREATE PER-BEAD SESSION FILE ===
mkdir -p "$SESSIONS_DIR"
SESSION_FILE="$SESSIONS_DIR/$BEAD_ID.json"

# Escape prompt for JSON storage
ESCAPED_PROMPT=$(echo "$PROMPT" | jq -Rs .)

cat > "$SESSION_FILE" << EOF
{
  "bead_id": "$BEAD_ID",
  "worktree_path": "$FULL_WORKTREE_PATH",
  "status": "in_progress",
  "iteration": 0,
  "max_iterations": $MAX_ITERATIONS,
  "completion_promise": "$COMPLETION_PROMISE",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "original_prompt": $ESCAPED_PROMPT
}
EOF

log_msg "Created session file: $SESSION_FILE"

# === CREATE WORKTREE MARKER AND SYMLINK ===
WORKTREE_GOD_RALPH="$FULL_WORKTREE_PATH/.claude/god-ralph"
mkdir -p "$WORKTREE_GOD_RALPH"

# Marker file with bead_id (for stop hook to identify which session)
echo "$BEAD_ID" > "$WORKTREE_GOD_RALPH/current-bead"
log_msg "Created marker file: $WORKTREE_GOD_RALPH/current-bead"

# Symlink to sessions directory for easy access
if [ -L "$WORKTREE_GOD_RALPH/sessions" ]; then
    rm -f "$WORKTREE_GOD_RALPH/sessions"
fi
ln -sf "$SESSIONS_DIR" "$WORKTREE_GOD_RALPH/sessions"
log_msg "Created symlink: $WORKTREE_GOD_RALPH/sessions -> $SESSIONS_DIR"

# === CLEANUP SPAWN QUEUE FILE ===
rm -f "$QUEUE_FILE"
log_msg "Removed spawn queue file: $QUEUE_FILE"

# === BUILD ENHANCED PROMPT WITH WORKTREE CONTEXT ===
WORKTREE_CONTEXT="## Worktree Environment

You are running in an isolated git worktree at: $FULL_WORKTREE_PATH
Branch: $BRANCH_NAME
Bead ID: $BEAD_ID
Session file: $SESSION_FILE
Max iterations: $MAX_ITERATIONS

CRITICAL: All your file operations should be relative to this worktree.
Run 'cd $FULL_WORKTREE_PATH' before doing any work.
Verify with 'pwd' and 'git branch --show-current'.

---

"

ENHANCED_PROMPT="${WORKTREE_CONTEXT}${PROMPT}"

# === RETURN UPDATED INPUT ===
# Use jq --arg for safe JSON construction
# Note: working_directory is NOT a supported Task input field per ClaudeDocs.
# Worktree context is already embedded in the enhanced prompt.
jq -n \
  --arg prompt "$ENHANCED_PROMPT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "updatedInput": {
        "prompt": $prompt
      }
    }
  }'

log_msg "SUCCESS: Worktree setup complete for $BEAD_ID"
