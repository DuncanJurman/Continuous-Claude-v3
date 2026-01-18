#!/bin/bash
#
# PreToolUse Hook for Task Tool - Worktree setup for god-ralph-worker
#
# This hook intercepts Task tool calls to ensure god-ralph-worker agents
# are spawned in isolated git worktrees with per-bead session state.
#
# Features:
# 1. Atomic worktree creation with file locking
# 2. Preserves existing prompt content from prior hooks
# 3. Returns valid JSON with updatedInput
#
# Flow:
# 1. Extract bead_id from Task prompt (looks for "BEAD_ID: xxx" marker)
# 2. Read spawn params from per-bead queue file (.claude/state/god-ralph/queue/<bead-id>.json)
# 3. Create worktree atomically with locking
# 4. Create per-bead session file (.claude/state/god-ralph/sessions/<bead-id>.json)
# 5. Create marker file in worktree (.claude/state/god-ralph/current-bead)
# 6. Return updatedInput with worktree context prepended
#

set -Eeuo pipefail

HOOK_EVENT_NAME="PreToolUse"
FAIL_CLOSED_ALREADY=0

fail_closed() {
    local exit_code=$?
    if [ "${FAIL_CLOSED_ALREADY:-0}" = "1" ]; then
        exit 0
    fi
    FAIL_CLOSED_ALREADY=1

    if [ -n "${LOG_FILE:-}" ]; then
        printf '[%s] ERROR: ensure-worktree failed (exit %s)\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            "$exit_code" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Fail closed: deny the tool call with valid JSON, per ClaudeDocs/Hooks.md.
    local reason="Internal ensure-worktree error (exit ${exit_code}). Check .claude/state/god-ralph/logs/worktree-hook.log."
    printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
        "$HOOK_EVENT_NAME" \
        "$reason"
    exit 0
}

trap fail_closed ERR

allow_without_modification() {
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg ev "$HOOK_EVENT_NAME" '{hookSpecificOutput:{hookEventName:$ev,permissionDecision:"allow"}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"allow"}}\n' "$HOOK_EVENT_NAME"
    fi
    exit 0
}

# === HELPER: Return deny JSON (standardized error handling) ===
deny_with_reason() {
    local reason="$1"
    if [ -n "${LOG_FILE:-}" ]; then
        printf '[%s] DENY: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$reason" >> "$LOG_FILE" 2>/dev/null || true
    fi

    if command -v jq >/dev/null 2>&1; then
        jq -n --arg ev "$HOOK_EVENT_NAME" --arg r "$reason" '{
          hookSpecificOutput: {
            hookEventName: $ev,
            permissionDecision: "deny",
            permissionDecisionReason: $r
          }
        }'
    else
        # Last-resort deny: keep JSON valid (no interpolation).
        printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"Denied"}}\n' "$HOOK_EVENT_NAME"
    fi
    exit 0  # Exit 0 with JSON, not exit 2
}

# === INPUT PARSING ===
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}')

# Only process Task tool calls
if [ "$TOOL_NAME" != "Task" ]; then
    # Not a Task tool call, allow without modification
    allow_without_modification
fi

# Get subagent type
SUBAGENT_TYPE=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // empty')

# Only process god-ralph-worker spawns
if [ "$SUBAGENT_TYPE" != "god-ralph-worker" ]; then
    # Not a god-ralph-worker, allow without modification
    allow_without_modification
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

# Defensive: prevent surprising branch/path names from malformed BEAD_ID.
if ! echo "$BEAD_ID" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    log_msg "ERROR: Invalid BEAD_ID extracted: $BEAD_ID"
    deny_with_reason "Invalid BEAD_ID '$BEAD_ID'. Use only letters, numbers, '.', '_', and '-'."
fi

# === READ PER-BEAD SPAWN QUEUE FILE ===
QUEUE_FILE="$QUEUE_DIR/$BEAD_ID.json"
if [ ! -f "$QUEUE_FILE" ]; then
    log_msg "ERROR: Queue file not found at $QUEUE_FILE"
    deny_with_reason "Queue file not found at $QUEUE_FILE. Orchestrator must write spawn params before calling Task."
fi

WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$QUEUE_FILE")
WORKTREE_POLICY=$(jq -r '.worktree_policy // empty' "$QUEUE_FILE")
BASE_REF=$(jq -r '.base_ref // "main"' "$QUEUE_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations // 10' "$QUEUE_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise // "BEAD COMPLETE"' "$QUEUE_FILE")
SPAWN_MODE=$(jq -r '.spawn_mode // "new"' "$QUEUE_FILE")
CODEX_MODEL=$(jq -r '.codex.model // empty' "$QUEUE_FILE")
CODEX_EFFORT=$(jq -r '.codex.model_reasoning_effort // empty' "$QUEUE_FILE")
QUEUE_BEAD_SPEC=$(jq '.bead_spec // null' "$QUEUE_FILE")

if [ -z "$WORKTREE_POLICY" ]; then
    deny_with_reason "Missing worktree_policy for bead $BEAD_ID. Queue file must include worktree_policy."
fi

case "$WORKTREE_POLICY" in
    required|optional|none)
        ;;
    *)
        deny_with_reason "Invalid worktree_policy '$WORKTREE_POLICY' for bead $BEAD_ID"
        ;;
esac

log_msg "Read spawn params: policy=$WORKTREE_POLICY, path=$WORKTREE_PATH, base_ref=$BASE_REF, max_iter=$MAX_ITERATIONS, spawn_mode=$SPAWN_MODE"

# Validate numeric iterations and spawn mode
if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    deny_with_reason "Invalid max_iterations '$MAX_ITERATIONS' for bead $BEAD_ID"
fi

case "$SPAWN_MODE" in
    new|resume|restart|repair)
        ;;
    *)
        deny_with_reason "Invalid spawn_mode '$SPAWN_MODE' for bead $BEAD_ID"
        ;;
esac

# === WORKTREE POLICY CHECK ===
if [ "$WORKTREE_POLICY" = "none" ]; then
    # No worktree needed, just clean up queue file and allow
    log_msg "Policy 'none': passing through without worktree"
    rm -f "$QUEUE_FILE"
    allow_without_modification
fi

# Policy "required" or "optional" - proceed with worktree creation
if [ -z "$WORKTREE_PATH" ]; then
    # Default worktree path if not specified
    WORKTREE_PATH=".worktrees/ralph-$BEAD_ID"
fi

# === SESSION LOOKUP (BEFORE WORKTREE CREATION) ===
mkdir -p "$SESSIONS_DIR"
SESSION_FILE="$SESSIONS_DIR/$BEAD_ID.json"
SESSION_EXISTS=false

SESSION_WORKTREE_PATH=""
SESSION_BASE_REF=""
SESSION_BASE_SHA=""
SESSION_MAX_ITERATIONS=""
SESSION_PROMISE=""
SESSION_BRANCH=""
SESSION_SPAWN_COUNT=""
SESSION_STATUS=""
SESSION_CREATED_AT=""
SESSION_ORIGINAL_PROMPT=""
SESSION_CODEX_THREAD_ID=""
SESSION_CODEX_CALLS=""
SESSION_CODEX_MODEL=""
SESSION_CODEX_EFFORT=""
SESSION_BEAD_SPEC=""

if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS=true
    SESSION_WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$SESSION_FILE")
    SESSION_BASE_REF=$(jq -r '.base_ref // empty' "$SESSION_FILE")
    SESSION_BASE_SHA=$(jq -r '.base_sha // empty' "$SESSION_FILE")
    SESSION_MAX_ITERATIONS=$(jq -r '.max_iterations // empty' "$SESSION_FILE")
    SESSION_PROMISE=$(jq -r '.completion_promise // empty' "$SESSION_FILE")
    SESSION_BRANCH=$(jq -r '.branch // empty' "$SESSION_FILE")
    SESSION_SPAWN_COUNT=$(jq -r '.spawn_count // empty' "$SESSION_FILE")
    SESSION_STATUS=$(jq -r '.status // empty' "$SESSION_FILE")
    SESSION_CREATED_AT=$(jq -r '.created_at // empty' "$SESSION_FILE")
    SESSION_ORIGINAL_PROMPT=$(jq -r '.original_prompt // empty' "$SESSION_FILE")
    SESSION_CODEX_THREAD_ID=$(jq -r '.codex_thread_id // empty' "$SESSION_FILE")
    SESSION_CODEX_CALLS=$(jq -r '.codex_calls // empty' "$SESSION_FILE")
    SESSION_CODEX_MODEL=$(jq -r '.codex.model // empty' "$SESSION_FILE")
    SESSION_CODEX_EFFORT=$(jq -r '.codex.model_reasoning_effort // empty' "$SESSION_FILE")
    SESSION_BEAD_SPEC=$(jq '.bead_spec // null' "$SESSION_FILE")
