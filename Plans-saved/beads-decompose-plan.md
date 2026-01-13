# Plan: Bead Decomposer + Bead Validator Agents

## Goal

Create two specialized agents that work together to transform approved plans into high-quality, atomic beads:

1. **bead-decomposer**: Takes a comprehensive plan and decomposes it into atomic, executable beads with proper granularity, dependencies, and distributed context
2. **bead-validator**: Reviews and refines the created beads to ensure they are self-contained, self-documenting, and ready for worker agents

## Design Decisions (Confirmed)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Bead ID Format | Feature-based prefix (e.g., `auth-001`) | Easier to group and find related beads |
| Epic Creation | Always create epic | Consistent grouping, easy to find all related beads via `bd epic` |
| Validation Iterations | Single pass with fixes | Efficient; fix what can be fixed, flag remaining issues |
| Agent Models | Both Opus | Decomposition and validation are critical decisions |
| Context Passing | Plan path + decomposer output file | Standard agent pattern, avoids large prompts |
| Output Location | `.claude/cache/agents/<name>/PLAN-<slug>-output.md` | Per-plan files preserve history; also updates `latest-output.md` as pointer |

## Workflow Position

```
plan-agent → validate-agent → plan-reviewer → [APPROVED]
                                                   ↓
                                          bead-decomposer
                                                   ↓
                                          bead-validator
                                                   ↓
                                          [READY FOR WORKERS]
                                                   ↓
                                          Worker claims via `bd ready`
```

## Agent 1: bead-decomposer

### Purpose
Transform approved plans into atomic beads with proper granularity, dependencies, and context distribution. You are the **Project Manager** responsible for breaking comprehensive specifications into executable units of work.

### Frontmatter
```yaml
---
name: bead-decomposer
description: Decomposes comprehensive plans into atomic, executable beads with proper granularity, dependencies, and context distribution
model: opus
tools: [Bash, Read, Grep, Glob]
worktree_policy: none
---
```

### Erotetic Framework

Before decomposing, frame the question space E(X,Q):
- **X** = plan to decompose
- **Q** = decomposition questions:
  1. What are the natural boundaries in this work?
  2. How many beads? What granularity?
  3. What context does each bead need to be self-contained?
  4. What are the dependency relationships?
  5. Are there any duplicates in existing beads?

Answer each Q systematically to produce a complete decomposition.

### Input Contract
The agent receives:
- **Plan file path**: `$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-<name>.md`
- **$CLAUDE_PROJECT_DIR**: Project root

### Output Contract
Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/PLAN-<slug>-output.md`

Also updates `latest-output.md` as a pointer to the most recent run (for validator convenience).

Output includes:
```markdown
# Bead Decomposition Report
Generated: [timestamp]
Plan: [plan file path]

## Decomposition Summary
- Feature Name: [extracted from plan]
- Prefix Used: [feature-prefix]-
- Epic Created: [epic-id]
- Total Beads: N (1 epic + N-1 tasks)
- PageRank Critical Path: [highest PageRank beads first]

## Dependency Graph
```
[feature-prefix]-epic (BLOCKED - depends on all children)
  ├── [feature-prefix]-001 (READY - highest PageRank)
  ├── [feature-prefix]-002 (READY)
  └── [feature-prefix]-003 (BLOCKED by [feature-prefix]-001)
```

## Created Beads
<!-- bead-validator reads this section to know which beads to review -->
| ID | Title | Type | Priority | Depends On | PageRank |
|----|-------|------|----------|------------|----------|
| auth-epic | Auth System | epic | P1 | auth-001, auth-002, auth-003 | - |
| auth-001 | Database schema | task | P2 | - | HIGH |
| auth-002 | JWT middleware | task | P2 | - | MEDIUM |
| auth-003 | API endpoints | task | P2 | auth-001 | LOW |

## Bead Details

### auth-epic: Auth System [EPIC]
**Dependencies:** Depends on all child beads (blocks nothing)
**Purpose:** Groups all auth-related beads; closed when all children complete.

### auth-001: Database schema
**Full Description Written to Bead:**
[Copy of what was written via bd create]

