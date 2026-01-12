# Common Workflows

Practical patterns for using beads effectively in different scenarios.

## Daily Development Flow

### Morning: Finding Work

```bash
# 1. Check ready work
bd ready

# 2. Review your active work
bd list --status=in_progress

# 3. Check what's blocking progress
bd blocked

# 4. Review an issue in detail
bd show entropy-wiki-123

# 5. Start working
bd update entropy-wiki-123 --status=in_progress
```

### During Work: Discovering Dependencies

```bash
# While working on entropy-wiki-123, you realize it needs entropy-wiki-100 first

# 1. Add the dependency
bd dep add entropy-wiki-123 entropy-wiki-100

# 2. Mark current issue as blocked
bd update entropy-wiki-123 --status=blocked

# 3. Work on the blocker instead
bd update entropy-wiki-100 --status=in_progress
```

### End of Day: Wrapping Up

```bash
# 1. Close completed work (batch)
bd close entropy-wiki-100 entropy-wiki-101 entropy-wiki-102

# 2. Commit and push code changes
git status
git add .
git commit -m "Implement features 100-102"
git push

# 3. Check what was unblocked
bd ready

# Note: Daemon handles beads sync automatically
```

---

## Feature Development Workflow

### Phase 1: Planning

```bash
# 1. Create the epic
bd create --title="User Authentication System" --type=epic --priority=1

# 2. Break down into tasks (use parallel subagents for efficiency)
bd create --title="Design auth schema" --type=task --priority=1
bd create --title="Implement JWT tokens" --type=task --priority=1
bd create --title="Add login endpoint" --type=task --priority=1
bd create --title="Add registration endpoint" --type=task --priority=1
bd create --title="Write auth tests" --type=task --priority=2
bd create --title="Update documentation" --type=task --priority=2

# 3. Set up dependencies
bd dep add beads-epic beads-task1  # Epic depends on all tasks
bd dep add beads-epic beads-task2
bd dep add beads-epic beads-task3
bd dep add beads-epic beads-task4
bd dep add beads-epic beads-task5
bd dep add beads-epic beads-task6

bd dep add beads-task3 beads-task1  # Login needs schema
bd dep add beads-task3 beads-task2  # Login needs JWT
bd dep add beads-task4 beads-task1  # Registration needs schema
bd dep add beads-task5 beads-task3  # Tests need endpoints
bd dep add beads-task5 beads-task4
bd dep add beads-task6 beads-task5  # Docs need tests to pass

# 4. Check the ready work
bd ready
# Should show: beads-task1 (schema) and beads-task2 (JWT) as highest priority
```

### Phase 2: Execution

```bash
# Work on foundation first (PageRank surfaces these)
bd update beads-task1 --status=in_progress
# [implement schema]
bd close beads-task1

bd update beads-task2 --status=in_progress
# [implement JWT]
bd close beads-task2

# PageRank now surfaces endpoint work
bd ready
bd update beads-task3 --status=in_progress
# [implement login]
bd close beads-task3

# Continue through dependency chain...
```

### Phase 3: Completion

```bash
# Close remaining work
bd close beads-task4 beads-task5 beads-task6

# Epic automatically unblocks
bd update beads-epic --status=closed

# Commit and push
git add .
git commit -m "Complete authentication system"
git push
```

---

## Bug Fix Workflow

### Rapid Fix (Single Session)

```bash
# 1. Create bug issue
bd create --title="Fix cache invalidation" --type=bug --priority=0

# 2. Start work immediately
bd update beads-123 --status=in_progress

# 3. Add findings as comments
bd comments beads-123 --add="Root cause: TTL not set on cache keys"

# 4. Fix and close
# [make the fix]
bd close beads-123

# 5. Commit
git add .
git commit -m "Fix cache invalidation (beads-123)"
git push
```

### Complex Bug (Multi-Session)

