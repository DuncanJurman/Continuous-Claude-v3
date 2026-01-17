---
description: Execute beads with parallel Ralph workers
---

# /ralph - Bead Execution with Ralph Workers

Orchestrates parallel Ralph worker agents to execute beads from the `.beads/` directory. Each worker operates in an isolated git worktree with its own branch.

**Important:** Run this in the main thread. Do NOT spawn the orchestrator subagent (subagents cannot spawn subagents).

## Subcommands

| Command | Description |
|---------|-------------|
| `/ralph` | Show current execution status |
| `/ralph start` | Start orchestrator (dry-run first) |
| `/ralph <bead-id>` | Run single Ralph worker for specific bead |
| `/ralph stop` | Stop gracefully (let workers finish) |
| `/ralph resume` | Resume from existing state + worktrees |
| `/ralph health` | Full system health check |
| `/ralph gc` | Garbage collect stale worktrees |
| `/ralph recover <bead-id>` | Recover a specific bead from failed state |
| `/ralph unlock [--force]` | Clear stale orchestrator lock |

## Usage

### Show Status (`/ralph`)

Display current orchestrator state:
- Active workers and their beads
- Worktree status
- Recent completions/failures

```
/ralph
```

Output:
```
Ralph Orchestrator Status
========================
State: running
Active Workers: 2/4
Queue: 3 beads ready

Workers:
  - ralph-auth-001: in_progress (iteration 3/50)
  - ralph-db-002: in_progress (iteration 1/50)

Recent:
  - ralph-api-003: WORKER_COMPLETE (4 iterations)
  - ralph-ui-001: VERIFIED_FAILED (blocked: missing dependency)
```

### Start Orchestrator (`/ralph start`)

Begin bead execution with dry-run safety:

```bash
# Dry run first (always recommended)
/ralph start --dry-run

# Actually start
/ralph start
```

Options:
- `--dry-run`: Show what would happen without executing
- `--parallelism N`: Max concurrent workers (default: 4)
- `--filter <pattern>`: Only process beads matching pattern

### Run Single Bead (`/ralph <bead-id>`)

Execute a specific bead manually:

```bash
/ralph auth-001
```

This:
1. Claims the bead (`bd update --status=in_progress`)
2. Writes queue file (required) with base_ref/spawn_mode
3. Spawns ralph-worker agent (ensure-worktree creates worktree + branch)
4. Monitors until completion or failure

### Stop Gracefully (`/ralph stop`)

Stop accepting new work, let active workers finish:

```bash
/ralph stop
```

Workers in progress will complete their current iteration cycle.

### Resume (`/ralph resume`)

Resume from existing state and any active worktrees:

```bash
/ralph resume
```

Resume should write queue files with `spawn_mode=resume` (or `repair` if the worktree is missing).

### Recover (`/ralph recover <bead-id>`)

Recover a specific bead from a failed or stuck state:

```bash
/ralph recover beads-123
```

Recover should respawn with `spawn_mode=restart` to reset the loop state.

### Unlock (`/ralph unlock [--force]`)

Clear a stale orchestrator lock if an earlier run crashed:

```bash
/ralph unlock
```

### Health Check (`/ralph health`)

Full system health check:

```bash
/ralph health
```

Output format:
```
Ralph System Health
==================

[OK] bd CLI available
[OK] .beads/ directory exists
[OK] PostgreSQL connection
[OK] Git worktrees functional

Worktrees:
  .worktrees/ralph-auth-001/  branch:ralph/auth-001  status:clean
  .worktrees/ralph-db-002/    branch:ralph/db-002    status:dirty

Beads:
  Ready: 5
  In Progress: 2
  Blocked: 1
  Completed: 12

Worker Agents:
  ralph-worker.md: present
  verification-ralph.md: present

Hooks (installed):
  ralph-stop-hook.sh: executable
  ensure-worktree.sh: executable
  ralph-doc-only-check.sh: executable
  settings.json: present

Overall: HEALTHY
```

### Garbage Collect (`/ralph gc`)

Clean up stale worktrees from completed/failed beads:

```bash
# Dry run
/ralph gc --dry-run

# Actually clean
/ralph gc
```

This removes:
- Worktrees for completed beads
- Worktrees for beads that failed permanently
- Orphaned worktrees with no corresponding bead

## Implementation

### Starting the Orchestrator

When `/ralph start` is invoked:

```bash
# 1. Verify prerequisites
bd list > /dev/null || { echo "bd CLI not available"; exit 1; }

# 2. Check for ready beads
READY_BEADS=$(bd ready --json | jq -r '.[].id')
if [ -z "$READY_BEADS" ]; then
  echo "No beads ready for execution"
  exit 0
fi

# 3. For each ready bead (up to parallelism limit):
for BEAD_ID in $READY_BEADS; do
  # Claim bead so other orchestrators don't pick it up
  bd update "$BEAD_ID" --status=in_progress

  # Write queue file for ensure-worktree hook
  mkdir -p .claude/state/god-ralph/queue
  cat > ".claude/state/god-ralph/queue/${BEAD_ID}.json" << EOF
{
  "worktree_path": ".worktrees/ralph-${BEAD_ID}",
  "worktree_policy": "required",
  "base_ref": "main",
  "max_iterations": 50,
  "completion_promise": "BEAD COMPLETE",
  "spawn_mode": "new"
}
EOF

  # Spawn ralph-worker agent in that worktree
  # (Worker uses stop hook for iteration control)
done
```