**ralph_spec Added:**
[Copy of ralph_spec comment]
```

### Step-by-Step Workflow

#### Step 1: Read and Analyze the Plan

```bash
# Read the plan file completely
cat "$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-<name>.md"

# Extract feature name for prefix (slugify the plan title)
# Example: "User Authentication System" → "auth"
```

**Extract from plan:**
- Feature name (for prefix)
- Business context (why this matters)
- All requirements and constraints
- Acceptance criteria
- File references

#### Step 2: Check for Duplicates

```bash
# Search existing beads for similar work
bd list --status=open | grep -i "<keywords>"
bd list --status=in_progress | grep -i "<keywords>"

# Check git log for recent fixes
git log --oneline -20 --grep="<keyword>"
git log --oneline -10 -- <suspected-file-paths>
```

**If duplicates found:**
- **Exact same feature or beads exist (duplicate)** → Report it and skip creating new beads
- **Overlapping scope but differences (similar)** → Create new beads with a note linking to existing work
- **Related prerequisite or subsequent work (distinct but related)** → Create new beads and add dependency to existing beads using `bd dep add`

#### Step 3: Identify Natural Boundaries

Analyze the plan for natural seams:

| Boundary Type | Example |
|---------------|---------|
| Different files/modules | API routes vs middleware vs models |
| Different concerns | Auth logic vs token handling vs rate limiting |
| Sequential dependencies | Must have X before Y |
| Parallelizable work | Can do X and Y simultaneously |
| Test boundaries | Unit tests vs integration tests |

#### Step 4: Determine Granularity

**Guideline: Each bead should be completable in 10-50 iterations by a worker agent.**

| Plan Complexity | Typical Beads | Example |
|-----------------|---------------|---------|
| Tiny (1 file change) | 1 bead + epic | Fix typo → 1 task |
| Small (2-3 related files) | 2-3 beads + epic | Add endpoint → schema, route, tests |
| Medium (feature) | 4-8 beads + epic | Auth system → multiple components |
| Large (system) | 8+ beads + epic | Full rewrite → possibly nested epics |

**Signs a bead is too big:**
- Touches 5+ unrelated files
- Has 10+ acceptance criteria
- Mixes multiple concerns (auth AND email AND database)
- Would take 50+ iterations

**Signs a bead is too small:**
- Single line change with no verification needed
- No meaningful acceptance criteria
- Could be combined with related work

**Note: Extremely Large Plans**
For very large features covering distinct subprojects or modules, consider decomposing into **multiple epics**. Create separate epic beads for each major sub-feature (with a top-level epic to group them if necessary). This keeps each epic focused and manageable, improving clarity and enabling parallel execution by different worker agents.

#### Step 5: Create the Epic

**Always create an epic first to group all related beads:**

```bash
# Extract prefix from plan name (slugify)
PREFIX="auth"  # Example

# Create epic bead
bd create \
  --title="<Feature Name>" \
  --type=epic \
  --priority=1 \
  --description="## Overview
<Brief description of the feature>

## Source Plan
$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-<name>.md

## Success Criteria
<High-level criteria from plan>
"

# Rename to use feature prefix (if bd supports, otherwise note the ID)
EPIC_ID="<returned-id>"
```

#### Step 6: Create Task Beads with Distributed Context

For each identified task, create a bead with ONLY relevant context:

```bash
bd create \
  --title="<Specific Task Title>" \
  --type=task \
  --priority=2 \
  --description="## Task
[Clear statement of what needs to be done]

## Context
[Why this task exists, how it fits into the larger feature]

## Key Files
- \`src/api/auth.ts\` - Add new endpoint here
- \`src/middleware/jwt.ts\` - Reference for token validation pattern

## Patterns to Follow
[Relevant code snippets or pattern references from plan]

## Acceptance Criteria
- [ ] Specific, testable criterion
- [ ] Command to verify: \`npm test -- --grep 'auth'\`

## Notes
[Edge cases this bead handles, gotchas, considerations for future self]
"
```

**Context Distribution Rules:**

