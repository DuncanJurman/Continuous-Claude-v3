# Plan: Integrate god-ralph into Continuous-Claude-v3 (Native v5)

**Version:** 5.0 (Revised based on ClaudeDocs review + user decisions)
**Date:** 2026-01-12
**Status:** READY FOR IMPLEMENTATION

---

## Design Decisions Summary (v5 - Final)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Bead CLI | `bd` CLI is source of truth | Use `bd ready --json`, wrap with error handling |
| Learnings agent | `ralph-learner` | Clear purpose, avoids naming confusion with scribe.md/chronicler.md |
| Agent delegation | Full delegation to existing agents | scout, debug-agent, arbiter, kraken, spark, bead-decomposer |
| Worker pattern | **Extend kraken TDD patterns** | Reuse battle-tested TDD workflow and checkpoints |
| Worktree model | Always worktrees per bead | `.worktrees/ralph-<bead-id>/` with isolated branch |
| Merge strategy | **Verify-then-merge** | Verify in worktree BEFORE merge to main (no integration branch) |
| Memory integration | **Inject ONCE at spawn via hook** | Not per iteration - prevents redundant queries |
| Hook registration | PreToolUse in settings.json, Stop in agent frontmatter | Avoid prompt clobbering; maintain hook chain order |
| State persistence | `.claude/state/god-ralph/` (simplified) | queue/, sessions/, logs/ only |
| Completions log | **JSONL format** | Queryable with jq, still append-only |
| Handoffs | Use existing `thoughts/shared/handoffs/` system | No separate handoff directory |
| New features | **Recovery commands only** | /ralph health, gc, recover for safe operation |
| Tool access | Omit tools (inherit all) | Maximum flexibility per ClaudeDocs |
| Subagent skills | Explicit in frontmatter | Include parallel-agents, no-task-output, recall-reasoning |

---

## Architecture (v5 - Verify-Then-Merge)

```
User Request
     |
     v
/ralph (slash command) or workflow-router "Execute Beads"
     |
     |-- /ralph                 -> Show status from orchestrator-state.json
     |-- /ralph start [--max-parallel N] -> Start orchestrator (dry-run first)
     |-- /ralph <bead-id>       -> Run single Ralph on specific bead
     |-- /ralph stop            -> Gracefully stop after current batch
     |-- /ralph health          -> Full health check with actionable fixes  [NEW]
     |-- /ralph gc              -> Garbage collect orphaned worktrees       [NEW]
     |-- /ralph recover <id>    -> Recover specific bead from failed state  [NEW]
     |
     |-- Pre-flight: dependency check + validate beads (bead-validator) + claim
     |
     |-- Group beads by impact_paths overlap (avoid conflicts)
     |   (fallback: parse Key Files in bead description)
     |
     |-- Spawn ralph-workers in worktrees (run_in_background)
     |     |-- Hook: memory injection ONCE at spawn (ensure-worktree.sh)
     |     |-- Uses: all tools (inherited), tldr, bd, MCP
     |     |-- Pattern: kraken TDD workflow (write tests -> implement -> refactor)
     |     |-- Delegates: debug-agent, scout, arbiter, kraken, spark,
     |     |              bead-decomposer, plan-agent, plan-reviewer
     |     |-- Learnings: ralph-learner (store to memory + CLAUDE.md)
     |     |-- Handoffs: standard create_handoff schema
     |
     |-- Status tracking:
     |     |-- .claude/state/god-ralph/sessions/<bead-id>.json
     |     |-- .claude/state/god-ralph/completions.jsonl (append-only)
     |     |-- orchestrator-state.json
     |
     |-- Per-bead verification IN WORKTREE (before merge)
     |     |
     |     |-- verification-ralph runs acceptance criteria
     |     |-- PASS -> merge to main + bd close <bead-id>
     |     |-- FAIL -> worktree stays, failure handoff, bead stays open
     |
     v
Orchestrator manages merge queue (serialize successful beads to main)
```

**Key Change from v4:** No integration branch. Each bead is verified in its worktree, then merged directly to main. This provides:
- Clear failure attribution (specific bead)
- Fresh base for each merge (current main)
- Simpler state management (no integration branch)

