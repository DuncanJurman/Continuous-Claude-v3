# Continuous Claude v3 - Architecture Guide

## Executive Summary

Continuous Claude v3 is an **agentic AI development environment** built on top of Claude Code with **autonomous parallel execution via God-Ralph**. It transforms a single AI assistant into a coordinated system of specialized agents that execute work in parallel, with automatic context management, semantic memory, and token-efficient code analysis.

**The Core Workflow: Plan → Decompose → Execute**

Instead of working on tasks one-by-one, the system:
1. **Plans** features with architect agents
2. **Decomposes** plans into atomic "beads" (self-contained work units)
3. **Executes** beads in parallel via Ralph workers in isolated git worktrees

Think of it as "VS Code + GitHub Copilot, but the AI plans your feature, breaks it into tasks, and completes them all autonomously in parallel."

The system has five main layers: **God-Ralph** (parallel execution engine), **Skills** (what users can trigger), **Hooks** (automatic behaviors), **Agents** (specialized sub-assistants), and **Infrastructure** (persistence and analysis tools).

---

## Architecture Diagram

```
+-----------------------------------------------------------------------------------+
|                              USER INTERACTION                                      |
|  "build a user settings page" | "execute the beads" | "check ralph status"        |
+-----------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                           SKILL ACTIVATION LAYER                                   |
|  skill-rules.json -> keyword/intent matching -> skill suggestion/injection         |
|  /build greenfield -> /decompose -> /ralph start                                   |
+-----------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                         GOD-RALPH LAYER (Primary Execution Engine)                 |
|                                                                                    |
|  +------------------+     +------------------+     +------------------+            |
|  |   PLANNING       |     |   DECOMPOSITION  |     |   EXECUTION      |            |
|  | - architect      | --> | - bead-decomposer| --> | - orchestrator   |            |
|  | - plan-agent     |     | - bead-validator |     | - ralph-workers  |            |
|  | - premortem      |     |                  |     | - verify-ralph   |            |
|  +------------------+     +------------------+     +------------------+            |
|                                                            |                       |
|  +--------------------------------------------------+      |                       |
|  |                   WORKTREE ISOLATION              |      |                       |
|  | .worktrees/                                       |<-----+                       |
|  |   ralph-beads-001/ (parallel) <-- ralph-worker    |                             |
|  |   ralph-beads-002/ (parallel) <-- ralph-worker    |                             |
|  |   ralph-beads-003/ (parallel) <-- ralph-worker    |                             |
|  +--------------------------------------------------+                              |
|                           |                                                        |
|                           v                                                        |
|  +--------------------------------------------------+                              |
|  |              VERIFY-THEN-MERGE                    |                             |
|  | verification-ralph runs acceptance_criteria       |                             |
|  | PASS -> merge to main, bd close                   |                             |
|  | FAIL -> worktree preserved, bead stays open       |                             |
|  +--------------------------------------------------+                              |
|                           |                                                        |
|                           v                                                        |
|  +--------------------------------------------------+                              |
|  |              ralph-learner                        |                             |
|  | Extract insights -> store_learning.py -> memory   |                             |
|  | Update CLAUDE.md with durable patterns            |                             |
|  +--------------------------------------------------+                              |
+-----------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                               HOOK LAYER                                           |
|                                                                                    |
|  +-------------+    +---------------+    +--------------+    +----------------+   |
|  | SessionStart|    | UserPrompt    |    | PreToolUse   |    | PostToolUse    |   |
|  | - Continuity|    | - Skill inject|    | - Search rtr |    | - Compiler     |   |
|  | - Indexing  |    | - Braintrust  |    | - TLDR inject|    | - Handoff idx  |   |
|  +-------------+    +---------------+    | - ensure-    |    +----------------+   |
|                                          |   worktree   |                         |
|  +-------------+    +---------------+    +--------------+    +----------------+   |
|  | SubagentSt  |    | SubagentStop  |    | Stop         |    | SessionEnd     |   |
|  | - Register  |    | - Continuity  |    | - ralph-stop |    | - Cleanup      |   |
|  +-------------+    +---------------+    +--------------+    +----------------+   |
+-----------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                              AGENT LAYER (36 agents)                               |
|                                                                                    |
|  GOD-RALPH (4)                          ORCHESTRATORS (2)                         |
|  +-------------+  +-------------+       +----------+  +----------+                |
|  | orchestrator|  |ralph-worker |       | maestro  |  | kraken   |                |
|  +-------------+  +-------------+       +----------+  +----------+                |
|  +-------------+  +-------------+                                                  |
|  | verify-ralph|  |ralph-learner|       BEAD MANAGEMENT (2)                       |
|  +-------------+  +-------------+       +---------------+  +---------------+      |
|                                         |bead-decomposer|  | bead-validator|      |
|  PLANNERS (4)      DEBUGGERS (3)        +---------------+  +---------------+      |
|  +----------+      +----------+                                                    |
|  | architect|      | sleuth   |         EXPLORERS (4)      VALIDATORS (2)         |
|  | phoenix  |      | debug-agt|         +----------+       +----------+           |
|  | plan-agt |      | profiler |         | scout    |       | arbiter  |           |
|  | validate |      +----------+         | oracle   |       | atlas    |           |
|  +----------+                           +----------+       +----------+           |
+-----------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                           INFRASTRUCTURE LAYER                                     |
|                                                                                    |
|  +-------------------+  +-------------------+  +-------------------+               |
|  | TLDR-Code 5-Layer |  | PostgreSQL+pgvec  |  | File Persistence  |               |
|  | - AST (structure) |  | - sessions        |  | - thoughts/shared |               |
|  | - Call Graph      |  | - file_claims     |  |   - handoffs/     |               |
|  | - CFG (control)   |  | - archival_memory |  |   - plans/        |               |
|  | - DFG (data flow) |  | - handoffs        |  |   - ledgers/      |               |
|  | - PDG (deps)      |  |                   |  | - .claude/state/  |               |
|  +-------------------+  +-------------------+  |   god-ralph/      |               |
|                                                +-------------------+               |
|  +-------------------+  +-------------------+  +-------------------+               |
|  | Symbol Index      |  | Artifact Index    |  | MCP Servers       |               |
|  | /tmp/claude-      |  | (SQLite FTS5)     |  | - Firecrawl       |               |
|  | symbol-index/     |  | - handoffs        |  | - Perplexity      |               |
|  | symbols.json      |  | - plans           |  | - GitHub          |               |
|  | callers.json      |  | - continuity      |  | - AST-grep        |               |
|  +-------------------+  +-------------------+  +-------------------+               |
+-----------------------------------------------------------------------------------+
```

