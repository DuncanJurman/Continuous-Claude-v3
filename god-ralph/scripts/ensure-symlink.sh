#!/bin/bash
# ensure-symlink.sh
# Ensures AGENTS.md exists as a symlink to CLAUDE.md
# Called by scribe agent's Stop hook

# Run in project root (where CLAUDE.md should be)
cd "${PROJECT_ROOT:-.}" 2>/dev/null || true

if [ -f CLAUDE.md ] && [ ! -e AGENTS.md ]; then
  ln -s CLAUDE.md AGENTS.md
  echo "[scribe] Created AGENTS.md -> CLAUDE.md symlink"
elif [ -f CLAUDE.md ] && [ -L AGENTS.md ]; then
  # Symlink exists, verify it points to CLAUDE.md
  target=$(readlink AGENTS.md)
  if [ "$target" = "CLAUDE.md" ]; then
    echo "[scribe] AGENTS.md symlink already exists"
  else
    echo "[scribe] Warning: AGENTS.md exists but points to $target, not CLAUDE.md"
  fi
elif [ -f CLAUDE.md ] && [ -f AGENTS.md ] && [ ! -L AGENTS.md ]; then
  echo "[scribe] Warning: AGENTS.md exists as regular file, not symlink"
  echo "[scribe] Consider: rm AGENTS.md && ln -s CLAUDE.md AGENTS.md"
elif [ ! -f CLAUDE.md ]; then
  echo "[scribe] CLAUDE.md not found - scribe should create it first"
fi
