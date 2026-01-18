#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}' 2>/dev/null || echo '{}')
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

if [ -z "$HOOK_CWD" ]; then
  exit 0
fi

WORKTREE_ROOT=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$WORKTREE_ROOT" ]; then
  exit 0
fi

if [ ! -f "$WORKTREE_ROOT/.claude/state/god-ralph/current-bead" ]; then
  exit 0
fi

UPDATED_INPUT=$(echo "$TOOL_INPUT" | jq --arg cwd "$WORKTREE_ROOT" '. + {cwd: $cwd}')

jq -n --argjson ti "$UPDATED_INPUT" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:$ti}}'
