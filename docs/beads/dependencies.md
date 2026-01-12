# Dependency Resolution

## Overview

Beads uses a dependency graph to model blocking relationships between issues. Dependencies enable:
- Explicit ordering constraints ("A must complete before B")
- Automatic priority surfacing via PageRank
- Blocking/unblocking cascade detection
- Strategic work sequencing

## Dependency Model

### Terminology

**Dependency Relationship:**
```
Issue A depends on Issue B
  = Issue A is blocked by Issue B
  = Issue B blocks Issue A
  = B must complete before A can proceed
```

**Graph Representation:**
- **Nodes:** Individual issues
- **Edges:** Dependency relationships (directed)
- **Direction:** Edge points from dependent to dependency
  - `A → B` means "A depends on B" (B blocks A)

### Dependency Commands

**Add Dependency:**
```bash
bd dep add <issue> <depends-on>
# Example: Task depends on Feature
bd dep add beads-123 beads-122
# Means: beads-123 is blocked by beads-122
```

**Remove Dependency:**
```bash
bd dep remove <issue> <depends-on>
```

**View Dependencies:**
```bash
bd show <issue-id>
# Shows:
# - Depends on: Issues blocking this one
# - Blocks: Issues blocked by this one
```

## PageRank-Based Priority

### Why PageRank?

Traditional priority systems (P0-P4) are static and don't account for strategic impact. PageRank dynamically calculates importance based on how many issues a given issue unblocks.

**Core Insight:** Issues that unblock many other issues should be prioritized, even if their nominal priority is lower.

### How It Works

1. **Graph Construction:**
   - Build directed graph from dependency relationships
   - Each issue is a node
   - Each dependency is a directed edge

2. **PageRank Calculation:**
   - Standard PageRank algorithm (like Google Search)
   - Iterative: importance flows from blocked issues to blocking issues
   - Converges to stable importance scores

3. **Priority Adjustment:**
   - Issues with high PageRank bubble up in `bd ready`
   - Unblocking work becomes visible
   - Strategic bottlenecks get surfaced

### Example

```
Issue A (Feature) [P2]
  ↓ blocks
Issue B (Tests) [P2]
Issue C (Docs) [P2]
Issue D (Deploy) [P1]

PageRank scoring:
- Issue A: HIGH (blocks 3 issues)
- Issue B: LOW (blocks 0 issues)
- Issue C: LOW (blocks 0 issues)
- Issue D: MEDIUM (blocks 0 but P1)

Result: Issue A surfaces in bd ready despite being P2
```

### When PageRank Helps

**Scenario 1: Hidden Bottlenecks**
- 10 tasks all depend on one infrastructure issue
- Infrastructure issue gets highest PageRank
- Surfaces as top priority automatically

**Scenario 2: Cascade Unblocking**
- Complete one critical issue
- PageRank recalculates
- Next bottleneck surfaces immediately

**Scenario 3: Long Dependency Chains**
- A → B → C → D
- PageRank identifies C and D as low priority (deep in chain)
- Focuses attention on A (head of chain)

## Blocking States

### Automatic Blocking Detection

Issues are automatically considered blocked if:
1. They have open dependencies (`Depends on` field has open issues)
2. Status is explicitly set to `blocked`

**Check Blocked Issues:**
```bash
bd blocked
# Shows all issues that:
# - Have open dependencies, OR
# - Status = blocked
```

### Unblocking Cascade

When you close an issue that blocks others:
1. Beads detects dependent issues
2. Those issues may become unblocked
3. `bd ready` output updates automatically
4. PageRank recalculates for remaining graph

**Example:**
```bash
# Before
bd blocked
  → Issue B (blocked by Issue A)
  → Issue C (blocked by Issue A)

bd close A

# After
bd ready
  → Issue B (now unblocked)
  → Issue C (now unblocked)
```

## Dependency Best Practices

### For AI Agents

1. **Explicit Dependencies:** Always add dependencies when discovered
   ```bash
   # Discovered: tests need feature implementation
   bd dep add beads-tests-456 beads-feature-123
   ```

2. **Parallel Creation:** Create dependent work immediately
   ```bash
   # Create feature and tests together
   bd create --title="Implement feature X"
   bd create --title="Test feature X"
   bd dep add beads-xxx beads-yyy
   ```

3. **Trust PageRank:** Let `bd ready` guide prioritization
   - Don't override just because P0 looks urgent
   - PageRank accounts for strategic unblocking

4. **Check Downstream:** Before starting work, check what it unblocks
   ```bash
   bd show <issue-id>
   # Look at "Blocks:" field
   # High-value if it unblocks many issues
   ```

### Common Patterns

**Epic → Task Dependencies:**
```bash
bd create --title="Epic: Major Feature" --type=epic
bd create --title="Task 1: Component A" --type=task
bd create --title="Task 2: Component B" --type=task
bd dep add beads-epic beads-task1
bd dep add beads-epic beads-task2
# Epic depends on tasks (tasks block epic)
```

**Sequential Dependencies:**
```bash
bd create --title="1. Database schema"
bd create --title="2. API endpoints"
bd create --title="3. Frontend UI"
bd dep add beads-002 beads-001
bd dep add beads-003 beads-002
# Linear chain: 1 → 2 → 3
```

**Fan-out Dependencies:**
```bash
bd create --title="Core library"
bd create --title="Service A uses library"
bd create --title="Service B uses library"
bd create --title="Service C uses library"
bd dep add beads-serviceA beads-core
bd dep add beads-serviceB beads-core
bd dep add beads-serviceC beads-core
# Core library blocks many services
```

## Graph Health

### Detecting Problems

**Circular Dependencies:**
```bash
# BAD: A → B → A (circular)
bd dep add A B
bd dep add B A
# Beads should error or warn
```

**Orphaned Issues:**
- Issues with no dependencies and no dependents
- May indicate poor planning or missed relationships
- Use `bd stats` and `bd show` to audit

**Deeply Nested Chains:**
- A → B → C → D → E (5+ levels deep)
- May indicate over-planning
- Consider collapsing or reorganizing

### Maintenance

**Regular Audits:**
```bash
bd blocked     # Check blocked issues
bd ready       # Check available work
bd stats       # Overall health metrics
```

**Dependency Cleanup:**
- Remove dependencies when requirements change
- Close issues that are no longer relevant
- Reorganize chains that become too complex

## Integration with Lifecycle

Dependencies affect lifecycle transitions:

1. **Open → In Progress:**
   - Only possible if all dependencies closed
   - Check with `bd ready` or `bd show`

2. **In Progress → Blocked:**
   - Manual transition when blocker discovered
   - Add dependency: `bd dep add <issue> <blocker>`

3. **Blocked → In Progress:**
   - Automatic when dependencies close
   - Or manual if blocker resolved externally

4. **Closing Issues:**
   - Check what it unblocks: `bd show <issue-id>`
   - May trigger cascade of unblocking

## Advanced: Custom Priority

While PageRank handles most cases, you can still use static priority:

```bash
bd update <issue-id> --priority=0  # Critical (P0)
bd update <issue-id> --priority=1  # High (P1)
bd update <issue-id> --priority=2  # Medium (P2)
bd update <issue-id> --priority=3  # Low (P3)
bd update <issue-id> --priority=4  # Backlog (P4)
```

**When to Override PageRank:**
- Time-sensitive issues (deadlines, incidents)
- External dependencies (partner teams, infrastructure)
- Business-critical vs technical-critical mismatch

**Best Practice:** Use priority sparingly. Trust PageRank for most strategic decisions.