---

## Agent Review & Recommendations (v5)

### Agents to ADD

| Agent | Source | Destination | Key Changes |
|-------|--------|-------------|-------------|
| `orchestrator` | god-ralph/agents/ | `.claude/agents/orchestrator.md` | Verify-then-merge, state persistence, recovery commands |
| `ralph-worker` | god-ralph/agents/ | `.claude/agents/ralph-worker.md` | **Extend kraken TDD patterns**, memory via hook, delegation |
| `verification-ralph` | god-ralph/agents/ | `.claude/agents/verification-ralph.md` | Run in worktree before merge, severity levels |
| `ralph-learner` | god-ralph/agents/scribe.md | `.claude/agents/ralph-learner.md` | **Renamed**, store to memory + CLAUDE.md |

### Agents to UPDATE

| Agent | Update |
|-------|--------|
| `kraken` | Add note: "Ralph-worker extends this TDD workflow. Ralph delegates here for complex TDD work." |
| `spark` | Add note: "For trivial 1-line fixes. Ralph delegates here for quick changes." |
| `bead-decomposer` | Add `impact_paths` to ralph_spec |
| `bead-validator` | Validate `impact_paths` presence/format |

### Agents/Commands to DELETE (from god-ralph)

| Item | Reason |
|------|--------|
| `bead-farmer.md` | Duplicate - use existing `bead-decomposer` |
| `scribe.md` | Renamed to `ralph-learner` |
| `commands/plan.md` | Use existing `plan-agent` |

---

## File Operations

### Phase 0: Dependency Verification

```bash
# Required dependencies - fail if missing
for dep in bd git jq; do
  if ! command -v "$dep" &> /dev/null; then
    echo "ERROR: Required dependency '$dep' not found"
    exit 1
  fi
done

# Optional dependencies - warn if missing
for dep in tldr; do
  if ! command -v "$dep" &> /dev/null; then
    echo "WARNING: Optional dependency '$dep' not found - degraded mode"
  fi
done
```

### Phase 1: Create State Directories (Simplified)

```bash
# Simplified structure - only 3 subdirectories
mkdir -p .claude/state/god-ralph/queue      # spawn queue files
mkdir -p .claude/state/god-ralph/sessions   # per-bead session state
mkdir -p .claude/state/god-ralph/logs       # hook and worker logs
mkdir -p .worktrees                         # git worktree location

# Initialize orchestrator state
cat > .claude/state/god-ralph/orchestrator-state.json << 'EOF'
{
  "status": "idle",
  "active_ralphs": [],
  "completed_beads": [],
  "failed_beads": [],
  "stuck_beads": [],
  "max_parallel": 3
}
EOF

# Initialize completions log (JSONL format)
touch .claude/state/god-ralph/completions.jsonl

# Add to .gitignore if not present
grep -q "^\.worktrees/" .gitignore 2>/dev/null || echo ".worktrees/" >> .gitignore
```

### Phase 2: Create bd Utility Wrappers

Create `.claude/scripts/bd-utils.sh`:
```bash
#!/usr/bin/env bash
# bd command wrappers with error handling

bd_ready() {
  local output
  if ! output=$(bd ready --json 2>&1); then
    echo "ERROR: bd ready failed: $output" >&2
    return 1
  fi
  echo "$output"
}

bd_claim() {
  local bead_id="$1"
  if ! bd update "$bead_id" --status=in_progress 2>&1; then
    echo "ERROR: Failed to claim bead $bead_id" >&2
    return 1
  fi
}

bd_close() {
  local bead_id="$1"
  if ! bd close "$bead_id" 2>&1; then
    echo "ERROR: Failed to close bead $bead_id" >&2
    return 1
  fi
}

bd_release() {
  local bead_id="$1"
  # Release claim without closing
  if ! bd update "$bead_id" --status=open 2>&1; then
    echo "ERROR: Failed to release bead $bead_id" >&2
    return 1
  fi
}
```

### Phase 3: Create/Update Hooks