| Include | Exclude |
|---------|---------|
| Files THIS bead touches | Files for other beads |
| Patterns THIS bead needs | All patterns from plan |
| Edge cases THIS bead handles | Edge cases for other beads |
| Acceptance criteria for THIS bead | Full feature criteria |
| Enough to work independently | Full plan content |

#### Step 7: Add ralph_spec to Each Bead

```bash
bd comments <bead-id> --add="ralph_spec:
completion_promise: BEAD COMPLETE
max_iterations: 50
acceptance_criteria:
  - type: test
    command: npm test -- --grep '<pattern>'
  - type: lint
    command: npm run lint
  - type: build
    command: npm run build
"
```

The ralph_spec tells worker agents:
- `completion_promise`: What to say when done
- `max_iterations`: Iteration budget
- `acceptance_criteria`: How to verify completion

#### Step 8: Establish Dependencies

**CRITICAL: Epic depends on ALL children (children are READY to work)**

```bash
# CORRECT: Epic depends on all children (repeat for each child bead)
bd dep add <epic-id> <child-1-id>
bd dep add <epic-id> <child-2-id>
bd dep add <epic-id> <child-3-id>
# ... repeat for every child bead

# Result:
# - children: READY (no blockers)
# - epic: BLOCKED (waiting for all children)
```

```bash
# WRONG: This blocks children forever!
bd dep add <child-id> <epic-id>
# DON'T DO THIS
```

**Other dependency patterns:**

```bash
# Task B requires Task A to complete first (B depends on A)
bd dep add <task-B-id> <task-A-id>

# Tests depend on implementation
bd dep add <tests-bead-id> <impl-bead-id>
```

#### Step 9: Associate Children with Epic

```bash
# Add each child bead to the epic
bd epic <epic-id> --add=<child-id>
```

#### Step 10: Write Output Report

Write the full decomposition report to the output file, including:
- All bead IDs created (for validator to read)
- Dependency graph visualization
- Full description of each bead
- ralph_spec for each bead

### Agent Rules

1. **Read the plan completely** - Understand business context before decomposing
2. **Always create an epic** - Even for small decompositions (multiple epics for very large plans)
3. **Use feature-based prefix** - Extract from plan title (e.g., "auth-001")
4. **Check for duplicates** - Search existing beads before creating
5. **Distribute context appropriately** - Each bead gets only what it needs
6. **CRITICAL: Epic depends on ALL children** - Repeat `bd dep add` for every child; never reverse direction
7. **Add ralph_spec to every bead** - Worker agents need this
8. **Write output report** - Validator reads this to know which beads to review
9. **Handle errors gracefully** - If any `bd` command fails (e.g., creation or dependency error), adjust the approach or flag the issue for human review instead of continuing blindly

---

## Agent 2: bead-validator

### Purpose
Review and refine created beads to ensure they are self-contained, self-documenting, and ready for worker agents. This agent **actively fixes** issues in a single pass rather than just flagging them.

### Frontmatter
```yaml
---
name: bead-validator
description: Reviews and refines beads to ensure self-contained context, proper dependencies, and clear acceptance criteria. Single-pass fix-as-you-go approach.
model: opus
tools: [Bash, Read, Grep, Glob]
worktree_policy: none
---
```

### Erotetic Framework

Before validating, frame the question space E(X,Q):
- **X** = set of beads to validate
- **Q** = validation questions for each bead:
  1. Can a worker understand this task without reading the full plan?
  2. Are acceptance criteria specific and testable?
  3. Are dependencies correctly established?
  4. Is the granularity appropriate?
  5. Is there enough reasoning/justification for future self?

Answer each Q systematically to validate and refine each bead.

### Input Contract
The agent receives:
- **Plan file path**: `$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-<name>.md`
- **Decomposer output path**: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md`
- **$CLAUDE_PROJECT_DIR**: Project root

The agent reads the decomposer output's "Created Beads" section to get the list of bead IDs to validate.

### Output Contract
Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-validator/PLAN-<slug>-output.md`

Also updates `latest-output.md` as a pointer to the most recent run.