---

## 1. Capability Catalog (What Users Can Do)

Users activate capabilities through **natural language keywords**. No slash commands needed - the system detects intent.

### God-Ralph: Primary Execution Workflow

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Build Feature** | "build", "implement feature", "create feature" | Primary workflow: Plan → Decompose → Execute |
| **Decompose Plan** | "decompose", "break into beads", "create beads" | Breaks plan into atomic beads with `ralph_spec` |
| **Execute Beads** | "start ralph", "execute beads", "run beads" | Parallel execution via ralph-workers in worktrees |
| **Ralph Status** | "ralph status", "check ralph", "bead status" | Shows orchestrator state and progress |
| **Ralph Health** | "ralph health", "diagnose ralph" | Full health check with actionable fixes |
| **Ralph Recovery** | "recover bead", "ralph gc" | Recover failed beads, clean orphaned worktrees |

### Planning & Workflow

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Create Plan** | "create plan", "plan feature", "design" | Architect agent creates phased implementation plan |
| **Implement Plan** | "implement plan", "execute plan", "follow plan" | Routes to God-Ralph: decompose → ralph-workers |
| **Create Handoff** | "create handoff", "done for today", "wrap up" | Saves session state for future pickup |
| **Resume Handoff** | "resume handoff", "continue work", "pick up where" | Restores context from previous session |
| **Continuity Ledger** | "save state", "before compact", "low on context" | Creates checkpoint within session |

### Code Understanding (TLDR-Code)

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Call Graph** | "what calls", "who calls", "calls what" | Shows function call relationships |
| **Complexity Analysis** | "how complex", "cyclomatic" | CFG-based complexity metrics |
| **Data Flow** | "where does variable", "what sets" | Tracks variable origins and uses |
| **Program Slicing** | "what affects line", "dependencies" | PDG-based impact analysis |

### Search & Research

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Semantic Search** | "recall", "what worked", "past decisions" | Searches archival memory with embeddings |
| **Structural Search** | "ast", "find all calls", "refactor" | AST-grep for code patterns |
| **Text Search** | "grep", "find in code", "search for" | Fast text search via Morph/Grep |
| **Web Research** | "search the web", "look up", "perplexity" | AI-powered web search |
| **Documentation** | "docs", "how to use", "API reference" | Library docs via Nia |

### Code Quality

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Quality Check** | "lint", "code quality", "auto-fix" | Qlty CLI with 70+ linters |
| **TDD Workflow** | "implement", "add feature", "fix bug" | Forces test-first development |
| **Debug** | "debug", "investigate", "why is it" | Spawns debug-agent for investigation |

### Git & GitHub

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Commit** | "commit", "save changes", "push" | Git commit with user approval |
| **PR Description** | "describe pr", "create pr" | Generates PR description from changes |
| **GitHub Search** | "github", "search repo", "PR" | Searches GitHub via MCP |