**Copy and modify hooks:**
```bash
cp god-ralph/hooks/ensure-worktree.sh .claude/hooks/ensure-worktree.sh
cp god-ralph/hooks/ralph-stop-hook.sh .claude/hooks/ralph-stop-hook.sh
cp god-ralph/hooks/doc-only-check.sh .claude/hooks/ralph-doc-only-check.sh
```

**Update ensure-worktree.sh for memory injection:**

The hook must:
1. Create worktree atomically
2. Inject memory context ONCE at spawn
3. Preserve existing prompt modifications from prior hooks

```bash
# Key addition to ensure-worktree.sh:

# Query memory for bead-relevant context (ONCE at spawn)
BEAD_TITLE=$(jq -r '.title // "task"' "$QUEUE_FILE" 2>/dev/null || echo "task")
RECALL_OUTPUT=""
if [ -d "$CLAUDE_PROJECT_DIR/opc" ]; then
  RECALL_OUTPUT=$(cd "$CLAUDE_PROJECT_DIR/opc" && \
    PYTHONPATH=. uv run python scripts/core/recall_learnings.py \
    --query "$BEAD_TITLE" --k 3 --text-only 2>/dev/null || echo "")
fi

# Build memory context block
MEMORY_CONTEXT=""
if [ -n "$RECALL_OUTPUT" ]; then
  MEMORY_CONTEXT="## Relevant Learnings (from memory)
$RECALL_OUTPUT

"
fi

# Preserve existing prompt (from tldr/arch hooks)
EXISTING_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // ""')

# Build final prompt with all context
NEW_PROMPT="${MEMORY_CONTEXT}WORKTREE_PATH: $WORKTREE_PATH
BEAD_ID: $BEAD_ID

$EXISTING_PROMPT"

# Return with preserved tool_input structure
jq -n --arg p "$NEW_PROMPT" \
  --argjson ti "$TOOL_INPUT" \
  '{updatedInput: ($ti + {prompt: $p})}'
```

**Update ralph-stop-hook.sh for JSONL completions:**

```bash
# Append to completions.jsonl instead of .log
COMPLETIONS_FILE=".claude/state/god-ralph/completions.jsonl"

log_completion() {
  local bead_id="$1"
  local status="$2"
  local iterations="$3"
  local reason="${4:-}"

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg bid "$bead_id" \
    --arg st "$status" \
    --argjson it "$iterations" \
    --arg r "$reason" \
    '{timestamp: $ts, bead_id: $bid, status: $st, iterations: $it, reason: $r}' \
    >> "$COMPLETIONS_FILE"
}
```

**Register in .claude/settings.json:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          { "type": "command", "command": "node $HOME/.claude/hooks/dist/tldr-context-inject.mjs", "timeout": 30 },
          { "type": "command", "command": "node $HOME/.claude/hooks/dist/arch-context-inject.mjs", "timeout": 30 },
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/ensure-worktree.sh", "timeout": 45 }
        ]
      }
    ]
  }
}
```

**Hook Chain Order (CRITICAL):**

| Order | Hook | Modifies | Must Preserve |
|-------|------|----------|---------------|
| 1 | tldr-context-inject | prompt (prepend) | - |
| 2 | arch-context-inject | prompt (prepend) | tldr context |
| 3 | ensure-worktree | prompt (prepend) + cwd | tldr + arch context |

Each hook MUST:
1. Read existing prompt from `tool_input.prompt`
2. Prepend new context (not replace)
3. Return via `updatedInput` preserving all fields

### Phase 4: Create New Agents

#### `.claude/agents/ralph-worker.md`

```yaml
---
name: ralph-worker
description: Ephemeral bead executor using kraken TDD workflow. Completes one bead then exits.
model: opus
# tools: omitted to inherit all tools (per ClaudeDocs)
skills:
  - parallel-agents
  - no-task-output
  - no-polling-agents
  - background-agent-pings
  - agent-context-isolation
  - recall-reasoning
  - tldr-code
worktree_policy: required
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/hooks/ralph-stop-hook.sh"
          timeout: 30
---

# Ralph Worker Agent

You are an ephemeral Ralph worker. You complete exactly ONE bead using TDD methodology, then exit.

## Your Lifecycle

