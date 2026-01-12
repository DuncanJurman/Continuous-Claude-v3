---
description: Start the god-ralph orchestrator to autonomously execute ready beads
---

# /god-ralph start

Start the god-ralph orchestrator to autonomously execute all ready beads.

## Behavior

1. **Dry-run first**: Show execution plan before starting
2. **User confirmation**: Wait for approval before executing
3. **Launch orchestrator**: Start the persistent orchestrator agent

## Execution

First, show the execution plan:

```bash
# Check for ready beads
echo "📋 god-ralph Execution Plan"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get ready beads
bd ready --json 2>/dev/null || echo '{"issues": []}'
```

Display the plan:
- Number of ready beads
- Parallelism groups (based on file overlap analysis)
- Estimated iterations
- Estimated cost

Then ask user for confirmation:
- If confirmed → Launch orchestrator agent
- If declined → Exit

## Arguments

- `--no-dry-run`: Skip dry-run, start immediately
- `--max-parallel N`: Maximum parallel Ralphs (default: auto)
- `--max-iterations N`: Override max iterations per bead (default: 50)

## Setup

Before launching orchestrator:

```bash
# Create state directory
mkdir -p .claude/god-ralph/logs

# Initialize orchestrator state
cat > .claude/god-ralph/orchestrator-state.json << EOF
{
  "status": "starting",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "active_ralphs": [],
  "completed_beads": [],
  "failed_beads": [],
  "total_iterations": 0
}
EOF
```

## Orchestrator Launch

After user confirms, invoke the orchestrator agent using the Task tool:

```
Task(
  subagent_type="god-ralph-orchestrator",
  prompt="Execute the orchestrator workflow as defined in agents/orchestrator.md.

  Start by:
  1. Reading bd ready --json to find ready beads
  2. Analyzing parallelism
  3. Spawning Ralph workers
  4. Monitoring and merging

  Continue until no ready beads remain or user stops.",
  description="god-ralph orchestrator"
)
```

## Example Output

```
📋 god-ralph Execution Plan
━━━━━━━━━━━━━━━━━━━━━━━━━━

Ready beads: 5
  - beads-abc: "Add user settings API"
  - beads-def: "Implement dark mode toggle"
  - beads-ghi: "Fix login validation bug"
  - beads-jkl: "Add password reset flow"
  - beads-mno: "Update user profile page"

Parallelism analysis:
  Group 1: beads-abc, beads-ghi (no file overlap)
  Group 2: beads-def, beads-mno (depends on Group 1, UI changes)
  Group 3: beads-jkl (auth system, sequential)

Estimated:
  - Iterations: 45-75
  - Cost: $15-25
  - Time: 30-60 minutes

Proceed with execution? [y/n]
```

## References

- [orchestrator.md](../agents/orchestrator.md) - Orchestrator agent definition
- [BEAD_SPEC.md](../skills/god-ralph/references/BEAD_SPEC.md) - Ralph-ready bead format
- [WORKFLOWS.md](../skills/god-ralph/references/WORKFLOWS.md) - Common workflows

## Notes

- The orchestrator runs persistently until stopped or all work complete
- Use `/god-ralph status` to check progress
- Use `/god-ralph stop` to gracefully halt execution
- Logs saved to `.claude/god-ralph/logs/`