### Math & Computation

| Capability | Trigger Keywords | What It Does |
|------------|-----------------|--------------|
| **Math Computation** | "calculate", "solve", "integrate" | SymPy, Z3, Pint computation |
| **Formal Proofs** | "prove", "theorem", "verify" | Lean 4 + Godel-Prover |

---

## 2. Hook Layer (Automatic Behaviors)

Hooks fire automatically at specific lifecycle points. Users don't invoke them directly - they just work.

### God-Ralph Hooks (Critical for Parallel Execution)

| Hook | Triggers On | What It Does |
|------|-------------|--------------|
| `ensure-worktree` | Task (ralph-worker) | Creates isolated git worktree, injects memory context ONCE at spawn |
| `ralph-stop-hook` | Stop (ralph-worker) | Re-invokes ralph-worker until completion promise or max iterations |
| `ralph-doc-only-check` | Edit (ralph-learner) | Restricts ralph-learner to documentation edits only |

**Hook Chain Order for ralph-worker spawn (CRITICAL):**

| Order | Hook | Modifies | Must Preserve |
|-------|------|----------|---------------|
| 1 | tldr-context-inject | prompt (prepend) | - |
| 2 | arch-context-inject | prompt (prepend) | tldr context |
| 3 | ensure-worktree | prompt (prepend) + cwd | tldr + arch context |

### PreToolUse Hooks

| Hook | Triggers On | What It Does |
|------|-------------|--------------|
| `path-rules` | Read, Edit, Write | Enforces file access patterns |
| `tldr-read-enforcer` | Read | Intercepts file reads, offers TLDR context instead |
| `smart-search-router` | Grep | Routes to AST-grep/LEANN/Grep based on query type |
| `tldr-context-inject` | Task | Adds code context to subagent prompts |
| `file-claims` | Edit | Tracks which session owns which files |
| `ensure-worktree` | Task (ralph-worker) | Creates worktree + memory injection |

### PostToolUse Hooks

| Hook | Triggers On | What It Does |
|------|-------------|--------------|
| `pattern-orchestrator` | Task | Manages multi-agent patterns (pipeline, jury, debate) |
| `typescript-preflight` | Edit, Write | Runs TypeScript compiler check |
| `handoff-index` | Write | Indexes handoff documents for search |
| `compiler-in-the-loop` | Write | Validates code changes compile |
| `import-validator` | Edit, Write | Checks import statements are valid |

### Session Lifecycle Hooks

| Hook | Fires When | What It Does |
|------|------------|--------------|
| `session-register` | SessionStart | Registers session in coordination layer |
| `session-start-continuity` | Resume/Compact | Restores continuity ledger |
| `skill-activation-prompt` | UserPromptSubmit | Suggests relevant skills |
| `subagent-start` | SubagentStart | Registers subagent spawn |
| `subagent-stop-continuity` | SubagentStop | Saves subagent state |
| `ralph-stop-hook` | Stop | Ralph iteration loop, completion detection |
| `session-end-cleanup` | SessionEnd | Cleanup and final state save |

---

## 3. Agent Layer

36 specialized agents, each with a defined role, model preference, and tool access.

### God-Ralph Agents (Primary Execution Engine)

| Agent | Model | Purpose |
|-------|-------|---------|
| **orchestrator** | opus | Persistent coordinator managing parallel Ralph workers. Handles spawning, verification, merging, and recovery. |
| **ralph-worker** | opus | Ephemeral bead executor. Completes ONE bead using TDD workflow in isolated worktree, then exits. |
| **verification-ralph** | sonnet | Runs acceptance criteria in worktree BEFORE merge. Reports pass/fail with severity levels. |
| **ralph-learner** | sonnet | Extracts learnings from completed beads. Stores to memory + updates CLAUDE.md. |

### Bead Management Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **bead-decomposer** | opus | Breaks plans into atomic beads with `ralph_spec`, `impact_paths`, acceptance criteria |
| **bead-validator** | sonnet | Validates beads are self-contained with proper dependencies, fixes issues on the fly |

### Orchestration Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **maestro** | opus | Multi-agent coordination, pattern selection |
| **kraken** | opus | TDD implementation, checkpointing, resumable work (ralph-worker extends this) |

### Planning Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **architect** | opus | Feature design, interface planning, integration design |
| **phoenix** | opus | Refactoring plans, tech debt analysis |
| **plan-agent** | opus | Lightweight planning with research/MCP tools |
| **validate-agent** | sonnet | Validate plans against best practices |

### Exploration Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **scout** | sonnet | Codebase exploration, pattern finding |
| **oracle** | opus | External research (web, docs) |
| **pathfinder** | sonnet | External repository analysis |
| **research-codebase** | sonnet | Document codebase as-is |

