Review of Plan: Bead Decomposer + Bead Validator Agents

After reviewing the Continuous-Claude-v3 documentation on skills, hooks, memory, subagents, and configuration, we've identified several improvements to align the plan with best practices. Below, each proposed change is explained with rationale and a corresponding diff showing how the original plan markdown would be modified.

Change 1: Add a dedicated slash command for orchestration (/decompose)

Rationale: Currently, the plan suggests an optional slash command to run the decomposition and validation sequence. Making this a first-class feature improves usability by allowing users to trigger the entire bead creation pipeline with one command. This aligns with Claude Code’s design where repetitive or standardized user-initiated workflows should be encapsulated in slash commands. By implementing /decompose, we ensure consistency and reduce manual steps (the main agent can still auto-delegate, but a slash provides an easy explicit trigger). The slash command file will reside in .claude/commands/, and the system will load it as a custom command.

In practice, using a slash command here fits the recommended decision framework: the action doesn’t need to run on its own (no hook needed), the task (decomposition) requires specialized multi-step work so we use subagents, and it’s a user-initiated workflow – perfect for a slash command. The diff below updates the plan to treat /decompose as a recommended addition and adds it to the files list:

 ## Integration: Agent Orchestration
 
-### Skill: /decompose (optional)
-
-Could create a skill that orchestrates both agents:
+### Skill: /decompose (Recommended for orchestration)
+
+Implement a slash command that orchestrates both agents in sequence:
 
 ```bash
 # User runs after plan approval
@@
 | `.claude/agents/bead-decomposer.md` | UPDATE | Replace current draft with full agent spec |
 | `.claude/agents/bead-validator.md` | CREATE | New agent for bead validation/refinement |
 
+| `.claude/commands/decompose.md` | CREATE | New slash command to orchestrate decomposer & validator |
 ---

Change 2: Use plan-specific output files to avoid overwriting

Rationale: The plan currently specifies using latest-output.md in each agent’s cache directory to store results. While following the standard pattern, this means each new run would overwrite the previous output. Instead, we should include the plan identifier (feature prefix or slug) in the output filename to preserve outputs per plan. This way, multiple decompositions won’t conflict and we maintain an audit trail of each plan’s results. We will still update latest-output.md as a convenient symlink or pointer to the most recent run, but the unique file ensures no loss of data. This change improves reliability when running the agents repeatedly or in parallel on different plans.

The diff below updates the Design Decisions table and each agent’s Output Contract to use PLAN-<name>-output.md (with <name> being the plan’s slug or identifier):

 | Context Passing | Plan path + decomposer output file | Standard agent pattern, avoids large prompts |
-| Output Location | `.claude/cache/agents/<name>/latest-output.md` | Standard agent pattern |
+| Output Location | `.claude/cache/agents/<name>/<plan-slug>-output.md` (per plan, updates latest-output.md) | Standard agent pattern |
@@
 ### Output Contract
-Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/latest-output.md`
+Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-decomposer/PLAN-<name>-output.md` (also updates latest-output.md)
@@
 ### Output Contract
-Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-validator/latest-output.md`
+Writes to: `$CLAUDE_PROJECT_DIR/.claude/cache/agents/bead-validator/PLAN-<name>-output.md` (also updates latest-output.md)


With this change, each plan’s bead decomposition report and validation report are saved to a file named after the plan, preventing confusion between runs.

Change 3: Ensure all dependencies are correctly represented

Rationale: It’s critical that the epic bead depends on all task beads, including those that themselves depend on others. In the original plan, the example dependency graph and table omitted the epic’s dependency on one task (auth-003). We should explicitly include every child task in the epic’s dependency list so the epic only closes when all tasks (even indirect ones) are done. This matches the intended dependency direction: epic is blocked by all children.

Additionally, the ASCII dependency graph should list all tasks under the epic (with notes about blocking) for clarity. We’ve adjusted the graph to show each task as a direct child of the epic, and indicated blocking relationships in parentheses.

