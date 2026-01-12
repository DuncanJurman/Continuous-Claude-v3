---
description: Show current god-ralph execution progress, active Ralphs, and costs
---

# /god-ralph status

Display current execution status, active Ralphs, and progress metrics.

## Output

Read and display the orchestrator state:

```bash
# Check if orchestrator is running
if [[ -f ".claude/god-ralph/orchestrator-state.json" ]]; then
  cat .claude/god-ralph/orchestrator-state.json | jq '.'
else
  echo "No active god-ralph session"
fi
```

## Display Format

```
📊 god-ralph Status
━━━━━━━━━━━━━━━━━━

Status: running
Started: 2024-01-10 14:30:00 (45 minutes ago)

Active Ralphs:
┌─────────────┬────────────┬───────────────┬──────────┐
│ Bead ID     │ Iteration  │ Worktree      │ Status   │
├─────────────┼────────────┼───────────────┼──────────┤
│ beads-abc   │ 12/50      │ .worktrees/1  │ working  │
│ beads-def   │ 8/50       │ .worktrees/2  │ tests    │
│ beads-ghi   │ 3/50       │ .worktrees/3  │ starting │
└─────────────┴────────────┴───────────────┴──────────┘

Progress:
  Completed: 5 beads
  Failed: 1 bead (beads-xyz: max iterations)
  Remaining: 8 beads

Metrics:
  Total iterations: 156
  Estimated cost: $23.40
  Avg iterations/bead: 12.3

Recent Activity:
  [14:42] beads-mno completed (8 iterations)
  [14:40] beads-jkl merged successfully
  [14:38] Verification passed for beads-jkl
  [14:35] beads-xyz failed (max iterations reached)
```

## Live Logs

To see live streaming output:

```bash
# Tail the current log file
tail -f .claude/god-ralph/logs/orchestrator.log
```

## Bead-Specific Status

Check status of a specific bead:

```bash
# Show Ralph session for specific bead
if [[ -f ".worktrees/ralph-beads-abc/.claude/god-ralph/sessions/beads-abc.json" ]]; then
  cat ".worktrees/ralph-beads-abc/.claude/god-ralph/sessions/beads-abc.json" | jq '.'
fi
```

## Arguments

- `--json`: Output raw JSON for scripting
- `--live`: Continuously update (like watch)
- `--bead <id>`: Show status for specific bead only