### Implementation Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **spark** | sonnet | Quick fixes, small changes (ralph-worker delegates here) |
| **kraken** | opus | Full TDD implementation |

### Debugging Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **sleuth** | opus | Debug investigation, root cause analysis |
| **debug-agent** | opus | Issue investigation via logs/code search |
| **profiler** | opus | Performance analysis, race conditions |

### Validation Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **arbiter** | opus | Unit/integration testing |
| **atlas** | opus | E2E testing |

### Review Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **critic** | sonnet | Code review |
| **judge** | sonnet | Refactor review |
| **surveyor** | sonnet | Migration completeness |
| **liaison** | sonnet | Integration/API quality review |
| **plan-reviewer** | sonnet | Reviews implementation plans |
| **review-agent** | sonnet | General code review |

### Specialized Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **aegis** | opus | Security analysis, vulnerability scanning |
| **herald** | sonnet | Release preparation, changelog |
| **chronicler** | sonnet | Session analysis |
| **memory-extractor** | sonnet | Extract learnings from sessions |

### Agent Output Location

All agents write their output to:
```
.claude/cache/agents/<agent-name>/latest-output.md
```

Ralph-specific state:
```
.claude/state/god-ralph/sessions/<bead-id>.json   # Per-bead session state
.claude/state/god-ralph/completions.jsonl         # Append-only completion log
```

---

## 4. Infrastructure Layer

### TLDR-Code (5-Layer Code Analysis)

Location: `opc/packages/tldr-code/`

A token-efficient code understanding system that provides 85% token savings compared to raw file reads.

| Layer | Extractor | What It Provides |
|-------|-----------|------------------|
| **L1: AST** | `ast_extractor.py` | Functions, classes, imports, structure |
| **L2: Call Graph** | `hybrid_extractor.py`, `cross_file_calls.py` | What calls what, cross-file dependencies |
| **L3: CFG** | `cfg_extractor.py` | Control flow, cyclomatic complexity |
| **L4: DFG** | `dfg_extractor.py` | Variable definitions and uses, data flow |
| **L5: PDG** | `pdg_extractor.py` | Program dependencies, backward/forward slicing |

**Supported Languages:** Python, TypeScript, Go, Rust

**API Entry Point:** `tldr/api.py`
```python
from tldr.api import get_relevant_context, query, get_slice
```

### PostgreSQL + pgvector

Schema in `docker/init-schema.sql`

| Table | Purpose |
|-------|---------|
| `sessions` | Cross-terminal awareness and coordination |
| `file_claims` | Cross-terminal file locking |
| `archival_memory` | Long-term learnings with vector embeddings |
| `handoffs` | Session handoffs with embeddings |

**Features:**
- Semantic search via pgvector embeddings (1024-dim BGE)
- Hybrid RRF search (text + vector combined)
- Cross-session coordination

### Artifact Index (SQLite FTS5)

Schema: `opc/scripts/artifact_schema.sql`
Location: `.claude/cache/context-graph/context.db`

| Table | Indexed Content |
|-------|-----------------|
| `handoffs` | Task summary, what worked/failed, key decisions |
| `plans` | Title, overview, approach, phases |
| `continuity` | Goal, state, learnings |
| `queries` | Q&A pairs for compound learning |

**Features:**
- Full-text search with porter stemming
- BM25 ranking with column weights
- Automatic FTS sync via triggers

### File-Based Persistence

```
thoughts/
  shared/
    handoffs/           # Session handoff documents (YAML)
      <session-name>/
        current.md      # Active handoff
        *.yaml          # Historical handoffs
    plans/              # Implementation plans
    ledgers/            # Continuity snapshots
  experiments/          # A/B tests, comparisons
  skill-builds/         # Skill development iterations

.claude/
  cache/
    agents/             # Agent outputs
      <agent>/latest-output.md
    patterns/           # Multi-agent pattern state
      pipeline-*.json
      jury-*.json
    context-graph/      # SQLite artifact index
  hooks/src/            # Hook implementations
  skills/               # Skill definitions
  agents/               # Agent definitions
```

### Symbol Index

Location: `/tmp/claude-symbol-index/`

| File | Content |
|------|---------|
| `symbols.json` | Function/class definitions with location |
| `callers.json` | Who calls each function |

Built by `build_symbol_index.py` on SessionStart.

---

## 5. Key Python Scripts

### Entry Points (User-Callable)

| Script | Purpose |
|--------|---------|
| `recall_learnings.py` | Semantic search of archival memory |
| `store_learning.py` | Store a new learning |
| `observe_agents.py` | Query running agent state |
| `braintrust_analyze.py` | Analyze session logs |
| `artifact_query.py` | Search artifact index |

### Background Services

