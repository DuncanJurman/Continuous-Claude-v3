#!/bin/bash
#
# PreToolUse Hook for Task Tool - Worktree + Memory Injection
#
# This hook intercepts Task tool calls to ensure ralph-worker agents
# are spawned in isolated git worktrees with per-bead session state
# and relevant memory context injected.
#
# Features:
# 1. Atomic worktree creation with file locking
# 2. Memory injection via recall_learnings.py
# 3. Preserves existing prompt content from prior hooks
# 4. Returns valid JSON with updatedInput
#
# Flow:
# 1. Extract bead_id from Task prompt (looks for "BEAD_ID: xxx" marker)
# 2. Read spawn params from per-bead queue file (.claude/state/god-ralph/queue/<bead-id>.json)
# 3. Create worktree atomically with locking
# 4. Inject memory context from recall_learnings.py
# 5. Create per-bead session file (.claude/state/god-ralph/sessions/<bead-id>.json)
# 6. Create marker file in worktree (.claude/state/god-ralph/current-bead)
# 7. Return updatedInput with worktree + memory context prepended
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
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}')

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

STATE_DIR="$PROJECT_ROOT/.claude/state/god-ralph"
SESSIONS_DIR="$STATE_DIR/sessions"
QUEUE_DIR="$STATE_DIR/queue"
LOG_DIR="$STATE_DIR/logs"
LOCK_DIR="$STATE_DIR/locks"

# Setup logging, locks, and queue directories
mkdir -p "$LOG_DIR" "$LOCK_DIR" "$QUEUE_DIR"
LOG_FILE="$LOG_DIR/worktree-hook.log"

log_msg() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" >> "$LOG_FILE"
}

# === BEAD_ID EXTRACTION FROM PROMPT (macOS-compatible) ===
PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty')

