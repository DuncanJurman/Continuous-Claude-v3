#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

STATE_DIR="$PROJECT_ROOT/.claude/state/god-ralph"
QUEUE_DIR="$STATE_DIR/queue"
SESSIONS_DIR="$STATE_DIR/sessions"
LOGS_DIR="$STATE_DIR/logs"
LOCKS_DIR="$STATE_DIR/locks"
ARTIFACTS_DIR="$STATE_DIR/artifacts"

mkdir -p "$QUEUE_DIR" "$SESSIONS_DIR" "$LOGS_DIR" "$LOCKS_DIR" "$ARTIFACTS_DIR" >/dev/null 2>&1 || true

echo "Ralph Health Check"
echo "=================="
echo ""

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[OK] $name available"
  else
    echo "[FAIL] $name not found"
  fi
}

check_cmd git
check_cmd jq
check_cmd bd
check_cmd codex

if command -v codex >/dev/null 2>&1; then
  if codex --version >/dev/null 2>&1; then
    echo "[OK] codex --version"
  else
    echo "[FAIL] codex --version failed"
  fi

  if codex login status >/dev/null 2>&1; then
    echo "[OK] codex login status"
  else
    echo "[WARN] codex login status failed (authenticate with codex login)"
  fi
fi

echo ""

if git worktree list >/dev/null 2>&1; then
  echo "[OK] git worktree support"
else
  echo "[FAIL] git worktree support"
fi

if git remote get-url origin >/dev/null 2>&1; then
  echo "[OK] origin remote present"
else
  echo "[FAIL] origin remote missing"
fi

if git push --dry-run origin main >/dev/null 2>&1; then
  echo "[OK] git push --dry-run origin main"
else
  echo "[WARN] git push --dry-run origin main failed"
fi

echo ""

HAS_UI=false
if rg -n '"type"\s*:\s*"ui"|type:\s*ui' "$QUEUE_DIR" "$SESSIONS_DIR" 2>/dev/null | head -1 >/dev/null; then
  HAS_UI=true
fi

if [ "$HAS_UI" = "true" ]; then
  if command -v npx >/dev/null 2>&1; then
    echo "[OK] npx available for Playwright MCP"
  else
    echo "[WARN] npx not found (Playwright MCP may be unavailable)"
  fi
fi

HAS_VERCEL_TARGET=false
if rg -n 'vercel_preview|vercel_production' "$QUEUE_DIR" "$SESSIONS_DIR" 2>/dev/null | head -1 >/dev/null; then
  HAS_VERCEL_TARGET=true
fi

if [ "$HAS_VERCEL_TARGET" = "true" ]; then
  if [ -n "${VERCEL_TOKEN:-}" ]; then
    echo "[OK] VERCEL_TOKEN present"
  else
    echo "[WARN] VERCEL_TOKEN missing"
  fi

  if [ -f "$PROJECT_ROOT/.vercel/project.json" ]; then
    echo "[OK] .vercel/project.json present"
  else
    if [ -n "${VERCEL_PROJECT_ID:-}" ]; then
      echo "[OK] VERCEL_PROJECT_ID present"
    else
      echo "[WARN] Missing .vercel/project.json and VERCEL_PROJECT_ID"
    fi
  fi
fi

echo ""
echo "State dirs:"
echo "  $QUEUE_DIR"
echo "  $SESSIONS_DIR"
echo "  $LOGS_DIR"
echo "  $LOCKS_DIR"
echo "  $ARTIFACTS_DIR"

echo ""
echo "Worktrees:"
for wt in "$PROJECT_ROOT"/.worktrees/ralph-*; do
  [ -d "$wt" ] || continue
  BRANCH=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  DIRTY=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  STATUS="clean"
  if [ "$DIRTY" -ne 0 ]; then
    STATUS="dirty"
  fi
  echo "  $wt  branch:$BRANCH  status:$STATUS"
done

echo ""
echo "Manual checks:"
echo "- Ensure MCP server 'codex' appears in /mcp tools"
