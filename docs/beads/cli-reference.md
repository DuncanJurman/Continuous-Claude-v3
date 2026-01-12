# CLI Reference: bd Command

Complete reference for the `bd` command-line interface.

## Command Structure

```bash
bd <command> [options] [arguments]
```

## Global Options

Available for all commands:
- `--help, -h` - Show help for command
- `--version, -v` - Show beads version

---

## Core Commands

### `bd init`

Initialize beads in the current project.

```bash
bd init
```

**What it does:**
- Creates `.beads/` directory structure
- Initializes config and index files
- Sets up git integration
- Configures hooks

**When to use:**
- First-time setup in a new repository
- After cloning a repo without beads

---

### `bd create`

Create a new issue.

```bash
bd create --title="Issue title" [options]
```

**Options:**
- `--title="..."` - Issue title (required)
- `--type=TYPE` - Issue type: `task`, `bug`, `feature`, `epic` (default: `task`)
- `--priority=N` - Priority: 0-4 or P0-P4 (0=critical, 4=backlog, default: 2)
- `--assignee=USERNAME` - Assign to user
- `--description="..."` - Issue description
- `--epic=EPIC_ID` - Associate with epic

**Examples:**
```bash
# Simple task
bd create --title="Fix login bug" --type=bug --priority=1

# Feature with description
bd create --title="Add dark mode" --type=feature \
  --description="Implement dark mode toggle in settings"

# Task assigned to user
bd create --title="Write tests" --type=task --assignee=alice
```

**Parallel Creation:**
For efficiency when creating multiple issues, use parallel subagents.

---

### `bd list`

List issues with optional filters.

```bash
bd list [options]
```

**Options:**
- `--status=STATUS` - Filter by status: `open`, `in_progress`, `blocked`, `closed`
- `--type=TYPE` - Filter by type: `task`, `bug`, `feature`, `epic`
- `--priority=N` - Filter by priority: 0-4 or P0-P4
- `--assignee=USERNAME` - Filter by assignee
- `--epic=EPIC_ID` - Show issues in epic

**Examples:**
```bash
# All open issues
bd list --status=open

# Active work
bd list --status=in_progress

# High priority bugs
bd list --type=bug --priority=1

# Alice's tasks
bd list --assignee=alice
```

---

### `bd show`

Show detailed information about an issue.

```bash
bd show <issue-id>
```

**What it shows:**
- Issue metadata (title, status, priority, type)
- Description
- Timestamps (created, updated)
- Assignee
- Dependencies (depends on / blocks)
- Comments
- Epic relationship

**Example:**
```bash
bd show beads-123
bd show entropy-wiki-3ph.1
```

---

### `bd update`

Update an issue's fields.

```bash
bd update <issue-id> [options]
```

**Options:**
- `--status=STATUS` - Update status: `open`, `in_progress`, `blocked`, `closed`
- `--priority=N` - Update priority: 0-4 or P0-P4
- `--assignee=USERNAME` - Change assignee
- `--title="..."` - Update title
- `--description="..."` - Update description
- `--type=TYPE` - Change type

**Examples:**
```bash
# Start work
bd update beads-123 --status=in_progress

# Change priority
bd update beads-123 --priority=0

# Reassign
bd update beads-123 --assignee=bob

# Multiple fields
bd update beads-123 --status=blocked --priority=1
```

---

### `bd close`

Close one or more issues.

```bash
bd close <issue-id> [<issue-id> ...] [options]
```

**Options:**
- `--reason="..."` - Reason for closing

**Examples:**
```bash
# Close single issue
bd close beads-123

# Close multiple (efficient)
bd close beads-123 beads-124 beads-125

# Close with reason
bd close beads-123 --reason="Duplicate of beads-456"
```

**Best Practice:** Close multiple issues in one command for efficiency.

---

### `bd reopen`

Reopen a closed issue.

```bash
bd reopen <issue-id>
```

**Example:**
```bash
bd reopen beads-123
```

---

## Discovery Commands

### `bd ready`

Show issues ready to work (no blockers).