Finally, in the Step 8 instructions and Implementation Notes, clarify that the epic must depend on each child bead. We add guidance to repeat the bd dep add <epic-id> <child-id> command for every task created. This prevents scenarios where a task not directly linked could allow the epic to close early. The updated plan also highlights this as “depends on all children” to avoid ambiguity.

Changes in the diff below:

 ## Dependency Graph


-[feature-prefix]-epic

├── [feature-prefix]-001 (READY - highest PageRank)

│ └── [feature-prefix]-003 (blocked)

└── [feature-prefix]-002 (READY)
+[feature-prefix]-epic

├── [feature-prefix]-001 (READY - highest PageRank)

├── [feature-prefix]-002 (READY)

└── [feature-prefix]-003 (BLOCKED by [feature-prefix]-001)

@@
| ID | Title | Type | Priority | Depends On | PageRank |
-| auth-epic | Auth System | epic | P1 | auth-001, auth-002 | - |
+| auth-epic | Auth System | epic | P1 | auth-001, auth-002, auth-003 | - |
@@
**CRITICAL: Epic depends on children** - Never reverse this
```bash
-# CORRECT: Epic depends on children
-bd dep add <epic-id> <child-id>
+# CORRECT: Epic depends on children
+bd dep add <epic-id> <child-id>    # (repeat for each child bead)
@@
```bash
-# CORRECT: Epic depends on children (children are READY to work)
-bd dep add <epic-id> <child-id>
+# CORRECT: Epic depends on all children (children are READY to work)
+bd dep add <epic-id> <child-id>    # (repeat for each child bead)


Now the epic’s Depends On field lists every task (including auth-003 in the example), and both the step-by-step guide and implementation notes emphasize adding a dependency entry for each child. This guarantees the epic remains blocked until all tasks — even those that were sequentially dependent — are completed. Correct dependency modeling is crucial for the workflow (preventing blocked tasks from being left untracked and ensuring proper task ordering).

Change 4: Strengthen duplicate detection logic

Rationale: The duplicate-checking step can be made more robust. We want the decomposer to catch if the plan is already addressed by an existing epic or tasks, which prevents redundant work. In the original plan, the guidance was very brief. We’ve expanded it to differentiate between exact duplicates, partial overlaps, and related (but distinct) work:

If the exact feature already exists (e.g. an epic or open beads with the same purpose), the agent should report that and skip creating duplicate beads.

If the plan overlaps with existing work but introduces new aspects, proceed with new beads but add notes referencing the existing context (so future readers know they’re related).

If the plan is a follow-up or prerequisite to existing beads, create the new beads and explicitly link them via dependencies to the existing ones (using bd dep add) to reflect the relationship.

This aligns with best practices of not duplicating work and respecting project context. It also saves time by avoiding redoing tasks or at least flagging potential conflicts for the user. To support this, the agent should search not only open/in-progress tasks but also epics for similar keywords (e.g., using bd list --type=epic if available). The updated text in Step 2 reflects these distinctions:

 If duplicates found:
-- If truly duplicate → Report, don't create
-- If similar but different → Create with note
-- If related but distinct → Create with dependency
+- If exact same feature or beads exist (duplicate) → Report it and skip creating new beads
+- If overlapping scope but differences (similar) → Create new beads with a note linking to existing work
+- If related prerequisite or subsequent work (distinct but related) → Create new beads and add dependency to existing beads


With this change, the bead-decomposer will be smarter about not generating redundant tasks. For example, if an “Auth System” epic already exists, the agent might warn that this plan is duplicative rather than blindly creating a second set of auth beads. This makes the system more reliable and avoids confusion.

Change 5: Handle extremely large plans with multiple epics

Rationale: The plan hints at “possibly nested epics” for very large features, but doesn’t specify how to handle them. To improve the architecture’s scalability, we explicitly advise splitting very large projects into multiple epics. If a plan covers disparate components or sub-features, creating one giant epic with too many tasks could become unwieldy. Instead, the agent should consider making several epics (each grouping a logical subset of tasks) and optionally a top-level epic if needed to tie them together. This approach mirrors how one might break down a big project into sub-projects for clarity and parallel execution.