1. **Receive bead spec** - Title, description, acceptance criteria
2. **Use TDD workflow** - Following kraken patterns (see below)
3. **Iterate** - Stop hook re-invokes until completion or max iterations
4. **Signal completion** - Output `<promise>BEAD COMPLETE</promise>` when done
5. **Exit** - Die after completing your single bead

## TDD Workflow (Inherited from kraken)

You follow kraken's strict TDD workflow:

### Phase 1: Write Failing Tests First
1. Create/update test files
2. Write tests that define expected behavior
3. Run tests to confirm they fail

### Phase 2: Implement Minimum Code
1. Write minimum code to pass tests
2. Focus on functionality
3. Iterate until tests pass

### Phase 3: Refactor
1. Clean up implementation
2. Remove duplication
3. Run tests to ensure nothing broke

### Phase 4: Verify Acceptance Criteria
1. Run ALL acceptance criteria from bead spec
2. If all pass -> output completion promise
3. If any fail -> continue iterating

## Environment Verification (FIRST STEP)

Before doing ANY work, verify your environment:

```bash
# Verify worktree
if ! git rev-parse --git-dir 2>/dev/null | grep -q worktrees; then
  echo "ERROR: Not in a worktree!"
  exit 1
fi

# Verify bead context
BEAD_ID=$(cat .claude/god-ralph/current-bead 2>/dev/null || echo "")
echo "Bead: $BEAD_ID"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
```

## Delegation to Specialized Agents

Use specialized agents when needed:

| Situation | Agent | Invocation |
|-----------|-------|------------|
| Blocked by bug | debug-agent | `Task(subagent_type="debug-agent", prompt="...")` |
| Exploring codebase | scout | `Task(subagent_type="scout", prompt="...")` |
| TDD-critical changes | kraken | `Task(subagent_type="kraken", prompt="...")` |
| Trivial 1-line fixes | spark | `Task(subagent_type="spark", prompt="...")` |
| Facing ambiguity | arbiter | `Task(subagent_type="arbiter", prompt="...")` |
| Discovered issue (non-blocking) | bead-decomposer | `Task(subagent_type="bead-decomposer", prompt="...")` |

## Completion Promise

**CRITICAL**: Only output the completion promise when ALL acceptance criteria pass:

```
<promise>BEAD COMPLETE</promise>
```

Do NOT output this if tests fail, lint errors exist, or implementation is incomplete.

## Failure Handling

### Type A: Max Iterations / Criteria Not Met
- Bead remains OPEN (not closed)
- Failure logged in handoff
- Orchestrator may retry later

### Type B: Discovered Unrelated Issue
- File NEW bead via bead-decomposer (non-blocking)
- Continue working on current bead
- NOT a failure of current bead

## Git Hygiene

Always commit progress:
```bash
git add -A
git commit -m "feat(<bead-id>): <what you did>"
```
```

#### `.claude/agents/orchestrator.md`

```yaml
---
name: orchestrator
description: Persistent coordinator managing parallel Ralph workers on beads. Handles spawning, verification, merging, and recovery.
model: opus
skills:
  - parallel-agents
  - no-task-output
  - no-polling-agents
  - background-agent-pings
worktree_policy: none
---

# Orchestrator Agent

You manage the autonomous execution of beads via parallel Ralph workers.

## Core Workflow (Verify-Then-Merge)

### Phase 1: Discovery
```bash
source "$CLAUDE_PROJECT_DIR/.claude/scripts/bd-utils.sh"
READY_BEADS=$(bd_ready) || exit 1
```

### Phase 2: Parallelism Analysis
Group beads by `impact_paths` overlap:
- No overlap -> parallel execution
- Overlap -> sequential execution

### Phase 3: Spawn Ralphs

For each bead (atomic spawn with lock):

```bash
BEAD_ID="$1"
QUEUE_FILE=".claude/state/god-ralph/queue/${BEAD_ID}.json"
LOCK_FILE="${QUEUE_FILE}.lock"

# Atomic write with lock
(
  flock -n 200 || { echo "Bead $BEAD_ID already spawning"; exit 1; }

  cat > "$QUEUE_FILE" << EOF
{
  "bead_id": "$BEAD_ID",
  "worktree_path": ".worktrees/ralph-$BEAD_ID",
  "max_iterations": 50,
  "completion_promise": "BEAD COMPLETE"
}
EOF
) 200>"$LOCK_FILE"

# Spawn Ralph
Task(
  subagent_type="ralph-worker",
  description="Ralph for $BEAD_ID",
  run_in_background=true,
  prompt="BEAD_ID: $BEAD_ID

  <bead spec here>"
)
```

