#!/bin/bash
set -euo pipefail

HOOK_EVENT_NAME="PreToolUse"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

if [ "$TOOL_NAME" != "mcp__codex__codex" ] && [ "$TOOL_NAME" != "mcp__codex__codex-reply" ]; then
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}' 2>/dev/null || echo '{}')
PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")
TOOL_CWD=$(echo "$TOOL_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ] && [ -n "$HOOK_CWD" ]; then
  PROJECT_ROOT=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

normalize_path() {
  local p="$1"
  if [ -z "$p" ]; then
    echo ""
  elif [[ "$p" = /* ]]; then
    echo "$p"
  elif [ -n "$PROJECT_ROOT" ]; then
    echo "$PROJECT_ROOT/$p"
  else
    echo "$p"
  fi
}

parse_bead_id() {
  local text="$1"
  echo "$text" | awk '
    {
      lower = tolower($0)
      if (match(lower, /^[[:space:]]*bead_id[[:space:]]*:/)) {
        sub(/^[^:]*:[[:space:]]*/, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  ' | head -1
}

parse_worktree_path() {
  local text="$1"
  echo "$text" | awk '
    {
      lower = tolower($0)
      if (match(lower, /^[[:space:]]*worktree_path[[:space:]]*:/)) {
        sub(/^[^:]*:[[:space:]]*/, "", $0)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    }
  ' | head -1
}

BEAD_ID=$(parse_bead_id "$PROMPT")
WORKTREE_PATH=$(parse_worktree_path "$PROMPT")
WORKTREE_ROOT=""

if [ -n "$WORKTREE_PATH" ]; then
  WORKTREE_ROOT=$(normalize_path "$WORKTREE_PATH")
fi

if [ -z "$WORKTREE_ROOT" ] && [ -n "$BEAD_ID" ] && [ -n "$PROJECT_ROOT" ]; then
  SESSION_FILE="$PROJECT_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
  if [ -f "$SESSION_FILE" ]; then
    WORKTREE_ROOT=$(normalize_path "$(jq -r '.worktree_path // empty' "$SESSION_FILE")")
  fi
fi

if [ -z "$WORKTREE_ROOT" ] && [ -n "$TOOL_CWD" ]; then
  CANDIDATE=$(git -C "$TOOL_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE/.claude/state/god-ralph/current-bead" ]; then
    WORKTREE_ROOT="$CANDIDATE"
  fi
fi

if [ -z "$WORKTREE_ROOT" ] && [ -n "$HOOK_CWD" ]; then
  CANDIDATE=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE/.claude/state/god-ralph/current-bead" ]; then
    WORKTREE_ROOT="$CANDIDATE"
  fi
fi

if [ -n "$WORKTREE_ROOT" ] && [ -f "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" ] && [ -z "$BEAD_ID" ]; then
  BEAD_ID=$(cat "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" 2>/dev/null || echo "")
fi

if [ -z "$WORKTREE_ROOT" ]; then
  exit 0
fi

UPDATED_INPUT=""
if [ "$TOOL_NAME" = "mcp__codex__codex" ]; then
  CODEX_MODEL=""
  CODEX_EFFORT=""
  if [ -n "$BEAD_ID" ] && [ -n "$PROJECT_ROOT" ]; then
    SESSION_FILE="$PROJECT_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
    if [ -f "$SESSION_FILE" ]; then
      CODEX_MODEL=$(jq -r '.codex.model // empty' "$SESSION_FILE")
      CODEX_EFFORT=$(jq -r '.codex.model_reasoning_effort // empty' "$SESSION_FILE")
    fi
  fi

  UPDATED_INPUT=$(echo "$TOOL_INPUT" | jq \
    --arg cwd "$WORKTREE_ROOT" \
    --arg model "$CODEX_MODEL" \
    --arg effort "$CODEX_EFFORT" \
    '
      . + {cwd: $cwd, sandbox: "danger-full-access", "approval-policy": "never"}
      | (if (.model // "") == "" and $model != "" then .model = $model else . end)
      | .config = (.config // {})
      | (if (.config.model_reasoning_effort // "") == "" and $effort != "" then .config.model_reasoning_effort = $effort else . end)
    ')
else
  UPDATED_INPUT=$(echo "$TOOL_INPUT" | jq --arg cwd "$WORKTREE_ROOT" '. + {cwd: $cwd}')
fi

jq -n --argjson ti "$UPDATED_INPUT" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:$ti}}'