| Script | Purpose |
|--------|---------|
| `build_symbol_index.py` | Builds symbol index on session start |
| `index_incremental.py` | Incremental artifact indexing |

### Computation Backends

| Script | Purpose |
|--------|---------|
| `sympy_compute.py` | Symbolic math |
| `z3_solve.py` | Constraint solving |
| `pint_compute.py` | Unit conversions |
| `math_router.py` | Routes math queries to backends |

### Hook Launcher

`hook_launcher.py` - Central dispatcher that compiles and runs TypeScript hooks via the `tsc-cache/` directory.

---

## 6. Data Flow Diagrams

### User Request Flow

```
User: "debug the authentication bug"
         |
         v
+-------------------+
| UserPromptSubmit  |  skill-activation-prompt hook fires
+-------------------+
         |
         v (skill suggested: debug-agent)
+-------------------+
| Task Tool         |  spawns debug-agent
+-------------------+
         |
         v
+-------------------+
| PreToolUse:Task   |  tldr-context-inject adds code context
+-------------------+
         |
         v
+-------------------+
| debug-agent runs  |  uses TLDR-code, searches codebase
+-------------------+
         |
         v
+-------------------+
| PostToolUse:Task  |  pattern-orchestrator checks completion
+-------------------+
         |
         v
+-------------------+
| Agent Output      |  .claude/cache/agents/debug-agent/latest-output.md
+-------------------+
```

### Code Context Injection Flow

```
Claude wants to Read file.py
         |
         v
+-------------------+
| PreToolUse:Read   |  tldr-read-enforcer fires
+-------------------+
         |
         v (blocks read, suggests TLDR)
+-------------------+
| TLDR Analysis     |
| L1: AST extract   |
| L2: Call graph    |
| L3: CFG (if func) |
+-------------------+
         |
         v
+-------------------+
| Context Returned  |  95% fewer tokens than raw file
+-------------------+
```

### Search Routing Flow

```
Claude calls Grep("validateToken")
         |
         v
+-------------------+
| PreToolUse:Grep   |  smart-search-router fires
+-------------------+
         |
         v (detects: structural query about function)
+-------------------+
| Route Decision    |
| - Structural? -> AST-grep
| - Semantic?   -> LEANN/Embeddings
| - Literal?    -> Grep (pass through)
+-------------------+
         |
         v (this is structural)
+-------------------+
| Redirect to       |  uses AST-grep for function references
| AST-grep          |
+-------------------+
```

### God-Ralph Execution Flow (PRIMARY WORKFLOW)

```
User: "build user settings page"
         |
         v
+-------------------+
| /build greenfield |  or /build brownfield
+-------------------+
         |
         v
+-------------------+
| architect agent   |  creates implementation plan
+-------------------+    writes to thoughts/shared/plans/
         |
         v
+-------------------+
| /decompose        |  breaks plan into atomic beads
+-------------------+
         |
         v
+-------------------+
| bead-decomposer   |  creates beads with ralph_spec
+-------------------+
         |
         v
+-------------------+
| bead-validator    |  ensures beads are self-contained
+-------------------+    writes to .claude/state/god-ralph/queue/
         |
         v
+-------------------+
| /ralph start      |  begins parallel execution
+-------------------+
         |
    +----+----+
    |    |    |
    v    v    v
+-------+ +-------+ +-------+
|Ralph-1| |Ralph-2| |Ralph-3|  parallel workers in worktrees
+-------+ +-------+ +-------+  .worktrees/ralph-<bead-id>/
    |         |         |
    v         v         v
+-------+ +-------+ +-------+
|verify | |verify | |verify |  verification-ralph checks each
+-------+ +-------+ +-------+
    |         |         |
    v         v         v
+-------------------+
| merge to main     |  verify-then-merge (no integration branch)
+-------------------+
         |
         v
+-------------------+
| ralph-learner     |  extracts patterns for future sessions
+-------------------+    stores in archival_memory
```

**Bead Structure:**
```yaml
id: "settings-ui-001"
ralph_spec:
  acceptance_criteria:
    - Settings page renders with user preferences
    - Form validation works for all fields
  impact_paths:
    - src/components/Settings/
    - src/hooks/useSettings.ts
  completion_promise: "Settings page functional with validation"
  max_iterations: 3
```

---

## 7. Key Files Reference

### Configuration

| File | Purpose |
|------|---------|
| `.claude/settings.json` | Hook registration, tool configuration |
| `.claude/skills/skill-rules.json` | Skill triggers and keywords |
| `opc/pyproject.toml` | Python dependencies |

### Hook Implementations

