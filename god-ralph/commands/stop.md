---
description: Gracefully stop the god-ralph orchestrator and all active Ralphs
---

# /god-ralph stop

Gracefully stop the god-ralph orchestrator and all active Ralph workers.

## Behavior

1. Signal orchestrator to stop accepting new work
2. Wait for active Ralphs to reach safe stopping point
3. Commit and save progress for each Ralph
4. Clean up worktrees
5. Update state file

## Execution

```bash
# Signal stop
if [[ -f ".claude/god-ralph/orchestrator-state.json" ]]; then
  # Update state to stopping
  jq '.status = "stopping"' .claude/god-ralph/orchestrator-state.json > .claude/god-ralph/orchestrator-state.json.tmp
  mv .claude/god-ralph/orchestrator-state.json.tmp .claude/god-ralph/orchestrator-state.json

  echo "[god-ralph] Stopping orchestrator..."
  echo "[god-ralph] Active Ralphs will complete current iteration before stopping"
else
  echo "[god-ralph] No active session to stop"
fi
```

## Graceful Shutdown

Each active Ralph:
1. Completes current iteration
2. Commits any uncommitted changes
3. Saves progress to bead comments

```bash
# For each active Ralph worktree
for worktree in .worktrees/ralph-*; do
  if [[ -d "$worktree" ]]; then
    cd "$worktree"

    # Commit any pending changes
    git add -A
    git commit -m "WIP: Stopped by user" || true

    # Note progress in bead
    BEAD_ID=$(basename "$worktree" | sed 's/ralph-//')
    SESSION_FILE=".claude/god-ralph/sessions/$BEAD_ID.json"
    if [[ -f "$SESSION_FILE" ]]; then
      ITERATION=$(jq -r '.iteration' "$SESSION_FILE")
    else
      ITERATION="unknown"
    fi
    bd comments "$BEAD_ID" --add "Stopped at iteration $ITERATION. Branch: ralph/$BEAD_ID"

    cd -
  fi
done
```

## Force Stop

If graceful stop doesn't work:

```bash
# Force remove all state
rm -f .claude/god-ralph/orchestrator-state.json
rm -rf .claude/god-ralph/sessions
rm -rf .claude/god-ralph/spawn-queue

# Clean up worktrees
git worktree list | grep ralph | awk '{print $1}' | xargs -I {} git worktree remove {} --force

# Remove worktree branches
git branch | grep ralph/ | xargs -I {} git branch -D {}
```

## Arguments

- `--force`: Force immediate stop without waiting for safe point
- `--keep-worktrees`: Don't clean up worktrees (for debugging)

## Output

```
[god-ralph] Stopping orchestrator...
[god-ralph] Waiting for 3 active Ralphs to reach safe point...
[god-ralph] Ralph beads-abc: saving progress at iteration 12
[god-ralph] Ralph beads-def: saving progress at iteration 8
[god-ralph] Ralph beads-ghi: saving progress at iteration 3
[god-ralph] Cleaning up worktrees...
[god-ralph] Orchestrator stopped

Summary:
  - Session duration: 45 minutes
  - Completed beads: 5
  - Stopped in progress: 3
  - Total iterations: 156
  - Estimated cost: $23.40

To resume: /god-ralph start
```

## Resume After Stop

Work is preserved:
- Completed beads are closed
- In-progress beads remain open with progress in comments
- Feature branches preserved (unless --force used)

Run `/god-ralph start` to resume execution.