Queue file fields (required):
- `base_ref`: branch to rebase onto and audit (`main` by default)
- `spawn_mode`: `new` | `resume` | `restart` | `repair`

### Running a Single Bead

When `/ralph <bead-id>` is invoked:

Write the queue file first (required by ensure-worktree), then spawn the worker:

```
Task(
  subagent_type="ralph-worker",
  model="opus",
  prompt="
BEAD_ID: <bead-id>

## Bead Specification
$(bd show <bead-id> --json)

## Instructions
Complete this bead following TDD workflow.
Signal completion with: <promise>BEAD COMPLETE</promise>
"
)
```

### Health Check Implementation

```bash
#!/bin/bash
# /ralph health

echo "Ralph System Health"
echo "=================="
echo ""

# Check bd CLI
if command -v bd &> /dev/null; then
  echo "[OK] bd CLI available"
else
  echo "[FAIL] bd CLI not found"
fi

# Check .beads directory
if [ -d ".beads" ]; then
  echo "[OK] .beads/ directory exists"
else
  echo "[FAIL] .beads/ directory missing"
fi

# Check PostgreSQL (for cross-session coordination)
if docker exec continuous-claude-postgres pg_isready -q 2>/dev/null; then
  echo "[OK] PostgreSQL connection"
else
  echo "[WARN] PostgreSQL not available (optional)"
fi

# Check git worktree support
if git worktree list &> /dev/null; then
  echo "[OK] Git worktrees functional"
else
  echo "[FAIL] Git worktrees not working"
fi

echo ""
echo "Worktrees:"
for wt in .worktrees/ralph-*/; do
  if [ -d "$wt" ]; then
    BRANCH=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    STATUS=$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')
    if [ "$STATUS" -eq 0 ]; then
      STATUS="clean"
    else
      STATUS="dirty"
    fi
    echo "  $wt  branch:$BRANCH  status:$STATUS"
  fi
done

echo ""
echo "Beads:"
echo "  Ready: $(bd ready 2>/dev/null | wc -l | tr -d ' ')"
echo "  In Progress: $(bd list --status=in_progress 2>/dev/null | wc -l | tr -d ' ')"
echo "  Blocked: $(bd blocked 2>/dev/null | wc -l | tr -d ' ')"
echo "  Completed: $(bd list --status=completed 2>/dev/null | wc -l | tr -d ' ')"

echo ""
echo "Worker Agents:"
[ -f ".claude/agents/ralph-worker.md" ] && echo "  ralph-worker.md: present" || echo "  ralph-worker.md: MISSING"
[ -f ".claude/agents/verification-ralph.md" ] && echo "  verification-ralph.md: present" || echo "  verification-ralph.md: MISSING"

echo ""
echo "Hooks (installed):"
[ -x "$HOME/.claude/hooks/ralph-stop-hook.sh" ] && echo "  ralph-stop-hook.sh: executable" || echo "  ralph-stop-hook.sh: MISSING or not executable"
[ -x "$HOME/.claude/hooks/ensure-worktree.sh" ] && echo "  ensure-worktree.sh: executable" || echo "  ensure-worktree.sh: MISSING or not executable"
[ -x "$HOME/.claude/hooks/ralph-doc-only-check.sh" ] && echo "  ralph-doc-only-check.sh: executable" || echo "  ralph-doc-only-check.sh: MISSING or not executable"
[ -f "$HOME/.claude/settings.json" ] && echo "  settings.json: present" || echo "  settings.json: MISSING"

echo ""
echo "Overall: HEALTHY"
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "bd CLI not available" | bd not installed | Run setup or add to PATH |
| "No beads ready" | All beads blocked or completed | Check `bd blocked` for issues |
| "Worktree already exists" | Previous run not cleaned | Run `/ralph gc` |
| "Branch already exists" | Stale branch from old run | Delete branch or use different ID |

## Integration with bd CLI

The `/ralph` command works with the `bd` CLI for bead management:

```bash
# See what's available
bd ready

# Check specific bead
bd show <bead-id>

# After ralph completes, check results
bd list --status=completed
```

## Worktree Lifecycle

1. **Creation**: `/ralph start` or `/ralph <bead-id>` writes queue + spawns worktree
2. **Execution**: Ralph worker operates in isolated worktree
3. **Rebase + Verify**: Orchestrator rebases onto main and runs verification
4. **Completion**: Verified branch merges (ff-only) and bead closes
5. **Cleanup**: `/ralph gc` removes worktree after successful merge

## See Also

- `/decompose` - Create beads from plans
- `bd` CLI - Bead management
- `.claude/agents/ralph-worker.md` - Worker agent definition