| File | Purpose |
|------|---------|
| `.claude/hooks/src/smart-search-router.ts` | Routes searches to best tool |
| `.claude/hooks/src/tldr-context-inject.ts` | Adds TLDR context to agents |
| `.claude/hooks/src/pattern-orchestrator.ts` | Multi-agent pattern management |
| `.claude/hooks/src/session-start-continuity.ts` | Restores session state |
| `.claude/hooks/src/handoff-index.ts` | Indexes handoff documents |

### Agent Definitions

| File | Purpose |
|------|---------|
| `.claude/agents/kraken.md` | TDD implementation agent |
| `.claude/agents/maestro.md` | Multi-agent orchestrator |
| `.claude/agents/architect.md` | Feature planning agent |
| `.claude/agents/scout.md` | Codebase exploration |
| `.claude/agents/orchestrator.md` | God-Ralph job queue manager |
| `.claude/agents/ralph-worker.md` | Parallel bead executor |
| `.claude/agents/verification-ralph.md` | Bead verification agent |
| `.claude/agents/ralph-learner.md` | Pattern extraction from completions |
| `.claude/agents/bead-decomposer.md` | Plan to bead decomposition |
| `.claude/agents/bead-validator.md` | Bead self-containment validation |

### God-Ralph State

| Path | Purpose |
|------|---------|
| `.claude/state/god-ralph/queue/` | Pending beads (JSON files) |
| `.claude/state/god-ralph/sessions/` | Active worker sessions |
| `.claude/state/god-ralph/logs/` | Worker execution logs |
| `.claude/state/god-ralph/orchestrator-state.json` | Queue state and assignments |
| `.claude/state/god-ralph/completions.jsonl` | Completed bead records |
| `.worktrees/ralph-<bead-id>/` | Isolated git worktrees per worker |

### Core Libraries

| File | Purpose |
|------|---------|
| `opc/packages/tldr-code/tldr/api.py` | TLDR-Code public API |
| `opc/scripts/temporal_memory/store_pg.py` | Temporal memory PostgreSQL store |
| `opc/scripts/artifact_index.py` | Artifact index management |

---

## 8. Getting Started

### For Users

**Primary Workflow (God-Ralph):**
1. **Plan** - "create a plan for feature X" → architect creates implementation plan
2. **Decompose** - `/decompose` → breaks plan into atomic beads
3. **Execute** - `/ralph start` → parallel workers complete beads
4. **Monitor** - `/ralph status` → track progress across workers

**Alternative Approaches:**
- **Ask naturally** - "help me understand the auth system" triggers appropriate skills/agents
- **Use handoffs** - "create handoff" when stopping, "resume handoff" when returning
- **Trust the routing** - the system picks the right tool (TLDR vs Grep vs AST-grep)

### For Developers

1. **Add skills** in `.claude/skills/<skill-name>/SKILL.md`
2. **Register triggers** in `.claude/skills/skill-rules.json`
3. **Add hooks** in `.claude/hooks/src/*.ts`, register in `.claude/settings.json`
4. **Add agents** in `.claude/agents/<agent>.md`
5. **Create beads** in `.claude/state/god-ralph/queue/` with proper `ralph_spec`

### Key Invariants

- **Plan before execute** - God-Ralph requires beads with clear acceptance criteria
- **Verify before merge** - each bead verified in worktree before merging to main
- **Agents write to files, not stdout** - all agent output goes to `.claude/cache/agents/`
- **Hooks are fast** - timeouts are 5-60 seconds
- **Memory is semantic** - use embeddings for recall, not exact match
- **TDD is enforced** - implementation agents (including ralph-workers) write tests first
- **Context is precious** - TLDR saves 85% tokens
- **Worktrees isolate** - parallel workers never conflict via git worktree isolation

---

## 9. Glossary

| Term | Meaning |
|------|---------|
| **Bead** | Atomic work unit with acceptance criteria, impact paths, and completion promise |
| **God-Ralph** | Autonomous parallel execution engine for beads |
| **Ralph Worker** | Agent executing a single bead in an isolated worktree |
| **Orchestrator** | Job queue manager assigning beads to workers |
| **Verify-Then-Merge** | Each bead verified in worktree before merging to main |
| **Worktree** | Isolated git working directory for parallel execution |
| **Skill** | A capability triggered by keywords in user input |
| **Hook** | Automatic behavior at lifecycle points (PreToolUse, etc.) |
| **Agent** | Specialized sub-assistant spawned via Task tool |
| **TLDR-Code** | Token-efficient code analysis (5 layers) |
| **Handoff** | Document transferring state between sessions |
| **Continuity Ledger** | Checkpoint within a session |
| **Artifact Index** | Full-text searchable index of past work |
| **Temporal Fact** | Fact that evolves over turns (e.g., "current goal") |
| **Pattern** | Multi-agent coordination (pipeline, jury, debate, gencritic) |
| **Ralph Spec** | YAML specification inside a bead defining acceptance criteria |
| **Completion Promise** | Single-sentence description of what "done" means for a bead |