We added a note in the granularity section to guide this decision. It instructs the decomposer to use multiple epics when appropriate, each focused on a sub-domain of the feature, rather than one epic with 15+ tasks. This division improves manageability and helps context isolation (each sub-epic’s tasks remain tightly related). It also aligns with context management best practices: subagents can handle complex tasks in isolated contexts, and multiple subagents (epics) can run in parallel if independent.

The inserted note in Step 4 is shown in the diff:

 - Could be combined with related work
+**Note:** For extremely large features, consider decomposing into multiple epics. If the plan covers distinct subprojects or modules, create separate epic beads for each major sub-feature (with a top-level epic to group them if necessary). This keeps each epic focused and manageable, improving clarity and parallel execution.


This change doesn’t mandate nested epics for every case, but provides a clear guideline when a plan is too big for a single epic. It makes the resulting bead set more robust and easier for worker agents to tackle in parallel chunks.

Change 6: Improve error handling during agent execution

Rationale: To make the system more reliable, the agents should handle errors gracefully. If a bd create or bd dep add command fails (for example, due to a duplicate title, missing permissions, or CLI error), the current plan doesn’t specify what to do. We introduce a new rule for the bead-decomposer: don’t proceed blindly on errors. Instead, the agent should either adjust its actions or halt and flag the issue for human intervention.

For instance, if creating an epic fails because an epic with that name exists, the decomposer might choose to reuse the existing epic or log a warning and not create a duplicate. Similarly, if adding a dependency fails (perhaps the link exists or IDs are wrong), the agent should catch that and not assume everything is fine. This defensive approach aligns with production readiness and error tolerance built into Claude Code’s philosophy (the framework includes robust error handling and retries). By explicitly instructing the agent to handle command failures, we prevent inconsistent states.

The following diff adds a rule to the Agent 1 rules list:

 7. **Add ralph_spec to every bead** - Worker agents need this
 8. **Write output report** - Validator reads this to know which beads to review
+9. **Handle errors gracefully** - If any `bd` command fails (e.g., creation or dependency addition error), adjust the approach or flag the issue for human review instead of continuing blindly.


With this addition, if something unexpected occurs (like the bd CLI returns an error message), the bead-decomposer will know to stop or adapt rather than continue with potentially incomplete data. This makes the workflow more robust. (In practice, the agent can catch the Bash tool’s output/status and decide to retry with a modified input or annotate the plan for manual follow-up.)

Beyond these changes, it’s worth noting that the overall design already follows many best practices from Continuous-Claude-v3:

Use of Subagents: The plan correctly uses subagents (bead-decomposer and bead-validator) for specialized, complex tasks with isolated context, which is encouraged. In fact, delegating feature planning to a dedicated subagent (like a “Planner”) is explicitly recommended in the docs.

Tool Permissions: The agents’ tool set is limited to what’s needed (Bash, Read, Grep, Glob). Notably, they do not include the task tool, preventing them from spawning further subagents recursively, which is a safeguard mentioned in the Claude architecture (subagents have certain tools removed to avoid recursion).

Context Management: The plan passes the plan file path and uses file reading tools to supply context on demand, rather than injecting the full plan into the prompt. This aligns with context-preservation strategies in Claude Code – heavy content is handled via tools and subagents to keep the main conversation light.

Slash vs Hook: We opted for a slash command to initiate the process, rather than an automatic hook, because plan approval is a user-driven milestone. This means the user can control when to run decomposition (maybe after some review), which matches the recommended use of slash commands for user-initiated workflows. Hooks are more suited for truly automatic, always-run scenarios (not the case here).

By implementing the changes above, the Bead Decomposer + Bead Validator system will be more maintainable, reliable, and aligned with the continuous Claude framework. These revisions enhance the architecture (through better orchestration and error handling), add useful features (like preserving outputs per plan), and ensure the outcome is robust and easy for human operators to use. Each diff snippet provided shows the precise adjustments to the plan document, which can guide updating the actual .claude/agents and .claude/commands files accordingly.