### Phase 4: Monitor

Poll session files for completion:
```bash
for session in .claude/state/god-ralph/sessions/*.json; do
  STATUS=$(jq -r '.status' "$session")
  case "$STATUS" in
    completed) handle_completion "$session" ;;
    failed)    handle_failure "$session" ;;
  esac
done
```

### Phase 5: Verify-Then-Merge

For EACH completed bead (before merge):

```bash
# 1. Spawn verification in worktree
Task(
  subagent_type="verification-ralph",
  prompt="Verify bead $BEAD_ID in worktree $WORKTREE_PATH

  Acceptance criteria:
  <criteria from bead spec>"
)

# 2. If PASS -> merge to main
git checkout main
git merge --ff-only "ralph/$BEAD_ID"
bd_close "$BEAD_ID"

# 3. If FAIL -> keep worktree, bead stays open
# Failure handoff created by verification-ralph
```

### Phase 6: Cleanup
```bash
# Remove completed worktrees
.claude/scripts/cleanup-worktree.sh "$BEAD_ID"
```

## State Management

| File | Purpose |
|------|---------|
| `orchestrator-state.json` | Overall orchestrator status |
| `sessions/<bead-id>.json` | Per-bead session state |
| `completions.jsonl` | Append-only completion log |
| `orchestrator.lock` | Prevent concurrent orchestrators |

## Recovery Commands

Handle crashes gracefully:
- `/ralph health` - Full health check
- `/ralph gc` - Clean orphaned worktrees
- `/ralph recover <bead-id>` - Recover specific bead
```

#### `.claude/agents/verification-ralph.md`

```yaml
---
name: verification-ralph
description: Runs bead acceptance criteria in worktree before merge. Reports pass/fail with details.
model: sonnet
tools: [Bash, Read, Grep]
worktree_policy: none
---

# Verification Ralph

You verify completed beads BEFORE they merge to main.

## Your Role

Run ALL acceptance criteria in the bead's worktree. Report results clearly.

## Acceptance Criteria Execution

```yaml
ralph_spec:
  acceptance_criteria:
    - type: test
      command: "npm test -- --grep 'settings'"
      severity: required
    - type: lint
      command: "npm run lint"
      severity: required
    - type: coverage
      command: "npm run coverage"
      severity: recommended
```

### Severity Levels

| Severity | On Failure |
|----------|------------|
| `required` | Block merge, bead stays open |
| `recommended` | Warn but allow merge |
| `optional` | Log only |

### Execution

```bash
cd "$WORKTREE_PATH"

for criterion in acceptance_criteria; do
  echo "Running: $criterion.command"
  if ! eval "$criterion.command"; then
    if [ "$criterion.severity" = "required" ]; then
      echo "FAIL: Required criterion failed"
      # Create failure handoff
      exit 1
    fi
  fi
done

echo "PASS: All required criteria met"
```

## Output

On success:
```
VERIFICATION PASSED
All required criteria met.
Warnings: <any recommended failures>
Ready for merge.
```

On failure:
```
VERIFICATION FAILED
Failed criteria:
- <criterion>: <error output>

Bead remains open. Worktree preserved for debugging.
```
```

#### `.claude/agents/ralph-learner.md`

```yaml
---
name: ralph-learner
description: Extracts and persists learnings from Ralph bead completions. Stores to memory system and updates CLAUDE.md with durable patterns.
model: sonnet
tools: [Bash, Read, Write]
worktree_policy: none
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/hooks/ralph-doc-only-check.sh"
  Stop:
    - hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/scripts/ensure-symlink.sh"
---

# Ralph Learner Agent

You extract actionable learnings from completed Ralph work and persist them for future sessions.

## Your Role

