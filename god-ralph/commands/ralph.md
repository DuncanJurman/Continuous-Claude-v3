---
description: Execute beads with god-ralph workers delegated to Codex via MCP
---

# /god-ralph:ralph

Main-thread orchestrator for parallel bead execution using god-ralph workers and Codex delegation. Do NOT spawn the orchestrator as a subagent.

## Subcommands

| Command | Description |
|---------|-------------|
| `/god-ralph:ralph` | Show current execution status |
| `/god-ralph:ralph start [--parallelism N] [--dry-run] [--filter PATTERN]` | Start orchestrator |
| `/god-ralph:ralph <bead-id>` | Run a single bead |
| `/god-ralph:ralph stop` | Stop gracefully |
| `/god-ralph:ralph resume` | Resume from existing state |
| `/god-ralph:ralph health` | Health check |
| `/god-ralph:ralph gc` | Clean orphaned worktrees |
| `/god-ralph:ralph recover <bead-id>` | Repair a specific bead |
| `/god-ralph:ralph unlock [--force]` | Clear stale locks |

## Orchestrator invariants

- Runs in main thread.
- Never edits code in bead worktrees.
- Uses queue files + Task to spawn `god-ralph-worker`.
- Serializes rebase → verify → merge with a merge lock.

## Spawn flow

1. Claim bead: `bd update <bead_id> --status in_progress`
2. Write queue file: `.claude/state/god-ralph/queue/<bead_id>.json`
3. Spawn worker:

```
Task(
  subagent_type="god-ralph-worker",
  description="God-Ralph worker for <bead-id>",
  prompt="""
BEAD_ID: <bead-id>
WORKTREE_PATH: .worktrees/ralph-<bead-id>
SESSION_FILE: .claude/state/god-ralph/sessions/<bead-id>.json

## Bead Spec
<bd show <bead-id> --json>

## Instructions
Complete this bead. Use Codex MCP to implement changes in the worktree.
Signal completion with: <promise>BEAD COMPLETE</promise>
"""
)
```

## Integration (rebase → verify → merge)

When a session is `worker_complete`:

1. Acquire merge lock (`.claude/state/god-ralph/locks/merge.lock`).
2. Sync main:
   - `git fetch origin main`
   - `git checkout main`
   - `git merge --ff-only origin/main`
3. Rebase bead branch:
   - `git checkout ralph/<bead-id>`
   - `git rebase main`
4. If any UI criteria target Vercel preview, push rebased branch:
   - `git push origin ralph/<bead-id> --force-with-lease`
5. Spawn verifier:

```
Task(
  subagent_type="god-ralph-verifier",
  description="Verify bead <bead-id>",
  prompt="""
BEAD_ID: <bead-id>
WORKTREE_PATH: <absolute worktree path>
SESSION_FILE: <absolute session path>
ARTIFACT_ROOT: <project>/.claude/state/god-ralph/artifacts

Acceptance criteria:
<criteria list>
"""
)
```

6. On verification pass:
   - Mark session `verified_passed`.
   - `git checkout main`
   - `git merge --ff-only ralph/<bead-id>`
   - `git push origin main` (required default).
   - `bd close <bead-id>`.
   - Mark session `merged` and clean worktree.
7. On verification fail:
   - Mark session `verified_failed`.
   - Add bead comment with failure summary + artifact paths.
   - Re-queue with `spawn_mode=resume` (escalate to `restart` after N failures).

## Health check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/ralph-health-check.sh` and surface issues.

## Notes

- Codex autonomy is enforced by plugin hooks: `sandbox=danger-full-access`, `approval-policy=never`, and `cwd` rewritten to the bead worktree.
- UI criteria must produce screenshots under `.claude/state/god-ralph/artifacts/<bead_id>/ui/` when passing.