```bash
# 1. Create bug issue
bd create --title="Memory leak in worker process" --type=bug --priority=1

# 2. Start investigation
bd update beads-200 --status=in_progress

# 3. Document findings as you go
bd comments beads-200 --add="Reproduces with 1000+ concurrent requests"
bd comments beads-200 --add="Profiler shows EventEmitter listeners not cleaned up"
bd comments beads-200 --add="Suspect issue in WebSocket handler"

# Session ends, conversation compacts...

# 4. Next session - context recovery
bd prime  # Loads context
bd show beads-200  # Review comments and progress

# 5. Continue work
bd comments beads-200 --add="Fixed: added proper cleanup in ws.on('close')"
bd close beads-200
```

---

## Refactoring Workflow

### Incremental Refactor

```bash
# 1. Create refactor epic
bd create --title="Refactor API layer" --type=epic --priority=2

# 2. Break into safe, incremental tasks
bd create --title="Extract validation middleware" --type=task
bd create --title="Standardize error responses" --type=task
bd create --title="Add request logging" --type=task
bd create --title="Update tests for new structure" --type=task

# 3. Set up dependencies (sequential safe changes)
bd dep add beads-task2 beads-task1  # Errors depend on validation
bd dep add beads-task3 beads-task2  # Logging depends on errors
bd dep add beads-task4 beads-task3  # Tests depend on all changes

# 4. Work through sequentially
bd ready  # Shows task1
# [complete task1]
bd close beads-task1

bd ready  # Now shows task2
# [complete task2]
bd close beads-task2

# Continue...
```

---

## Blocked Work Recovery

### Scenario: External Blocker

```bash
# Working on feature, discover need for infrastructure

# 1. Document the blocker
bd update beads-current --status=blocked
bd comments beads-current --add="Blocked: need Redis cluster provisioned"

# 2. Create infrastructure task
bd create --title="Provision Redis cluster" --type=task --priority=1

# 3. Link dependency
bd dep add beads-current beads-infra

# 4. Work on other ready tasks
bd ready  # Shows what else is available

# Later: infrastructure complete
bd close beads-infra

# Current task automatically unblocks
bd ready  # Shows beads-current
bd update beads-current --status=in_progress
```

---

## Collaboration Workflow

### Taking Over Work

```bash
# 1. Review available work
bd ready

# 2. Check what Alice was working on
bd list --assignee=alice --status=in_progress

# 3. Review issue details and comments
bd show beads-alice-task
bd comments beads-alice-task

# 4. Reassign to yourself
bd update beads-alice-task --assignee=bob

# 5. Continue work
# [make progress]
bd comments beads-alice-task --add="Continued from Alice's work, implemented error handling"
bd close beads-alice-task
```

### Sync and Conflict Resolution

```bash
# Daemon handles most sync automatically, but manual sync if needed:

# 1. Check sync status
bd sync --status

# 2. Manual sync if behind
bd sync

# 3. If conflicts occur
bd doctor  # Diagnoses sync issues
# Resolve manually in .beads/ directory
git status
# [resolve conflicts in .beads/issues/]
git add .beads/
git commit -m "Resolve beads sync conflict"
bd sync
```

---

## Context Recovery Workflow

### After Conversation Compaction

```bash
# Conversation was compacted, context lost

# 1. Auto-recovery (via hooks)
# bd prime runs automatically when .beads/ detected

# 2. Manual recovery if needed
bd prime

# 3. Review active work
bd list --status=in_progress
bd show <issue-id>

# 4. Review comments for context
bd comments <issue-id>

# 5. Continue work
```

### After Long Break

```bash
# Haven't worked on project in weeks

# 1. Get project overview
bd stats

# 2. Check what's ready
bd ready

# 3. Check what was in progress
bd list --status=in_progress

# 4. Review blocked work
bd blocked

# 5. Pick up where you left off
bd show <issue-id>
bd comments <issue-id>
bd update <issue-id> --status=in_progress
```

---

## Strategic Planning Workflow

### Epic with Parallel Tracks

