#!/usr/bin/env bash
# bd command wrappers with error handling
# Source this file to use: source .claude/scripts/bd-utils.sh

bd_ready() {
  local output
  if ! output=$(bd ready --no-daemon --json 2>&1); then
    echo "ERROR: bd ready failed: $output" >&2
    return 1
  fi
  echo "$output"
}

bd_claim() {
  local bead_id="$1"
  if [ -z "$bead_id" ]; then
    echo "ERROR: bd_claim requires bead_id" >&2
    return 1
  fi
  if ! bd update "$bead_id" --status=in_progress --no-daemon 2>&1; then
    echo "ERROR: Failed to claim bead $bead_id" >&2
    return 1
  fi
}

bd_close() {
  local bead_id="$1"
  if [ -z "$bead_id" ]; then
    echo "ERROR: bd_close requires bead_id" >&2
    return 1
  fi
  if ! bd close "$bead_id" --no-daemon 2>&1; then
    echo "ERROR: Failed to close bead $bead_id" >&2
    return 1
  fi
}

bd_release() {
  local bead_id="$1"
  if [ -z "$bead_id" ]; then
    echo "ERROR: bd_release requires bead_id" >&2
    return 1
  fi
  if ! bd update "$bead_id" --status=open --no-daemon 2>&1; then
    echo "ERROR: Failed to release bead $bead_id" >&2
    return 1
  fi
}

bd_get_spec() {
  local bead_id="$1"
  if [ -z "$bead_id" ]; then
    echo "ERROR: bd_get_spec requires bead_id" >&2
    return 1
  fi
  bd show "$bead_id" --json --no-daemon 2>/dev/null
}

bd_add_comment() {
  local bead_id="$1"
  local comment="$2"
  if [ -z "$bead_id" ] || [ -z "$comment" ]; then
    echo "ERROR: bd_add_comment requires bead_id and comment" >&2
    return 1
  fi
  if ! bd comments "$bead_id" --add "$comment" --no-daemon 2>&1; then
    echo "ERROR: Failed to add comment to bead $bead_id" >&2
    return 1
  fi
}