Output includes:
```markdown
# Bead Validation Report
Generated: [timestamp]
Plan: [plan file path]
Decomposer Output: [decomposer output path]

## Validation Summary
- Beads Reviewed: N
- Issues Found: M
- Issues Fixed: M (all that could be fixed in single pass)
- Remaining Issues: R (requires human review)
- Status: VALIDATED | NEEDS_ATTENTION

## Bead Reviews

### auth-001: Database schema ✓ VALIDATED
**Checklist:**
- [x] Task statement is clear and actionable
- [x] Context explains WHY this task exists
- [x] Key files are listed with actions
- [x] Acceptance criteria are specific and testable
- [x] Dependencies are correct
- [x] Self-documenting for future worker

**No issues found.**

### auth-002: JWT middleware ✓ VALIDATED (with fixes)
**Issues Found:**
1. Context gap: Missing reference to existing auth middleware pattern
2. Dependency: Should depend on auth-001 (schema must exist first)

**Fixes Applied:**
1. Added pattern reference: `bd comments auth-002 --add="## Pattern Reference\nSee src/middleware/example.ts for middleware pattern"`
2. Added dependency: `bd dep add auth-002 auth-001`

**Final Status:** ✓ VALIDATED

### auth-003: API endpoints ⚠️ NEEDS_ATTENTION
**Issues Found:**
1. Granularity: Bead covers 6 endpoints - consider splitting
2. Missing verification command in acceptance criteria

**Fixes Applied:**
1. Added verification command via bd comments

**Remaining Issues (requires human review):**
1. Granularity decision: Split into multiple beads?

## Dependency Graph (After Fixes)
```
auth-epic
  └── auth-001 (READY - highest PageRank)
        └── auth-002 (blocked by auth-001)
              └── auth-003 (blocked by auth-002)
```

## Final Status
- **VALIDATED:** N beads ready for workers
- **NEEDS_ATTENTION:** M beads require human review before workers can proceed
```

### Step-by-Step Workflow

#### Step 1: Read Decomposer Output

```bash
# Read the decomposer output to get bead IDs
cat "$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md"

# Extract bead IDs from "Created Beads" table
# Example: auth-epic, auth-001, auth-002, auth-003
```

#### Step 2: Read the Original Plan

```bash
# Read the plan for full context
cat "$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-<name>.md"
```

Use the plan as reference when checking if beads have sufficient context.

#### Step 3: Validate Each Bead (Single Pass)

For each bead ID from the decomposer output:

```bash
# Get full bead details
bd show <bead-id>
```

Apply the validation checklist and fix issues as you go:

**Validation Checklist:**

| Category | Check | Fix Action |
|----------|-------|------------|
| **Context Sufficiency** | | |
| Task statement clear? | If vague, update via `bd update <id> --description` |
| Context explains WHY? | If missing, add via `bd comments` |
| Key files listed? | If missing, add via `bd comments` |
| Patterns referenced? | If missing, add pattern reference via `bd comments` |
| Edge cases noted? | If missing, add via `bd comments` |
| **Acceptance Criteria** | | |
| Criteria specific/testable? | If vague, refine via `bd update` or `bd comments` |
| Verification commands? | If missing, add via `bd comments` |
| Scoped to THIS bead? | If too broad, note for human review |
| **Dependencies** | | |
| All blocking captured? | Add missing: `bd dep add` |
| Epic depends on children? | Fix if wrong: `bd dep remove` + `bd dep add` |
| No circular? | Check with `bd show`, fix if found |
| **Granularity** | | |
| Completable in 10-50 iter? | If too big, flag for human review |
| Single concern? | If mixed, flag for human review |
| Meaningful scope? | If too small, consider merging (human review) |
| **Self-Documentation** | | |
| Worker can understand alone? | If not, add context via `bd comments` |
| Reasoning included? | If not, add via `bd comments` |
| Project goals linkage? | If unclear, add via `bd comments` |

**Fix Commands:**

```bash
# Add missing context as comment
bd comments <id> --add="## Additional Context
[missing information here]

## Pattern Reference
See src/example.ts:42 for pattern to follow"

# Fix dependencies
bd dep add <dependent> <dependency>
bd dep remove <dependent> <dependency>

# Update bead priority if misassessed
bd update <id> --priority=<new>

# Add labels for categorization
bd label <id> --add="needs-review"
bd label <id> --add="complex"
```

