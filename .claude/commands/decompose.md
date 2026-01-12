# Decompose Plan into Beads

Orchestrates bead-decomposer and bead-validator agents to transform an approved plan into atomic, executable beads.

## Usage

```
/decompose <plan-path>
```

## Arguments

- `plan-path`: Path to the approved plan file (e.g., `thoughts/shared/plans/PLAN-auth-system.md`)

## Workflow

1. **Spawn bead-decomposer** with the plan path
   - Reads and analyzes the plan
   - Checks for duplicates
   - Creates epic + task beads
   - Establishes dependencies (epic depends on children)
   - Adds ralph_spec to each bead
   - Writes decomposition report

2. **Spawn bead-validator** with plan path + decomposer output
   - Reads decomposer output to get bead IDs
   - Validates each bead against checklist
   - Fixes issues via bd commands
   - Flags unfixable issues for human review
   - Writes validation report

3. **Return final status**
   - VALIDATED: All beads ready for workers
   - NEEDS_ATTENTION: Some beads need human review

## Example

```bash
# After plan-reviewer approves a plan
/decompose thoughts/shared/plans/PLAN-auth-system.md

# Result: Creates beads like auth-epic, auth-001, auth-002, auth-003
# Workers can then run: bd ready
```

## Output Locations

- Decomposer: `.claude/cache/agents/bead-decomposer/PLAN-<slug>-output.md`
- Validator: `.claude/cache/agents/bead-validator/PLAN-<slug>-output.md`

Both also update `latest-output.md` as a convenience pointer.

---

## Implementation

When this skill is invoked with a plan path, execute:

### Step 1: Validate Input

Ensure the plan file exists:
```bash
if [ ! -f "$1" ]; then
  echo "Error: Plan file not found: $1"
  exit 1
fi
```

### Step 2: Spawn bead-decomposer

```
Task(
  subagent_type="bead-decomposer",
  model="opus",
  prompt="
## Plan File
$CLAUDE_PROJECT_DIR/$1

## Context
Plan has been approved. Decompose into atomic beads with:
- Feature-based prefix (slugify plan title)
- Epic + task beads
- Proper dependencies (epic depends on ALL children)
- ralph_spec for each bead
- Output report for validator

$CLAUDE_PROJECT_DIR = $(pwd)
"
)
```

### Step 3: Wait for Decomposer Completion

The decomposer will write to:
- `.claude/cache/agents/bead-decomposer/PLAN-<slug>-output.md`
- `.claude/cache/agents/bead-decomposer/latest-output.md`

### Step 4: Spawn bead-validator

```
Task(
  subagent_type="bead-validator",
  model="opus",
  prompt="
## Plan File
$CLAUDE_PROJECT_DIR/$1

## Decomposer Output
$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md

## Context
Validate and refine all beads created by the decomposer:
- Check context sufficiency (can worker understand without plan?)
- Verify acceptance criteria are specific and testable
- Confirm dependencies are correct
- Fix issues via bd commands
- Flag unfixable issues for human review

$CLAUDE_PROJECT_DIR = $(pwd)
"
)
```

### Step 5: Report Final Status

Read validator output and report:
- Number of beads validated
- Issues found and fixed
- Remaining issues (if any)
- Final status: VALIDATED or NEEDS_ATTENTION

If VALIDATED, workers can claim beads via `bd ready`.

---

## Prerequisites

- Plan must be approved (typically after plan-reviewer)
- `bd` CLI must be available
- `.beads/` directory initialized in project

## Next Steps After Decomposition

```bash
# See available work
bd ready

# Workers claim and complete beads
bd update <bead-id> --status=in_progress
# ... do the work ...
bd close <bead-id>
```

## Troubleshooting

**Decomposer fails:**
- Check if plan file exists and is readable
- Verify `bd` CLI is working: `bd list`
- Check for existing beads with same prefix

**Validator finds many issues:**
- Review decomposer output for quality
- Consider re-running decomposer with clearer plan
- Some issues require human review (granularity changes)

**Beads not showing in `bd ready`:**
- Check dependency direction: epic should depend on children
- Verify beads are `open` status: `bd list --status=open`
- Check for blocking dependencies: `bd blocked`