fi

if [ "$SPAWN_MODE" = "resume" ] && [ "$SESSION_EXISTS" != "true" ]; then
    deny_with_reason "spawn_mode=resume requires an existing session for $BEAD_ID. Use spawn_mode=new to create one."
fi

if [ "$SPAWN_MODE" = "repair" ] && [ "$SESSION_EXISTS" != "true" ]; then
    deny_with_reason "spawn_mode=repair requires an existing session for $BEAD_ID. Use spawn_mode=new to create one."
fi

if [ "$SESSION_EXISTS" = "true" ] && [ "$SPAWN_MODE" = "new" ]; then
    SPAWN_MODE="resume"
fi

if [ "$SESSION_EXISTS" = "true" ] && [ "$SPAWN_MODE" != "restart" ]; then
    case "$SESSION_STATUS" in
        failed)
            deny_with_reason "Session for $BEAD_ID is failed. Respawn with spawn_mode=restart to reset the loop or create a fix-bead."
            ;;
        worker_complete|verified_passed|merged)
            deny_with_reason "Session for $BEAD_ID is $SESSION_STATUS. Use spawn_mode=restart to reopen or create a fix-bead."
            ;;
    esac
fi

normalize_path() {
    local p="$1"
    if [[ "$p" = /* ]]; then
        echo "$p"
    else
        echo "$PROJECT_ROOT/$p"
    fi
}

# === QUEUE VS SESSION AUTHORITY ===
if [ "$SESSION_EXISTS" = "true" ] && [ "$SPAWN_MODE" != "restart" ]; then
    # Reject parameter drift unless restart
    QUEUE_WORKTREE_FULL=$(normalize_path "$WORKTREE_PATH")
    SESSION_WORKTREE_FULL="$SESSION_WORKTREE_PATH"
    if [ -n "$SESSION_WORKTREE_FULL" ] && [[ "$SESSION_WORKTREE_FULL" != /* ]]; then
        SESSION_WORKTREE_FULL=$(normalize_path "$SESSION_WORKTREE_FULL")
    fi
    if [ -n "$SESSION_WORKTREE_FULL" ] && [ -n "$WORKTREE_PATH" ] && [ "$SESSION_WORKTREE_FULL" != "$QUEUE_WORKTREE_FULL" ]; then
        deny_with_reason "Queue worktree_path ($WORKTREE_PATH) does not match existing session worktree_path ($SESSION_WORKTREE_FULL). Use spawn_mode=restart to override."
    fi
    if [ -n "$SESSION_BASE_REF" ] && [ -n "$BASE_REF" ] && [ "$SESSION_BASE_REF" != "$BASE_REF" ]; then
        deny_with_reason "Queue base_ref ($BASE_REF) does not match existing session base_ref ($SESSION_BASE_REF). Use spawn_mode=restart to override."
    fi
    if [ -n "$SESSION_MAX_ITERATIONS" ] && [ -n "$MAX_ITERATIONS" ] && [ "$SESSION_MAX_ITERATIONS" != "$MAX_ITERATIONS" ]; then
        deny_with_reason "Queue max_iterations ($MAX_ITERATIONS) does not match existing session max_iterations ($SESSION_MAX_ITERATIONS). Use spawn_mode=restart to override."
    fi
    if [ -n "$SESSION_PROMISE" ] && [ -n "$COMPLETION_PROMISE" ] && [ "$SESSION_PROMISE" != "$COMPLETION_PROMISE" ]; then
        deny_with_reason "Queue completion_promise does not match existing session. Use spawn_mode=restart to override."
    fi

    # Prefer existing session values when resuming
    WORKTREE_PATH="${SESSION_WORKTREE_PATH:-$WORKTREE_PATH}"
    BASE_REF="${SESSION_BASE_REF:-$BASE_REF}"
    MAX_ITERATIONS="${SESSION_MAX_ITERATIONS:-$MAX_ITERATIONS}"
    COMPLETION_PROMISE="${SESSION_PROMISE:-$COMPLETION_PROMISE}"
    if [ -n "$SESSION_CODEX_MODEL" ]; then
        CODEX_MODEL="$SESSION_CODEX_MODEL"
    fi
    if [ -n "$SESSION_CODEX_EFFORT" ]; then
        CODEX_EFFORT="$SESSION_CODEX_EFFORT"
    fi
    if [ -n "$SESSION_BEAD_SPEC" ] && [ "$SESSION_BEAD_SPEC" != "null" ]; then
        QUEUE_BEAD_SPEC="$SESSION_BEAD_SPEC"
    fi
fi

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    deny_with_reason "Invalid max_iterations '$MAX_ITERATIONS' after session reconciliation for bead $BEAD_ID"
fi

# === CONSTRUCT FULL WORKTREE PATH ===
if [[ "$WORKTREE_PATH" = /* ]]; then
    FULL_WORKTREE_PATH="$WORKTREE_PATH"
else
    FULL_WORKTREE_PATH="$PROJECT_ROOT/$WORKTREE_PATH"
fi

BRANCH_NAME="ralph/$BEAD_ID"
if [ -n "$SESSION_BRANCH" ] && [ "$SESSION_BRANCH" != "$BRANCH_NAME" ] && [ "$SPAWN_MODE" != "restart" ]; then
    deny_with_reason "Existing session branch ($SESSION_BRANCH) does not match expected ($BRANCH_NAME). Use spawn_mode=restart to override."
fi

# Resolve base ref SHA for auditability
BASE_SHA=$(git -C "$PROJECT_ROOT" rev-parse "$BASE_REF" 2>/dev/null || echo "")
if [ -z "$BASE_SHA" ]; then
    deny_with_reason "Failed to resolve base_ref '$BASE_REF'. Ensure it exists (e.g., 'main') and try again."
fi

if [ "$SESSION_EXISTS" = "true" ] && [ "$SPAWN_MODE" != "restart" ] && [ -n "$SESSION_BASE_SHA" ]; then
    BASE_SHA="$SESSION_BASE_SHA"
fi

log_msg "Creating/reusing worktree at $FULL_WORKTREE_PATH"

validate_worktree() {
    local path="$1"
    if [ ! -d "$path" ]; then
        return 1
    fi
    if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi
    local git_dir
    git_dir=$(git -C "$path" rev-parse --git-dir 2>/dev/null || echo "")
    if ! echo "$git_dir" | grep -q "/worktrees/"; then
        return 1
    fi
    local branch
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$branch" != "$BRANCH_NAME" ]; then
        return 2
    fi
    if ! git -C "$PROJECT_ROOT" worktree list --porcelain | awk -v p="$path" '
        $1 == "worktree" { wt=$2 }
        wt == p { found=1 }
        END { exit found ? 0 : 1 }
    '; then
        return 3
    fi
    return 0
}

if [ "$SESSION_EXISTS" = "true" ] && [ "$SPAWN_MODE" = "resume" ] && [ ! -d "$FULL_WORKTREE_PATH" ]; then
    deny_with_reason "Session exists but worktree path is missing for $BEAD_ID. Use spawn_mode=repair or spawn_mode=restart."
fi

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
    if validate_worktree "$FULL_WORKTREE_PATH"; then
        log_msg "Worktree already exists, reusing: $FULL_WORKTREE_PATH"
    else
        case "$SPAWN_MODE" in
            repair)
                log_msg "Worktree validation failed; attempting repair for $FULL_WORKTREE_PATH"
                git -C "$PROJECT_ROOT" worktree remove "$FULL_WORKTREE_PATH" --force >> "$LOG_FILE" 2>&1 || rm -rf "$FULL_WORKTREE_PATH"
                ;;
            restart)
                log_msg "Worktree invalid; restart requested - removing $FULL_WORKTREE_PATH"
                git -C "$PROJECT_ROOT" worktree remove "$FULL_WORKTREE_PATH" --force >> "$LOG_FILE" 2>&1 || rm -rf "$FULL_WORKTREE_PATH"
                ;;
            *)
                release_lock
                deny_with_reason "Worktree exists but is invalid or on wrong branch. Run /ralph gc or respawn with spawn_mode=repair."
                ;;
        esac
    fi
fi

if [ ! -d "$FULL_WORKTREE_PATH" ]; then
    # Create the worktree atomically from base_ref
    if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        if git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" "$BRANCH_NAME" >> "$LOG_FILE" 2>&1; then
            log_msg "Created worktree with existing branch: $BRANCH_NAME"
        else
            WORKTREE_ERROR=$(git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" "$BRANCH_NAME" 2>&1 || true)
            log_msg "ERROR: Failed to add worktree with existing branch: $WORKTREE_ERROR"
            rm -f "$QUEUE_FILE"
            release_lock
            deny_with_reason "Failed to create worktree for bead $BEAD_ID: $WORKTREE_ERROR"
        fi
    else
        if git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" "$BASE_REF" >> "$LOG_FILE" 2>&1; then
            log_msg "Created worktree with new branch: $BRANCH_NAME (base_ref=$BASE_REF)"
        else
            WORKTREE_ERROR=$(git -C "$PROJECT_ROOT" worktree add "$FULL_WORKTREE_PATH" -b "$BRANCH_NAME" "$BASE_REF" 2>&1 || true)
            log_msg "ERROR: Failed to create worktree: $WORKTREE_ERROR"
            rm -f "$QUEUE_FILE"
            release_lock
            deny_with_reason "Failed to create worktree for bead $BEAD_ID: $WORKTREE_ERROR"
        fi
    fi
fi

# Release lock
release_lock

# === CREATE / UPDATE PER-BEAD SESSION FILE ===
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$SESSION_EXISTS" = "true" ]; then
    if [[ "$SESSION_SPAWN_COUNT" =~ ^[0-9]+$ ]]; then
        SPAWN_COUNT=$((SESSION_SPAWN_COUNT + 1))
    else
        SPAWN_COUNT=1
    fi

    if [ "$SPAWN_MODE" = "restart" ]; then
        NEW_STATUS="in_progress"
        NEW_ITERATION=0
    else
        NEW_STATUS=$(jq -r '.status // "in_progress"' "$SESSION_FILE")
        NEW_ITERATION=$(jq -r '.iteration // 0' "$SESSION_FILE")
    fi

    if ! [[ "$NEW_ITERATION" =~ ^[0-9]+$ ]]; then
        NEW_ITERATION=0
    fi

    NEW_CODEX_THREAD_ID="$SESSION_CODEX_THREAD_ID"
    NEW_CODEX_CALLS="$SESSION_CODEX_CALLS"
    NEW_CODEX_LAST_USED_AT=$(jq -r '.codex_last_used_at // empty' "$SESSION_FILE")

    if [ "$SPAWN_MODE" = "restart" ]; then
        NEW_CODEX_THREAD_ID=""
        NEW_CODEX_CALLS="0"
        NEW_CODEX_LAST_USED_AT=""
    fi

    if ! [[ "$NEW_CODEX_CALLS" =~ ^[0-9]+$ ]]; then
        NEW_CODEX_CALLS="0"
    fi

	    jq \
	      --arg bead_id "$BEAD_ID" \
	      --arg worktree_path "$FULL_WORKTREE_PATH" \
	      --arg branch "$BRANCH_NAME" \
	      --arg base_ref "$BASE_REF" \
	      --arg base_sha "$BASE_SHA" \
	      --arg status "$NEW_STATUS" \
	      --arg completion_promise "$COMPLETION_PROMISE" \
	      --arg updated_at "$NOW_TS" \
	      --arg last_spawned_at "$NOW_TS" \
	      --arg spawn_mode "$SPAWN_MODE" \
	      --arg last_prompt "$PROMPT" \
	      --arg iteration "$NEW_ITERATION" \
	      --arg max_iterations "$MAX_ITERATIONS" \
	      --arg spawn_count "$SPAWN_COUNT" \
	      --arg created_at "$NOW_TS" \
	      --arg original_prompt "$PROMPT" \
	      --arg codex_thread_id "$NEW_CODEX_THREAD_ID" \
	      --arg codex_last_used_at "$NEW_CODEX_LAST_USED_AT" \
	      --arg codex_calls "$NEW_CODEX_CALLS" \
	      --arg codex_model "$CODEX_MODEL" \
	      --arg codex_effort "$CODEX_EFFORT" \
	      --argjson bead_spec "$QUEUE_BEAD_SPEC" \
	      '
	        .bead_id = $bead_id
	        | .worktree_path = $worktree_path
	        | .branch = $branch
	        | .base_ref = $base_ref
	        | .base_sha = $base_sha
	        | .status = $status
	        | .iteration = ($iteration | tonumber)
	        | .max_iterations = ($max_iterations | tonumber)
	        | .completion_promise = $completion_promise
	        | .updated_at = $updated_at
	        | .last_spawned_at = $last_spawned_at
	        | .spawn_mode = $spawn_mode
	        | .spawn_count = ($spawn_count | tonumber)
	        | .last_prompt = $last_prompt
	        | .codex_thread_id = (if $codex_thread_id == "" then null else $codex_thread_id end)
	        | .codex_last_used_at = (if $codex_last_used_at == "" then null else $codex_last_used_at end)
	        | .codex_calls = ($codex_calls | tonumber)
	        | .codex = {
	            model: (if $codex_model == "" then null else $codex_model end),
	            model_reasoning_effort: (if $codex_effort == "" then null else $codex_effort end)
	          }
	        | .bead_spec = $bead_spec
	        | .created_at = (if .created_at then .created_at else $created_at end)
	        | .original_prompt = (if .original_prompt then .original_prompt else $original_prompt end)
	      ' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    log_msg "Updated session file: $SESSION_FILE"
else
	    jq -n \
	      --arg bead_id "$BEAD_ID" \
	      --arg worktree_path "$FULL_WORKTREE_PATH" \
	      --arg branch "$BRANCH_NAME" \
	      --arg base_ref "$BASE_REF" \
	      --arg base_sha "$BASE_SHA" \
	      --arg status "in_progress" \
	      --arg completion_promise "$COMPLETION_PROMISE" \
	      --arg created_at "$NOW_TS" \
	      --arg updated_at "$NOW_TS" \
	      --arg last_spawned_at "$NOW_TS" \
	      --arg spawn_mode "$SPAWN_MODE" \
	      --arg last_prompt "$PROMPT" \
	      --arg original_prompt "$PROMPT" \
	      --arg iteration "0" \
	      --arg max_iterations "$MAX_ITERATIONS" \
	      --arg spawn_count "1" \
	      --arg codex_model "$CODEX_MODEL" \
	      --arg codex_effort "$CODEX_EFFORT" \
	      --argjson bead_spec "$QUEUE_BEAD_SPEC" \
	      '{
	        bead_id: $bead_id,
	        worktree_path: $worktree_path,
	        branch: $branch,
	        base_ref: $base_ref,
	        base_sha: $base_sha,
	        status: $status,
	        iteration: ($iteration | tonumber),
	        max_iterations: ($max_iterations | tonumber),
	        completion_promise: $completion_promise,
	        created_at: $created_at,
	        updated_at: $updated_at,
	        last_spawned_at: $last_spawned_at,
	        spawn_mode: $spawn_mode,
	        spawn_count: ($spawn_count | tonumber),
	        original_prompt: $original_prompt,
	        last_prompt: $last_prompt,
	        codex_thread_id: null,
	        codex_last_used_at: null,
	        codex_calls: 0,
	        codex: {
	          model: (if $codex_model == "" then null else $codex_model end),
	          model_reasoning_effort: (if $codex_effort == "" then null else $codex_effort end)
	        },
	        bead_spec: $bead_spec
	      }' > "$SESSION_FILE"

    log_msg "Created session file: $SESSION_FILE"
fi

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

# Artifacts symlink for verifier screenshots/logs
ARTIFACTS_DIR="$STATE_DIR/artifacts"
mkdir -p "$ARTIFACTS_DIR"
if [ -L "$WORKTREE_STATE_DIR/artifacts" ]; then
    rm -f "$WORKTREE_STATE_DIR/artifacts"
fi
ln -sf "$ARTIFACTS_DIR" "$WORKTREE_STATE_DIR/artifacts"
log_msg "Created symlink: $WORKTREE_STATE_DIR/artifacts -> $ARTIFACTS_DIR"

# === CLEANUP SPAWN QUEUE FILE ===
rm -f "$QUEUE_FILE"
log_msg "Removed queue file: $QUEUE_FILE"

# === BUILD ENHANCED PROMPT WITH WORKTREE CONTEXT ===
# IMPORTANT: Prepend to existing prompt, do not replace
WORKTREE_CONTEXT="## Worktree Environment

You are running in an isolated git worktree at: $FULL_WORKTREE_PATH
Branch: $BRANCH_NAME
Bead ID: $BEAD_ID
Session file: $SESSION_FILE
Max iterations: $MAX_ITERATIONS
Base ref: $BASE_REF ($BASE_SHA)
Spawn mode: $SPAWN_MODE

CRITICAL: All your file operations should be relative to this worktree.
Run 'cd $FULL_WORKTREE_PATH' before doing any work.
Verify with 'pwd' and 'git branch --show-current'.

---

"

# Combine: Worktree Context + Original Prompt
ENHANCED_PROMPT="${WORKTREE_CONTEXT}${PROMPT}"

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

log_msg "SUCCESS: Worktree setup complete for $BEAD_ID"