#### Step 4: Handle Unfixable Issues

Some issues cannot be fixed by the validator:
- **Granularity changes** require re-decomposition (human review)
- **Scope decisions** require understanding user intent (human review)
- **Ambiguous requirements** need clarification (human review)

For these, mark with label and note in output:
```bash
bd label <id> --add="needs-human-review"
bd comments <id> --add="## Validator Note
This bead may be too large. Consider splitting into:
1. [suggested split 1]
2. [suggested split 2]

Flagged for human review."
```

#### Step 5: Write Validation Report

Write comprehensive report including:
- All beads reviewed
- Issues found and fixes applied
- Remaining issues requiring human review
- Updated dependency graph
- Final status (VALIDATED or NEEDS_ATTENTION)

### Agent Rules

1. **Single pass** - Fix issues as you find them, don't iterate
2. **Fix what you can** - Use bd commands to add context, fix dependencies
3. **Flag what you can't** - Label beads that need human review
4. **Be thorough** - Every bead gets the full checklist
5. **Document fixes** - Record exactly what was changed
6. **Reference the plan** - Use original plan to fill context gaps
7. **Think like a worker** - Would you understand this bead without the plan?
8. **Handle errors gracefully** - If any `bd` command fails, note the issue in the report and continue with remaining beads

---

## Integration: Agent Orchestration

### Slash Command: /decompose (Recommended)

Implement a slash command that orchestrates both agents in sequence:

```bash
# User runs after plan approval
/decompose thoughts/shared/plans/PLAN-auth-system.md
```

**Skill flow:**
1. Spawn bead-decomposer with plan path
2. Wait for completion
3. Spawn bead-validator with plan path + decomposer output
4. Return final validation status

This aligns with Claude Code's design where user-initiated workflows should be encapsulated in slash commands for consistency and ease of use.

### Direct Task Invocation

Alternatively, maestro or user can spawn directly:

```
Task(subagent_type="bead-decomposer", prompt="
## Plan File
$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-auth-system.md

## Context
Plan has been approved by plan-reviewer. Decompose into atomic beads.
")
```

Then:
```
Task(subagent_type="bead-validator", prompt="
## Plan File
$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-auth-system.md

## Decomposer Output
$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md

## Context
Validate and refine all beads created by decomposer.
")
```

---

## Files to Create/Modify

| File | Action | Notes |
|------|--------|-------|
| `.claude/agents/bead-decomposer.md` | UPDATE | Replace current draft with full agent spec |
| `.claude/agents/bead-validator.md` | CREATE | New agent for bead validation/refinement |
| `.claude/commands/decompose.md` | CREATE | Slash command to orchestrate decomposer + validator |

---

## ralph_spec Format

Each bead should have a comment with ralph_spec:

```bash
bd comments <bead-id> --add "ralph_spec:
completion_promise: BEAD COMPLETE
max_iterations: 50
acceptance_criteria:
  - type: test
    command: npm test -- --grep '<pattern>'
  - type: lint
    command: npm run lint
  - type: build
    command: npm run build
"
```

This tells worker agents:
- What to say when done (`completion_promise`)
- Iteration budget (`max_iterations`)
- How to verify completion (`acceptance_criteria`)

---

## End-to-End Example

### Scenario: Auth System Plan → Beads

