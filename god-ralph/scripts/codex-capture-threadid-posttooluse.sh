#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
if [ "$TOOL_NAME" != "mcp__codex__codex" ]; then
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}' 2>/dev/null || echo '{}')
PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")
TOOL_CWD=$(echo "$TOOL_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

THREAD_ID=$(echo "$INPUT" | jq -r '
  .tool_response.structuredContent.threadId //
  .tool_output.structuredContent.threadId //
  .tool_result.structuredContent.threadId //
  empty
' 2>/dev/null || echo "")

if [ -z "$THREAD_ID" ]; then
  TEXT_PAYLOAD=$(echo "$INPUT" | jq -r '.tool_response.content[0].text // empty' 2>/dev/null || echo "")
  if [ -n "$TEXT_PAYLOAD" ]; then
    THREAD_ID=$(echo "$TEXT_PAYLOAD" | jq -r '.threadId // empty' 2>/dev/null || echo "")
  fi
fi

if [ -z "$THREAD_ID" ]; then
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ] && [ -n "$HOOK_CWD" ]; then
  PROJECT_ROOT=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

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

BEAD_ID=$(parse_bead_id "$PROMPT")
SESSION_FILE=""

if [ -n "$TOOL_CWD" ]; then
  WORKTREE_ROOT=$(git -C "$TOOL_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$WORKTREE_ROOT" ] && [ -f "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" ]; then
    if [ -z "$BEAD_ID" ]; then
      BEAD_ID=$(cat "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" 2>/dev/null || echo "")
    fi
    SESSION_FILE="$WORKTREE_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
  fi
fi

if [ -z "$SESSION_FILE" ] && [ -n "$HOOK_CWD" ]; then
  WORKTREE_ROOT=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$WORKTREE_ROOT" ] && [ -f "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" ]; then
    if [ -z "$BEAD_ID" ]; then
      BEAD_ID=$(cat "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" 2>/dev/null || echo "")
    fi
    SESSION_FILE="$WORKTREE_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
  fi
fi

if [ -z "$SESSION_FILE" ] && [ -n "$BEAD_ID" ] && [ -n "$PROJECT_ROOT" ]; then
  SESSION_FILE="$PROJECT_ROOT/.claude/state/god-ralph/sessions/$BEAD_ID.json"
fi

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

CURRENT_CALLS=$(jq -r '.codex_calls // 0' "$SESSION_FILE")
if ! [[ "$CURRENT_CALLS" =~ ^[0-9]+$ ]]; then
  CURRENT_CALLS=0
fi
NEW_CALLS=$((CURRENT_CALLS + 1))
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq \
  --arg thread_id "$THREAD_ID" \
  --arg now "$NOW_TS" \
  --argjson calls "$NEW_CALLS" \
  '.codex_thread_id = $thread_id
   | .codex_last_used_at = $now
   | .codex_calls = $calls
  ' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
