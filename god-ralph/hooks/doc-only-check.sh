#!/usr/bin/env bash
# Ensure scribe only edits/writes .md files
# Per ClaudeDocs: JSON is only processed on exit 0; use permissionDecisionReason (not reason)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Check if file is NOT a markdown file AND NOT a CLAUDE.* file
# Regex: ^CLAUDE\. matches CLAUDE.md, CLAUDE.local.md, etc. but not arbitrary files containing "CLAUDE"
if [[ -n "$FILE_PATH" ]] && [[ ! "$FILE_PATH" =~ \.md$ ]] && [[ ! "$FILE_PATH" =~ (^|/)CLAUDE\. ]]; then
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Scribe can only edit/write documentation files (.md, CLAUDE.md). Attempted: $FILE_PATH"
  }
}
EOF
    exit 0
fi

echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