```bash
# 1. Plan exists after approval
cat thoughts/shared/plans/PLAN-auth-system.md

# 2. Spawn bead-decomposer
Task(subagent_type="bead-decomposer", prompt="
## Plan File
$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-auth-system.md

## Context
Plan has been approved by plan-reviewer. Decompose into atomic beads.
")

# 3. Decomposer creates beads
bd create --title="Auth System" --type=epic --priority=1 --description="..."
bd create --title="Database schema" --type=task --priority=2 --description="..."
bd create --title="JWT middleware" --type=task --priority=2 --description="..."
bd create --title="API endpoints" --type=task --priority=2 --description="..."
bd dep add auth-epic auth-001
bd dep add auth-epic auth-002
bd dep add auth-epic auth-003
bd dep add auth-002 auth-001  # JWT depends on schema
bd comments auth-001 --add="ralph_spec:..."

# 4. Decomposer writes output
# → .claude/cache/agents/bead-decomposer/latest-output.md

# 5. Spawn bead-validator
Task(subagent_type="bead-validator", prompt="
## Plan File
$CLAUDE_PROJECT_DIR/thoughts/shared/plans/PLAN-auth-system.md

## Decomposer Output
$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md

## Context
Validate and refine all beads created by decomposer.
")

# 6. Validator reviews and fixes
bd show auth-001  # Check context sufficiency
bd comments auth-002 --add="## Pattern Reference\nSee src/middleware/..."  # Add missing context
bd dep add auth-003 auth-002  # Add missing dependency

# 7. Validator writes output
# → .claude/cache/agents/bead-validator/latest-output.md
# Status: VALIDATED

# 8. Beads are ready for workers
bd ready
# OUTPUT:
# 📋 Ready work (1 issue with no blockers):
# 1. [P2] [task] auth-001: Database schema

# 9. Worker claims and completes
bd update auth-001 --status=in_progress
# ... worker does the work ...
bd close auth-001

# 10. Next bead unblocks automatically
bd ready
# OUTPUT:
# 📋 Ready work (1 issue with no blockers):
# 1. [P2] [task] auth-002: JWT middleware
```

---

## Success Criteria

### Automated Verification

After implementation, run these commands to verify:

```bash
# 1. Agent files exist
ls -la .claude/agents/bead-decomposer.md
ls -la .claude/agents/bead-validator.md

# 2. Test decomposition on a sample plan
# (create a test plan first, then spawn the agent)

# 3. Verify beads created correctly
bd list --status=open
bd show <epic-id>
bd blocked
bd ready

# 4. Verify dependency direction
bd show <epic-id>  # Should show "Depends on: <child-ids>"
bd show <child-id>  # Should show "Blocks: <epic-id>"
```

### Manual Verification
- [ ] Agent files follow standard frontmatter format
- [ ] bead-decomposer creates epic + task beads correctly
- [ ] bead-decomposer adds ralph_spec to every bead
- [ ] bead-decomposer sets correct dependency direction (epic depends on children)
- [ ] bead-validator reads decomposer output to find bead IDs
- [ ] bead-validator fixes issues via bd commands
- [ ] bead-validator flags unfixable issues for human review
- [ ] Bead descriptions are self-contained (readable without plan)
- [ ] Dependencies correctly model blocking relationships
- [ ] A new worker agent could claim a bead and complete it

---

## Open Questions

*All key design decisions have been resolved - see Design Decisions table above.*

---

## Implementation Notes

### Dependency Direction (CRITICAL)

```bash
# CORRECT: Epic depends on ALL children (repeat for each child bead)
bd dep add <epic-id> <child-1-id>
bd dep add <epic-id> <child-2-id>
bd dep add <epic-id> <child-3-id>
# ... repeat for every child bead

# Result:
# - children: READY (no blockers)
# - epic: BLOCKED (waiting for all children to complete)
```

```bash
# WRONG: This blocks children forever!
bd dep add <child-id> <epic-id>

# Result:
# - child: BLOCKED (waiting for epic)
# - epic: READY (but meaningless)
```

**Important:** The epic must depend on ALL task beads, including those that have inter-task dependencies. This ensures the epic only closes when every task is complete.

### Context Distribution Strategy

For each bead, extract ONLY the relevant subset:

| Include | Exclude |
|---------|---------|
| Files this bead touches | Files for other beads |
| Patterns this bead needs | All patterns from plan |
| Edge cases this bead handles | Edge cases for other beads |
| Acceptance criteria for THIS bead | Full feature criteria |
| Enough context to work independently | Full plan content |

---

## Out of Scope

- Worker agent implementation (kraken, spark handle execution)
- `bd` CLI changes (using existing commands)
- Plan creation (handled by plan-agent, architect)
- Plan validation (handled by validate-agent, plan-reviewer)