```bash
bd ready
```

**What it shows:**
- Open issues with no open dependencies
- Sorted by PageRank (unblocking priority)
- Priority level indicated

**Example output:**
```
📋 Ready work (3 issues with no blockers):

1. [P1] [epic] beads-100: Major Feature
2. [P2] [task] beads-101: Implement API
3. [P2] [bug] beads-102: Fix cache issue
```

**Use this to:** Find your next task.

---

### `bd blocked`

Show all blocked issues.

```bash
bd blocked
```

**What it shows:**
- Issues with open dependencies
- Issues with status=blocked
- What each issue is blocked by

**Use this to:** Identify bottlenecks and unblocking work.

---

### `bd search`

Search issues by text query.

```bash
bd search <query>
```

**What it searches:**
- Issue titles
- Descriptions
- Comments

**Example:**
```bash
bd search "authentication"
bd search "API endpoint"
```

---

## Dependency Commands

### `bd dep add`

Add a dependency relationship.

```bash
bd dep add <issue> <depends-on>
```

**Meaning:** `<issue>` depends on `<depends-on>`
- `<depends-on>` blocks `<issue>`
- `<depends-on>` must complete first

**Example:**
```bash
# Tests depend on Feature
bd dep add beads-tests beads-feature
# Feature blocks Tests
```

---

### `bd dep remove`

Remove a dependency relationship.

```bash
bd dep remove <issue> <depends-on>
```

**Example:**
```bash
bd dep remove beads-tests beads-feature
```

---

## Comment Commands

### `bd comments`

View or manage comments on an issue.

```bash
# View comments
bd comments <issue-id>

# Add comment
bd comments <issue-id> --add="Comment text"
```

**Example:**
```bash
# View all comments
bd comments beads-123

# Add comment
bd comments beads-123 --add="Found root cause in auth module"
```

---

## Epic Commands

### `bd epic`

Manage epics and their child issues.

```bash
# Show epic tree
bd epic <epic-id>

# Add issue to epic
bd epic <epic-id> --add=<issue-id>

# Remove issue from epic
bd epic <epic-id> --remove=<issue-id>
```

**Example:**
```bash
# Show epic with children
bd epic beads-epic-1

# Associate task with epic
bd epic beads-epic-1 --add=beads-task-123
```

---

## Label Commands

### `bd label`

Manage issue labels.

```bash
# Add label
bd label <issue-id> --add="label-name"

# Remove label
bd label <issue-id> --remove="label-name"

# List labels
bd label <issue-id>
```

**Example:**
```bash
bd label beads-123 --add="needs-review"
bd label beads-123 --remove="in-progress"
```

---

## Sync Commands

### `bd sync`

Synchronize issues with git remote.

```bash
# Manual sync (rarely needed, daemon handles this)
bd sync

# Check sync status
bd sync --status
```

**What it does:**
- Commits local changes to `.beads/`
- Pushes to remote repository
- Pulls remote changes
- Resolves conflicts if any

**Note:** Daemon auto-syncs when configured. Manual sync rarely needed.

---

### `bd daemon`

Manage background sync daemon.

```bash
# Start daemon
bd daemon start

# Stop daemon
bd daemon stop

# Check status
bd daemon status
```

**Daemon features:**
- Auto-commit on issue changes
- Auto-push to remote
- Auto-pull from remote
- Configurable intervals

---

## Maintenance Commands

### `bd compact`

Compact old closed issues using semantic summarization.

```bash
bd compact [options]
```

**Options:**
- `--days=N` - Compact issues closed more than N days ago (default: 30)
- `--dry-run` - Show what would be compacted without doing it

**What it does:**
- Semantically summarizes closed issues
- Reduces `.beads/` directory size
- Maintains history in git
- Issues can be restored

**Example:**
```bash
# Compact issues closed >30 days ago
bd compact

# Compact older issues
bd compact --days=60

# Preview compaction
bd compact --dry-run
```

---

### `bd restore`

Restore full history of compacted issue from git.

```bash
bd restore <issue-id>
```

