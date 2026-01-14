#!/usr/bin/env bash
# ensure-symlink.sh
# Ensures AGENTS.md exists as a symlink to CLAUDE.md
# Called by ralph-learner Stop hook

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-.}}"
cd "$PROJECT_ROOT" 2>/dev/null || true

if [ -f CLAUDE.md ] && [ ! -e AGENTS.md ]; then
  ln -s CLAUDE.md AGENTS.md
  echo "[ralph-learner] Created AGENTS.md -> CLAUDE.md symlink"
elif [ -f CLAUDE.md ] && [ -L AGENTS.md ]; then
  # Symlink exists, verify it points to CLAUDE.md
  target=$(readlink AGENTS.md)
  if [ "$target" = "CLAUDE.md" ]; then
    echo "[ralph-learner] AGENTS.md symlink already exists"
  else
    echo "[ralph-learner] Warning: AGENTS.md exists but points to $target, not CLAUDE.md"
  fi
elif [ -f CLAUDE.md ] && [ -f AGENTS.md ] && [ ! -L AGENTS.md ]; then
  echo "[ralph-learner] Warning: AGENTS.md exists as regular file, not symlink"
  echo "[ralph-learner] Consider: rm AGENTS.md && ln -s CLAUDE.md AGENTS.md"
elif [ ! -f CLAUDE.md ]; then
  echo "[ralph-learner] CLAUDE.md not found - ralph-learner should create it first"
fi