# Primary: Look for BEAD_ID: or Bead ID heading (portable awk)
BEAD_ID=$(echo "$PROMPT" | awk '
  {
    lower = tolower($0)
    if (match(lower, /^[[:space:]]*bead_id[[:space:]]*:/)) {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
    if (match(lower, /^[[:space:]]*bead[[:space:]]+id[[:space:]]*:/)) {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
    if (match(lower, /^[[:space:]]*#{1,3}[[:space:]]*bead[[:space:]]+id[[:space:]]*$/)) {
      if (getline) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  }
' | head -1)

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
QUEUE_FILE="$QUEUE_DIR/$BEAD_ID.json"
if [ ! -f "$QUEUE_FILE" ]; then
    log_msg "ERROR: Queue file not found at $QUEUE_FILE"
    deny_with_reason "Queue file not found at $QUEUE_FILE. Orchestrator must write spawn params before calling Task."
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

# === ATOMIC WORKTREE CREATION WITH LOCKING ===
LOCK_FILE="$LOCK_DIR/worktree-$BEAD_ID.lock"
LOCK_DIR_PATH=""
LOCK_MODE=""

release_lock() {
    if [ "$LOCK_MODE" = "flock" ]; then
        flock -u 200
    elif [ -n "$LOCK_DIR_PATH" ]; then
        rmdir "$LOCK_DIR_PATH" 2>/dev/null || true
    fi
}

# Create parent directory for worktree
mkdir -p "$(dirname "$FULL_WORKTREE_PATH")"

# Acquire lock for worktree creation (portable fallback if flock missing)
if command -v flock >/dev/null 2>&1; then
    LOCK_MODE="flock"
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_msg "Another process is creating worktree for $BEAD_ID, waiting..."
        flock 200  # Wait for lock
    fi
else
    LOCK_MODE="mkdir"
    LOCK_DIR_PATH="${LOCK_FILE}.d"
    attempts=0
    while ! mkdir "$LOCK_DIR_PATH" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 150 ]; then
            log_msg "ERROR: Timed out waiting for lock $LOCK_DIR_PATH"
            deny_with_reason "Timed out waiting for worktree lock for bead $BEAD_ID"
        fi
        sleep 0.2
    done
fi

if [ -d "$FULL_WORKTREE_PATH" ]; then
    log_msg "Worktree already exists, reusing: $FULL_WORKTREE_PATH"
else
    # Create the worktree atomically
    CURRENT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)

    if git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" "$CURRENT_BRANCH" >> "$LOG_FILE" 2>&1; then
        log_msg "Created worktree with new branch: $BRANCH_NAME"
    elif git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" "$BRANCH_NAME" >> "$LOG_FILE" 2>&1; then
        log_msg "Created worktree with existing branch: $BRANCH_NAME"
    else
        WORKTREE_ERROR=$(git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" 2>&1 || true)
        log_msg "ERROR: Failed to create worktree: $WORKTREE_ERROR"
        rm -f "$QUEUE_FILE"
        release_lock
        deny_with_reason "Failed to create worktree for bead $BEAD_ID: $WORKTREE_ERROR"
    fi
fi

# Release lock
release_lock

# === INJECT MEMORY CONTEXT ===
MEMORY_CONTEXT=""

# Try to recall relevant learnings based on bead description
# Extract task keywords from the prompt (first 200 chars after "Task" or "##")
TASK_KEYWORDS=$(echo "$PROMPT" | grep -E '(Task|##)' | head -1 | cut -c1-200 | tr -cd '[:alnum:] ' || echo "")

if [ -n "$TASK_KEYWORDS" ] && [ -d "$PROJECT_ROOT/opc" ]; then
    log_msg "Attempting memory recall with keywords: $TASK_KEYWORDS"

    # Run recall_learnings.py to get relevant context
    RECALL_OUTPUT=$(cd "$PROJECT_ROOT/opc" && PYTHONPATH=. uv run python scripts/core/recall_learnings.py \
        --query "$TASK_KEYWORDS" --k 3 --text-only 2>/dev/null || echo "")

    if [ -n "$RECALL_OUTPUT" ] && [ "$RECALL_OUTPUT" != "No results found." ]; then
        MEMORY_CONTEXT="## Relevant Memory Context

The following learnings from past sessions may be helpful:

$RECALL_OUTPUT

---

"
        log_msg "Injected memory context (${#MEMORY_CONTEXT} chars)"
    else
        log_msg "No relevant memory found for keywords"
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
WORKTREE_STATE_DIR="$FULL_WORKTREE_PATH/.claude/state/god-ralph"
mkdir -p "$WORKTREE_STATE_DIR"

# Marker file with bead_id (for stop hook to identify which session)
echo "$BEAD_ID" > "$WORKTREE_STATE_DIR/current-bead"
log_msg "Created marker file: $WORKTREE_STATE_DIR/current-bead"

# Symlink to sessions directory for easy access
if [ -L "$WORKTREE_STATE_DIR/sessions" ]; then
    rm -f "$WORKTREE_STATE_DIR/sessions"
fi
ln -sf "$SESSIONS_DIR" "$WORKTREE_STATE_DIR/sessions"
log_msg "Created symlink: $WORKTREE_STATE_DIR/sessions -> $SESSIONS_DIR"

# === CLEANUP SPAWN QUEUE FILE ===
rm -f "$QUEUE_FILE"
log_msg "Removed queue file: $QUEUE_FILE"

# === BUILD ENHANCED PROMPT WITH WORKTREE + MEMORY CONTEXT ===
# IMPORTANT: Prepend to existing prompt, do not replace
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

# Combine: Memory Context + Worktree Context + Original Prompt
ENHANCED_PROMPT="${MEMORY_CONTEXT}${WORKTREE_CONTEXT}${PROMPT}"

# === RETURN UPDATED INPUT ===
# Use jq --arg for safe JSON construction
# Note: working_directory is NOT a supported Task input field per ClaudeDocs.
# Worktree context is already embedded in the enhanced prompt.
jq -n \
  --argjson ti "$TOOL_INPUT" \
  --arg prompt "$ENHANCED_PROMPT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "updatedInput": ($ti + {prompt: $prompt})
    }
  }'

log_msg "SUCCESS: Worktree setup complete for $BEAD_ID with memory injection"