**Example:**
```bash
bd restore beads-123
```

---

### `bd doctor`

Check for issues and inconsistencies.

```bash
bd doctor
```

**What it checks:**
- Sync status (local vs remote)
- Missing or corrupted issue files
- Index consistency
- Git integration health
- Hook configuration
- Daemon status

**Use this when:** Something seems wrong or after major changes.

---

### `bd stats`

Show project statistics and progress.

```bash
bd stats
```

**What it shows:**
- Issue counts by status
- Issue counts by type
- Issue counts by priority
- Blocked vs ready ratio
- Completion trends

**Example output:**
```
Project Statistics:
  Total issues: 42
  Open: 15
  In Progress: 3
  Blocked: 5
  Closed: 19

By Type:
  Tasks: 25
  Bugs: 10
  Features: 5
  Epics: 2

By Priority:
  P0: 1
  P1: 5
  P2: 20
  P3: 10
  P4: 6
```

---

## Import/Export Commands

### `bd export`

Export issues to JSONL format.

```bash
bd export [options] > output.jsonl
```

**Options:**
- `--status=STATUS` - Export only specific status
- `--type=TYPE` - Export only specific type

**Use cases:**
- Backup
- Migration
- Analysis
- Integration with other tools

---

### `bd import`

Import issues from JSONL format.

```bash
bd import <file.jsonl>
```

**Use cases:**
- Restore from backup
- Migrate from other systems
- Bulk issue creation

---

## Advanced Commands

### `bd delete`

Delete issues and clean up references.

```bash
bd delete <issue-id> [<issue-id> ...]
```

**Warning:** Destructive operation. Use with caution.

**What it does:**
- Removes issue file
- Cleans up dependencies
- Removes from epics
- Updates index

---

### `bd rename-prefix`

Rename the issue prefix for all issues.

```bash
bd rename-prefix <old-prefix> <new-prefix>
```

**Example:**
```bash
bd rename-prefix beads myproject
# beads-123 becomes myproject-123
```

---

## Hook Integration

### `bd prime`

Load context from beads for AI agents.

```bash
bd prime
```

**What it does:**
- Summarizes open and in-progress issues
- Highlights blocked items
- Shows ready-to-work tasks
- Provides context for session recovery

**When to use:**
- After conversation compaction
- After `/clear` command
- Starting new session
- Context recovery needed

**Note:** Automatically called by hooks when `.beads/` detected.

---

## Configuration

Beads configuration is stored in `.beads/config.json`.

**Common settings:**
- Issue prefix (default: "beads")
- Daemon settings (intervals, auto-sync)
- Compaction threshold (days)
- PageRank parameters

Edit via:
```bash
# Direct edit
vim .beads/config.json

# Or use bd commands to modify behavior
```

---

## Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid arguments
- `3` - Git error
- `4` - Sync conflict

---

## Common Workflows

### Starting Work
```bash
bd ready                              # Find available work
bd show <id>                          # Review details
bd update <id> --status=in_progress   # Claim it
```

### Completing Work
```bash
bd close <id1> <id2> <id3>            # Close all done issues
git add . && git commit -m "..."      # Commit code
git push                              # Push (beads auto-synced)
```

### Creating Dependent Work
```bash
bd create --title="Feature X"         # Create parent
bd create --title="Test X"            # Create child
bd dep add <test-id> <feature-id>     # Tests depend on feature
```

### Checking Health
```bash
bd stats                              # Overall metrics
bd blocked                            # Bottlenecks
bd doctor                             # System health
```

---

## Tips for AI Agents

1. **Use `bd ready` first** - Always check for unblocked work
2. **Close in batches** - `bd close id1 id2 id3` is more efficient
3. **Trust PageRank** - Don't second-guess the priority ordering
4. **One task at a time** - Only one issue should be `in_progress`
5. **Immediate updates** - Update status as soon as state changes
6. **Document blockers** - Use comments when setting `blocked` status
7. **Check downstream** - Use `bd show` to see what you're unblocking
8. **Parallel creation** - Use subagents to create multiple issues efficiently