```bash
# 1. Create epic
bd create --title="Platform V2 Migration" --type=epic --priority=0

# 2. Create parallel work tracks
# Track A: Database
bd create --title="Migrate to Postgres 15" --type=task
bd create --title="Update ORM schemas" --type=task
bd create --title="Migrate data" --type=task

# Track B: API
bd create --title="Update API to v2 spec" --type=task
bd create --title="Add backwards compat layer" --type=task

# Track C: Frontend
bd create --title="Update frontend API client" --type=task
bd create --title="Update UI components" --type=task

# 3. Set up dependencies
# Database track (sequential)
bd dep add beads-db2 beads-db1
bd dep add beads-db3 beads-db2

# API track (sequential)
bd dep add beads-api2 beads-api1

# Frontend depends on API
bd dep add beads-fe1 beads-api2
bd dep add beads-fe2 beads-fe1

# Epic depends on all final tasks
bd dep add beads-epic beads-db3
bd dep add beads-epic beads-api2
bd dep add beads-epic beads-fe2

# 4. PageRank surfaces critical path
bd ready
# Shows: beads-db1, beads-api1 (heads of tracks)
```

---

## Maintenance Workflow

### Weekly Cleanup

```bash
# 1. Check project health
bd stats
bd doctor

# 2. Review old closed issues
bd list --status=closed | head -20

# 3. Compact old issues
bd compact --days=30 --dry-run  # Preview
bd compact --days=30            # Execute

# 4. Check for orphaned work
bd blocked
bd list --status=open

# 5. Clean up stale issues
bd close beads-stale1 beads-stale2 --reason="No longer relevant"
```

### Monthly Audit

```bash
# 1. Export for analysis
bd export --status=closed > closed-issues.jsonl

# 2. Review metrics
bd stats

# 3. Check dependency health
bd blocked
# Look for patterns: same issues blocking multiple items?

# 4. Reorganize if needed
# Break up long chains
# Remove unnecessary dependencies
# Update priorities based on PageRank insights
```

---

## Anti-Patterns to Avoid

### 1. Too Many In-Progress Issues

**Bad:**
```bash
bd list --status=in_progress
# Shows 10+ issues
```

**Good:**
```bash
# Keep 1-2 issues in_progress max
# Close or re-open others
bd update beads-extra1 --status=open
bd update beads-extra2 --status=open
```

### 2. Ignoring Dependencies

**Bad:**
```bash
# Work on tasks without checking blockers
bd update beads-123 --status=in_progress
# (actually blocked by beads-100)
```

**Good:**
```bash
# Always check ready work
bd ready
# Trust PageRank to surface unblocked work
```

### 3. Manual Priority Override

**Bad:**
```bash
# Constantly overriding priority
bd update beads-123 --priority=0
bd update beads-124 --priority=0
bd update beads-125 --priority=0
```

**Good:**
```bash
# Trust PageRank
bd ready
# Work on what surfaces naturally
```

### 4. Creating Without Planning

**Bad:**
```bash
# Create 50 issues without dependencies
bd create --title="Task 1"
bd create --title="Task 2"
# ... no structure
```

**Good:**
```bash
# Create epic, break down, link dependencies
bd create --title="Epic" --type=epic
# Create tasks with clear dependencies
# Use PageRank to guide execution order
```

### 5. Not Using Comments

**Bad:**
```bash
# Issue sits blocked for days, no context
bd show beads-123
# No comments explaining blocker
```

**Good:**
```bash
# Document as you go
bd comments beads-123 --add="Blocked: waiting for API key from vendor"
bd comments beads-123 --add="Temporary workaround: using mock data"
```

---

## Summary: Key Principles

1. **Trust `bd ready`** - PageRank knows the critical path
2. **One thing at a time** - Single in_progress issue per agent
3. **Document as you go** - Use comments for future context
4. **Close in batches** - Efficient: `bd close id1 id2 id3`
5. **Dependencies drive flow** - Link blockers explicitly
6. **Daemon handles sync** - Don't worry about manual sync
7. **Context recovery** - `bd prime` restores after compaction
8. **Strategic planning** - Use epics and dependencies for complex work