---

## 10. TLDR 5-Layer Analysis Results

> Generated via `tldr arch`, `tldr calls`, `tldr dead`, `tldr cfg`, `tldr dfg`

### 10.1 Architectural Layer Detection (L2: Call Graph)

TLDR detected 3 architectural layers based on call patterns:

#### Entry Layer (Controllers/Handlers)
Files that are called from outside but rarely call other internal code.

| Directory | Calls Out | Calls In | Functions | Inferred Layer |
|-----------|-----------|----------|-----------|----------------|
| `scripts/` (root) | 21 | 3 | 1,232 | HIGH (entry) |
| `archive/` | 66 | 6 | 590+ | HIGH (entry, dead code) |
| `temporal_memory/` | 13 | 1 | 55 | HIGH (entry) |

#### Service Layer (Business Logic)
Files that mediate between entry and data layers.

| Directory | Calls Out | Calls In | Functions | Inferred Layer |
|-----------|-----------|----------|-----------|----------------|
| `monitors/` | 1 | 0 | 25 | MIDDLE (service) |

#### Data Layer (Utilities)
Files that provide primitive operations, rarely call other code.

| Directory | Calls Out | Calls In | Functions | Inferred Layer |
|-----------|-----------|----------|-----------|----------------|
| `agentica_patterns/` | 4 | 116 | 251 | LOW (utility) |
| `setup/` | 0 | 4 | 67 | LOW (utility) |
| `sacred_tui/` | 0 | 2 | 11 | LOW (utility) |
| `security/` | 0 | 0 | 4 | LOW (utility) |

### 10.2 Cross-File Call Graph (Key Edges)

Selected high-impact call relationships:

```
math_router.py
  → sympy_compute.py:safe_parse
  → numpy_compute.py:cmd_*
  → scipy_compute.py:cmd_*
  → mpmath_compute.py:cmd_*

temporal_memory/store_pg.py
  → postgres_pool.py:get_connection
  → postgres_pool.py:init_pgvector

memory_service_pg.py
  → postgres_pool.py:get_connection (38 callers total)
  → embedding_service.py:embed

braintrust_hooks.py
  → session_start → get_project_id
  → session_start → get_session_value
  → log → ensure_dirs
```

#### Most Called Functions (Impact Analysis)

| Function | File | Caller Count | Description |
|----------|------|--------------|-------------|
| `get_connection` | `postgres_pool.py` | 38 | Central DB connection pool |
| `math_command` | `math_base.py` | 50+ | Math computation wrapper |
| `parse_array` | `math_base.py` | 30+ | Array parsing for numpy |
| `parse_matrix` | `math_base.py` | 20+ | Matrix parsing for scipy |

### 10.3 Complexity Hot Spots (L3: CFG)

Functions with elevated cyclomatic complexity:

| Function | File | Complexity | Blocks | Reason |
|----------|------|------------|--------|--------|
| `session_start` | `braintrust_hooks.py` | 5 | 13 | Multiple early returns |
| `search_hybrid` | `memory_service_pg.py` | 3 | 6 | Date filter branches |
| `infer_pattern` | `pattern_inference.py` | 12+ | - | Pattern matching logic |
| `main` | `compiler-in-the-loop.ts` | 8+ | - | Lean4 + Loogle integration |
| `main` | `skill-activation-prompt.ts` | 10+ | - | Large skill matching switch |

#### Refactoring Candidates

1. **`skill-activation-prompt.ts:main`** - Extract skill matchers to separate functions
2. **`pattern_inference.py:infer_pattern`** - Use strategy pattern
3. **`braintrust_hooks.py`** - Split session vs span logic

### 10.4 Data Flow Analysis (L4: DFG)

#### Key Data Paths

**PostgreSQL Connection Flow (38 callers):**
```
postgres_pool.py:get_connection()
    ├── memory_service_pg.py (all methods)
    ├── temporal_memory/store_pg.py
    ├── coordination_pg.py
    ├── message_memory.py
    └── populate_temporal_sessions.py
```

**Embedding Pipeline:**
```
Input text
    → embedding_service.py:embed()
        → OpenAI/Local API
            → memory_service_pg.py:store()
                → PostgreSQL (pgvector column)
```

**search_hybrid Data Flow:**
```
Parameters:
    text_query: str
    query_embedding: list[float] (1536 dims)
    limit: int = 10
    text_weight: float = 0.5
    vector_weight: float = 0.5
    start_date, end_date: Optional[datetime]
        │
        ▼
    _pad_embedding() → padded_query
        │
        ▼
    Build SQL conditions (date filters)
        │
        ▼
    Execute hybrid query:
        SELECT ...
        ts_rank(...) * text_weight +
        (1 - embedding <=> query) * vector_weight
        │
        ▼
Output: list[MemoryRecord]
```