1. **Extract learnings** from Ralph's work
2. **Store to memory** via store_learning.py
3. **Update CLAUDE.md** with durable patterns only

## What to Extract

### Store to Memory (store_learning.py)

- Non-obvious solutions
- Error fixes that took multiple attempts
- Patterns discovered in codebase
- Architectural insights

```bash
cd "$CLAUDE_PROJECT_DIR/opc"
PYTHONPATH=. uv run python scripts/core/store_learning.py \
  --session-id "ralph-$BEAD_ID" \
  --type WORKING_SOLUTION \
  --content "<what was learned>" \
  --context "<bead title and scope>" \
  --tags "ralph,bead,$BEAD_ID" \
  --confidence high
```

### Update CLAUDE.md (Durable Patterns Only)

Only add to CLAUDE.md if:
- Pattern applies to future work in this codebase
- Non-obvious and would save time
- System-level insight (not bead-specific)

Do NOT add:
- Bead-specific details
- Trivial observations
- Generic programming knowledge

## Worktree Context

Parse `WORKTREE_PATH:` marker if present:
- If present: update `$WORKTREE_PATH/CLAUDE.md`
- If absent: update `./CLAUDE.md`
```

### Phase 5: Create /ralph Command

Create `.claude/commands/ralph.md`:

```markdown
---
description: Execute beads with parallel Ralph workers
---

# /ralph - Bead Execution with Ralph Workers

Orchestrate parallel Ralph workers to complete beads autonomously.

## Commands

| Command | Description |
|---------|-------------|
| `/ralph` | Show status (reads orchestrator-state.json) |
| `/ralph start [--max-parallel N]` | Start orchestrator (dry-run first) |
| `/ralph <bead-id>` | Run single Ralph on specific bead |
| `/ralph stop` | Stop gracefully after current batch |
| `/ralph resume` | Resume from state + existing worktrees |
| `/ralph health` | Full health check with actionable fixes |
| `/ralph gc` | Garbage collect orphaned worktrees |
| `/ralph recover <bead-id>` | Recover specific bead from failed state |
| `/ralph unlock [--force]` | Clear stale orchestrator lock |

## /ralph health Output

```markdown
# Ralph Health Check

## Orchestrator State
- Lock: CLEAR
- Status: idle
- Active Ralphs: 0

## Worktree State
- Total: 3
- With sessions: 2
- Orphaned: 1 (.worktrees/ralph-old)

## Bead State
- Ready: 5
- In Progress: 0
- Blocked: 2

## Recommendations
1. Run `/ralph gc` to clean orphaned worktree
2. Review blocked beads: beads-123, beads-456
```

## Behavior

- **Start**: Shows dry-run with parallelism groups, asks confirmation
- **Stop**: Sets state to "stopping", waits for current workers
- **Resume**: Reconcile state with sessions/worktrees, continue
- **Health**: Full diagnostic with actionable recommendations
- **GC**: Remove orphaned worktrees without active sessions
- **Recover**: Reset failed bead to open, clean up state
```

### Phase 6: Update workflow-router

Add to `.claude/skills/workflow-router/SKILL.md`:

```yaml
- goal: "Execute Beads"
  patterns: ["run beads", "execute beads", "start ralph", "complete beads", "work on beads"]
  agent: orchestrator
  description: "Parallel bead execution with Ralph workers"
```

---

## Critical Files Summary

| File | Changes |
|------|---------|
| `.claude/agents/ralph-worker.md` | NEW - extends kraken TDD, stop hook |
| `.claude/agents/orchestrator.md` | NEW - verify-then-merge, recovery commands |
| `.claude/agents/verification-ralph.md` | NEW - pre-merge verification, severity levels |
| `.claude/agents/ralph-learner.md` | NEW - renamed from scribe, memory integration |
| `.claude/scripts/bd-utils.sh` | NEW - bd command wrappers with error handling |
| `.claude/hooks/ensure-worktree.sh` | Memory injection, atomic spawn, chain preservation |
| `.claude/hooks/ralph-stop-hook.sh` | JSONL completions, iteration loop |
| `.claude/settings.json` | Register ensure-worktree hook |
| `.claude/commands/ralph.md` | NEW - full command set including recovery |
| `.claude/state/god-ralph/` | Simplified: queue/, sessions/, logs/ only |

---

## Verification Plan

### Test 1: Single Bead (Happy Path)
```bash
bd create --title="Test bead" --type=task --priority=2
/ralph <bead-id>

