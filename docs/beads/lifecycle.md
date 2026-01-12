# Bead Lifecycle

## State Model

A bead progresses through discrete states that represent its position in the work pipeline. Understanding these states is critical for effective memory management and work coordination.

## States

### 1. Open (Initial State)
**Meaning:** Issue has been created but work has not started.

**Characteristics:**
- Newly created issues start here
- Available for assignment
- May have dependencies (blockers)
- Visible in `bd list --status=open`

**Valid Transitions:**
- → `in_progress` (work begins)
- → `closed` (cancelled or determined unnecessary)

**Commands:**
```bash
bd create --title="Task name" --type=task --priority=2
bd list --status=open
```

### 2. In Progress (Active Work)
**Meaning:** An agent or human is actively working on this issue.

**Characteristics:**
- Indicates current focus area
- Should have assignee
- One agent should work on one issue at a time
- Visible in `bd list --status=in_progress`

**Valid Transitions:**
- → `blocked` (dependency or external blocker discovered)
- → `closed` (work completed)
- → `open` (work paused/reassigned)

**Commands:**
```bash
bd update <issue-id> --status=in_progress
bd update <issue-id> --assignee=username
bd list --status=in_progress
```

### 3. Blocked (Waiting)
**Meaning:** Work cannot proceed due to dependencies or external factors.

**Characteristics:**
- Has explicit blocking dependency
- Not shown in `bd ready` output
- Visible in `bd blocked` output
- Should document blocker reason

**Valid Transitions:**
- → `in_progress` (blocker resolved, work resumes)
- → `open` (blocker removed, but work not yet resumed)
- → `closed` (cancelled)

**Commands:**
```bash
bd update <issue-id> --status=blocked
bd blocked  # Show all blocked issues
bd show <issue-id>  # See what's blocking this issue
```

### 4. Closed (Terminal State)
**Meaning:** Work is complete or issue is no longer relevant.

**Characteristics:**
- Terminal state (can be reopened if needed)
- Removed from active work queues
- Eligible for compaction after time threshold
- Can include reason for closure

**Valid Transitions:**
- → `open` (via `bd reopen <issue-id>`)

**Commands:**
```bash
bd close <issue-id>
bd close <id1> <id2> <id3>  # Close multiple
bd close <issue-id> --reason="Duplicate of beads-123"
bd list --status=closed
```

### 5. Compacted (Archived)
**Meaning:** Closed issue has been semantically summarized and compressed.

**Characteristics:**
- Historical record maintained in git
- Reduces working set size
- Can be restored: `bd restore <issue-id>`
- Automatic after closure threshold (configurable)

**Valid Transitions:**
- → `open` (via `bd restore <issue-id>` then `bd reopen <issue-id>`)

**Commands:**
```bash
bd compact  # Compact old closed issues
bd restore <issue-id>  # Restore full history from git
```

## State Transition Diagram

```
    [Created]
        ↓
    [open] ←────────────────┐
        ↓                    │
        ↓ (start work)       │ (reopen)
        ↓                    │
  [in_progress] ←──┐         │
        ↓           │         │
        ↓ (blocked) │         │
        ↓           │         │
    [blocked] ──────┘         │
        ↓ (unblock)           │
        ↓                     │
    [closed] ─────────────────┘
        ↓
        ↓ (after threshold)
        ↓
  [compacted]
```

## Lifecycle Best Practices

### For AI Agents

1. **Check Status First:** Always run `bd ready` to find unblocked work
2. **Single Focus:** Keep only one issue `in_progress` at a time
3. **Immediate Updates:** Update status as soon as state changes
4. **Close in Batches:** Use `bd close <id1> <id2> ...` for efficiency
5. **Document Blockers:** When setting `blocked`, add comment explaining why

### State Selection Logic

**When to use `open`:**
- Issue created but not ready to start
- Work paused indefinitely
- Reassigning to another agent

**When to use `in_progress`:**
- Actively working on the issue right now
- Have context loaded and making progress
- Single issue per agent

**When to use `blocked`:**
- Cannot proceed without external dependency
- Waiting for another issue to complete
- External blocker (infrastructure, access, information)

**When to use `closed`:**
- Work completed successfully
- Issue cancelled/obsolete
- Duplicate of another issue

## Dependency Impact on Lifecycle

Issues with dependencies have special lifecycle behavior:

1. **Blocked by Dependencies:** Won't appear in `bd ready` until dependencies closed
2. **PageRank Priority:** Issues that unblock others get higher priority
3. **Cascade Unblocking:** Closing an issue may unblock multiple downstream issues

See [Dependency Resolution](./dependencies.md) for details.

## Automation

The beads daemon handles:
- Auto-commit on issue state changes
- Auto-push for remote synchronization
- Auto-pull for collaboration updates
- Hook triggers for context recovery

Manual intervention rarely needed for lifecycle management.