### 10.5 Dead Code Analysis

#### Cleanup Completed (2026-01-07)

**Files archived:**
| File | Reason |
|------|--------|
| `offline_search.py` → `archive/` | Duplicate of wizard functionality, only test imports |
| `service_checks.py` → `archive/` | Duplicate of wizard functionality, only test imports |
| `test_mcp_offline.py` → `tests/archive/` | Tests for archived files |

**Functions removed:**
| File | Function | Reason |
|------|----------|--------|
| `braintrust_analyze.py` | `format_duration` | Never called, no tests |
| `secrets_filter.py` | `mask_secret` | Never called, not exported |

**Functions kept (have tests, cross-platform support):**
| File | Function | Reason |
|------|----------|--------|
| `hook_launcher.py` | `expand_path` | Cross-platform path handling, tested |

#### Archive Directory (490+ functions)

The `archive/` directory contains deprecated subsystems:

| File | Status | Note |
|------|--------|------|
| `offline_search.py` | Archived | Duplicate of wizard SQLite fallback |
| `service_checks.py` | Archived | Duplicate of wizard service checks |
| `user_preferences.py` | Dead | Old preference system |
| `websocket_multiplex.py` | Dead | Replaced by coordination_pg |
| `skill_validation.py` | Dead | Moved to hooks |
| `ledger_workflow.py` | Dead | Superseded by continuity hooks |
| `post_tool_use_flywheel.py` | Dead | Never integrated |
| `db_connection.py` | Dead | Replaced by postgres_pool |

### 10.6 Circular Dependencies

**Resolved:** The `claude_scope ↔ unified_scope` circular dependency was eliminated by archiving both modules (2026-01-07). These were Agentica infrastructure modules that were never integrated into production hooks or skills.

No circular dependencies remain in active code.

### 10.7 TLDR-Code Package Structure

Location: `opc/packages/tldr-code/tldr/`

| Module | Layer | Functions | Classes | Purpose |
|--------|-------|-----------|---------|---------|
| `api.py` | API | 20 | 3 | Unified interface |
| `ast_extractor.py` | L1 | 2 | 6 | Python AST extraction |
| `hybrid_extractor.py` | L1 | 1 | 1 | Multi-language AST |
| `cross_file_calls.py` | L2 | 53 | 2 | Call graph building |
| `cfg_extractor.py` | L3 | 7 | 5 | Control flow graphs |
| `dfg_extractor.py` | L4 | 7 | 7 | Data flow analysis |
| `pdg_extractor.py` | L5 | 6 | 4 | Program dependencies |
| `analysis.py` | Util | 9 | 1 | Impact/dead code |
| `cli.py` | CLI | 1 | 0 | Command-line entry |

### 10.8 Hook System Structure

Location: `.claude/hooks/src/`

| Category | Hooks | Purpose |
|----------|-------|---------|
| Session | 4 | Start/end lifecycle |
| Tool Interception | 8 | Enhance tool behavior |
| Subagent | 4 | Agent coordination |
| Patterns | 2 | Multi-agent orchestration |
| Validation | 3 | Code quality gates |

**Key Hook Functions:**

| Hook | Key Functions |
|------|---------------|
| `skill-activation-prompt.ts` | `runPatternInference`, `generateAgenticaOutput` |
| `tldr-context-inject.ts` | `detectIntent`, `getTldrContext`, `extractEntryPoints` |
| `subagent-stop-continuity.ts` | `parseStructuredHandoff`, `createYamlHandoff` |
| `compiler-in-the-loop.ts` | `runLeanCompiler`, `getGoedelSuggestions`, `queryLoogle` |
| `pattern-orchestrator.ts` | `handlePipeline`, `handleJury`, `handleDebate`, `handleGenCritic` |

---

## 11. Summary Statistics

| Metric | Count | Notes |
|--------|-------|-------|
| Python functions | 2,328 | Across all `opc/scripts/` |
| TypeScript hooks | 34 | Active in `.claude/hooks/src/` |
| Skills | 123 | In `.claude/skills/` |
| Agents | 41 | Defined in system prompt |
| Tests | 265+ | TLDR-code alone |
| Entry layer functions | 1,057 | Called from outside |
| Leaf functions | 729 | Utility/helper code |
| Dead functions | 4 active, 43 archived | Most dead code now in archive/ |
| Circular dependencies | 0 | Resolved by archiving scope modules |
| get_connection callers | 38 | Most called internal function |

---

*This architecture document is generated by TLDR 5-layer analysis. Token cost: ~5,000 (vs ~50,000 raw files = 90% savings).*
