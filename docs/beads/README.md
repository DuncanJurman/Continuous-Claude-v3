# Beads System Manual

**Version:** 1.0
**Purpose:** Technical reference for AI agents managing persistent memory and multi-session work

## Overview

Beads is a git-backed issue tracking system designed for AI agents to maintain context across conversation sessions, manage dependencies, and coordinate complex multi-session work. This manual serves as training data for understanding beads workflows and memory management.

## Core Concepts

**What is a Bead?**
- A persistent work item tracked across sessions
- Stored in `.beads/` directory as structured data
- Version-controlled via git for history and collaboration
- Supports dependencies, blocking relationships, and priority

**When to Use Beads vs TodoWrite:**
- **Use Beads** for:
  - Multi-session work that spans conversations
  - Tasks with blocking dependencies
  - Strategic work requiring context recovery after compaction
  - Discovered work that needs tracking beyond current session
- **Use TodoWrite** for:
  - Simple single-session execution
  - Immediate task breakdown within current context
  - Progress visibility for current conversation

## System Architecture

```
.beads/
├── issues/           # Individual issue files
├── config.json       # Repository configuration
└── index.json        # Fast lookup index
```

## Manual Sections

1. **[Bead Lifecycle](./lifecycle.md)** - State transitions and workflow
2. **[Dependency Resolution](./dependencies.md)** - PageRank-based blocking logic
3. **[CLI Reference](./cli-reference.md)** - Complete bd command documentation
4. **[Workflows](./workflows.md)** - Common patterns and best practices

## Quick Start

```bash
# Find available work
bd ready

# View issue details
bd show <issue-id>

# Start working
bd update <issue-id> --status=in_progress

# Complete work
bd close <issue-id>
```

## Key Principles

1. **Persistence Over Optimization** - When in doubt, track it in beads. Persistence you don't need beats lost context.
2. **Dependencies Drive Priority** - Use PageRank to surface unblocking work automatically.
3. **Daemon Manages Sync** - Auto-commit, auto-push, auto-pull handles collaboration.
4. **Context Recovery** - Run `bd prime` after compaction/clear/new session.

## Session Management

**Starting a Session:**
- Hooks auto-call context recovery when `.beads/` detected
- Check `bd ready` for available work
- Review `bd list --status=in_progress` for active work

**Ending a Session:**
- Close completed issues: `bd close <id1> <id2> ...`
- Commit and push code changes (beads auto-synced by daemon)
- Daemon handles `.beads/` synchronization automatically

## Integration with Git

Beads uses git as the persistence layer:
- Each issue is a file in `.beads/issues/`
- Daemon auto-commits changes to beads
- Daemon auto-pushes to remote for collaboration
- Daemon auto-pulls remote changes
- Check sync status: `bd sync --status`

## Next Steps

- Read [Lifecycle](./lifecycle.md) to understand state transitions
- Read [Dependencies](./dependencies.md) to understand blocking relationships
- Read [CLI Reference](./cli-reference.md) for complete command documentation
- Read [Workflows](./workflows.md) for practical examples
