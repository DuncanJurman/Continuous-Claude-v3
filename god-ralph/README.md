# god-ralph

Autonomous development orchestrator combining ephemeral Ralph workers with Beads granular task tracking.

## What is god-ralph?

god-ralph automates software development by:
1. Breaking work into granular, trackable **beads**
2. Spawning **ephemeral Ralphs** to complete each bead
3. Running **parallel execution** on independent tasks
4. **Verifying** merged work automatically
5. Creating **fix-beads** when things break

## Installation

```bash
# Clone or copy to your plugins directory
cp -r god-ralph ~/.claude/plugins/

# Or use --plugin-dir for testing
claude --plugin-dir ~/Desktop/entropy-plugins/god-ralph
```

## Quick Start

```bash
# 1. Create some beads
bd create --title="Add user API" --type=feature --priority=2

# 2. Add acceptance criteria (in comments for now)
bd comments beads-xxx --add "ralph_spec:
completion_promise: BEAD COMPLETE
acceptance_criteria:
  - type: test
    command: npm test"

# 3. Start autonomous execution
/god-ralph start
```

## Commands

| Command | Description |
|---------|-------------|
| `/god-ralph start` | Start orchestrator (dry-run first) |
| `/god-ralph plan` | Interactive bead creation wizard |
| `/god-ralph status` | Show current progress |
| `/god-ralph stop` | Gracefully stop execution |
| `/god-ralph <id>` | Run Ralph on specific bead |

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│         god-ralph Orchestrator          │
│         (Persistent Agent)              │
└─────────────────────────────────────────┘
         │         │         │
         ▼         ▼         ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │ Ralph  │ │ Ralph  │ │ Ralph  │
    │ bead-1 │ │ bead-2 │ │ bead-3 │
    └────────┘ └────────┘ └────────┘
    worktree/1 worktree/2 worktree/3
```

### Execution Flow

1. **Discovery**: Find ready beads via `bd ready`
2. **Analysis**: Determine parallelism (file overlap detection)
3. **Spawn**: Create worktrees, launch Ralphs
4. **Monitor**: Stream progress, track iterations
5. **Merge**: Auto-merge completed branches
6. **Verify**: Run acceptance criteria
7. **Continue**: Close beads, spawn next batch

### Ephemeral Workers

Each Ralph:
- Works on exactly ONE bead
- Iterates until completion or max iterations
- Commits progress to feature branch
- Dies after completion

### Git Isolation

```
Main repo:     /project/              → main
Worktree 1:    .worktrees/ralph-1/    → ralph/bead-123
Worktree 2:    .worktrees/ralph-2/    → ralph/bead-456
```

## Bead Format

```yaml
title: "Add settings API"
description: "GET and POST /api/settings"
type: feature
priority: 2

ralph_spec:
  completion_promise: "BEAD COMPLETE"
  max_iterations: 50
  acceptance_criteria:
    - type: test
      command: "npm test"
    - type: lint
      command: "npm run lint"
```

## Requirements

- Claude Code with plugin support
- Beads CLI (`bd`) installed
- Git repository

## Philosophy

god-ralph embodies the Ralph Wiggum principle: **"deterministically bad in an undeterministic world"**.

By making failures predictable (max iterations, acceptance criteria), we can:
- Tune the guardrails instead of the model
- Fail fast and fix forward
- Let the system iterate without babysitting

## License

MIT