# Verify:
# - Worktree created at .worktrees/ralph-<bead-id>/
# - Memory context in initial prompt
# - TDD workflow followed
# - Verification runs in worktree
# - Merge to main after verification PASS
# - Bead closed
```

### Test 2: Verification Failure
```bash
# Create bead with failing acceptance criteria
/ralph <bead-id>

# Verify:
# - Verification fails in worktree
# - Worktree preserved
# - Bead stays OPEN
# - Main unchanged
# - Failure handoff created
```

### Test 3: Parallel Execution
```bash
# Create non-overlapping beads
/ralph start --max-parallel 3

# Verify:
# - Impact path grouping works
# - Non-overlapping beads run in parallel
# - Overlapping beads wait
```

### Test 4: Recovery Commands
```bash
# Simulate crash
/ralph start
# Kill terminal

# New session:
/ralph health   # Shows orphaned worktree
/ralph gc       # Cleans orphaned worktree
/ralph recover <bead-id>  # Resets bead to open
/ralph resume   # Continues
```

### Test 5: Hook Chain Preservation
```bash
/ralph <bead-id>

# Check ralph-worker received:
# - tldr structure context (from hook 1)
# - architecture context (from hook 2)
# - memory context (from hook 3)
# - worktree context (from hook 3)
```

### Test 6: Memory Injection (Single Query)
```bash
# Monitor recall queries
/ralph <bead-id>

# Verify:
# - Memory queried ONCE at spawn
# - Not queried on each iteration
# - Context visible in initial prompt
```

---

## Implementation Order

| Phase | Task | Verification |
|-------|------|--------------|
| 0 | Dependency check | `bd`, `git`, `jq` available |
| 1 | Create state dirs | `ls .claude/state/god-ralph/` shows 3 dirs |
| 2 | Create bd-utils.sh | `source bd-utils.sh && bd_ready` works |
| 3 | Create/update hooks | `ensure-worktree.sh` returns valid JSON |
| 4 | Register hooks | `jq '.hooks' .claude/settings.json` shows chain |
| 5 | Create agents | All 4 agent files exist |
| 6 | Create /ralph command | `/ralph` shows status |
| 7 | Update workflow-router | "Execute Beads" goal works |
| 8 | Test single bead | End-to-end passes |
| 9 | Test verification failure | Failure handling works |
| 10 | Test parallel | Grouping works |
| 11 | Test recovery | All recovery commands work |

---

## Migration from god-ralph

```bash
# 1. Copy source files (then modify per above)
cp god-ralph/agents/orchestrator.md .claude/agents/orchestrator.md
cp god-ralph/agents/ralph-worker.md .claude/agents/ralph-worker.md
cp god-ralph/agents/verification.md .claude/agents/verification-ralph.md
cp god-ralph/agents/scribe.md .claude/agents/ralph-learner.md

cp god-ralph/hooks/ensure-worktree.sh .claude/hooks/ensure-worktree.sh
cp god-ralph/hooks/ralph-stop-hook.sh .claude/hooks/ralph-stop-hook.sh
cp god-ralph/hooks/doc-only-check.sh .claude/hooks/ralph-doc-only-check.sh

cp god-ralph/scripts/cleanup-worktree.sh .claude/scripts/cleanup-worktree.sh
cp god-ralph/scripts/ensure-symlink.sh .claude/scripts/ensure-symlink.sh

# 2. Apply modifications per this plan

# 3. Keep god-ralph/ as reference (do not delete)
```

---

**Status: READY FOR IMPLEMENTATION**

Key improvements from v4:
- Verify-then-merge (no integration branch)
- ralph-learner naming (clear purpose)
- Extends kraken TDD patterns (code reuse)
- Memory injection ONCE via hook (performance)
- Recovery commands (safe operation)
- JSONL completions (queryable)
- Simplified state directories
- Atomic spawn with locking
- Hook chain order documentation
- bd error handling wrappers
