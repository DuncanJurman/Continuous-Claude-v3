---
description: Interactive wizard to create comprehensive feature specifications. Gathers context, explores codebase, and outputs detailed design documents for bead-farmer to decompose.
---

# /god-ralph plan <initial context>

Interactive wizard that creates comprehensive feature specifications with enough detail for bead-farmer to decompose into atomic beads.

## Usage

```bash
# Simple idea
/god-ralph plan I want to add user authentication with JWT

# Detailed context
/god-ralph plan Add a dark mode toggle to settings. Should persist to localStorage and apply a .dark class to body

# Multi-line context
/god-ralph plan Build a notification system that:
- Sends email and push notifications
- Has user preferences for each type
- Queues notifications for batch sending
```

## Required: Initial Context

**The user MUST provide initial context.** If they run `/god-ralph plan` without any description, prompt them:

```
Please provide the initial context for your plan. Describe what you want to build:

/god-ralph plan <describe your feature or task here>

Examples:
- /god-ralph plan Add user authentication with JWT and password reset
- /god-ralph plan Fix the checkout bug where totals don't update
- /god-ralph plan Refactor the API to use async/await instead of callbacks
```

**Do NOT proceed with generic questions.** Wait for the user to provide their idea.

## Philosophy

**You are the Architect.** Your job is to produce a **comprehensive feature specification** - NOT to decide bead granularity, titles, or dependencies. That's bead-farmer's job.

**What comprehensive means:**
- Exhaustive detail organized by concern
- Every relevant file, pattern, convention discovered
- All edge cases and constraints documented
- Clear acceptance criteria at the feature level
- NOT vague "high-level" descriptions

**What you DON'T decide:**
- How many beads to create
- Bead titles or descriptions
- Dependency chains between beads
- Ralph specs or iteration limits
- What subset of context each bead gets

## Visual References (Screenshots, Mockups)

When the user provides images (mockups, screenshots, designs):

1. **Claude cannot save pasted images** - ask user to save it:
   ```
   Please save that image to: reference-images/<descriptive-name>.png
   ```

2. **Verify and view it:**
   ```bash
   mkdir -p reference-images
   Read("reference-images/homepage-mockup.png")
   ```

3. **Include in specification** with path + text summary:
   ```markdown
   ## Visual References
   - `reference-images/homepage-mockup.png` - Hero with gradient, 3 feature cards, dark footer
   ```

Ralph workers can use the Read tool to view images, so they'll have full visual context.

## Wizard Phases

### Phase 1: Clarify

**Starting from user's initial context:**

1. Parse and acknowledge what was understood
2. Use `AskUserQuestion` to fill in gaps only
3. Ask targeted follow-ups based on what's missing
4. Continue iterating until nothing is uncertain/unclear

**Core questions to answer (skip if already provided in initial context):**
- What is the goal? *(usually provided)*
- What are the constraints?
- What existing code is involved?
- What are the success criteria?
- Are there dependencies on other work?
- What tests need to pass?

**Smart follow-up strategy:**
- Group related questions (don't ask 10 one at a time)
- Use multiple choice when options are clear
- Let user provide freeform for open questions
- Stop asking when implementation is clear enough
- **Never re-ask what the user already specified**

### Phase 2: Explore

**Auto-explore the codebase** to gather context, then confirm with user:

```bash
# Find relevant files
Glob("src/**/*auth*")
Glob("src/**/*user*")

# Search for patterns
Grep("login", type="ts")
Grep("JWT", type="ts")

# Read key files
Read("src/api/routes.ts")
Read("src/middleware/auth.ts")
```

**Present findings to user:**
```
I found these relevant files:
- src/api/auth.ts (existing auth routes)
- src/middleware/jwt.ts (JWT validation)
- src/models/User.ts (user model)
- tests/auth.test.ts (test patterns)

Is this correct? Any files I missed?
```

### Phase 3: Design

**Write the comprehensive feature specification.** This is your primary output.

Do NOT output structured beads. Output a **design document** with all the detail bead-farmer needs to make decomposition decisions.

### Phase 4: Delegate to Bead-Farmer

After the specification is complete, invoke bead-farmer to decompose it:

```
Task(
  subagent_type="bead-farmer",
  description="Decompose feature specification into beads",
  prompt="Decompose this comprehensive feature specification into atomic beads:

<insert full specification document here>

You decide:
- How many beads and what granularity
- Bead titles and descriptions
- Dependency order
- Epic structure if needed
- Ralph spec for each bead
- Which subset of context each bead needs

Check for existing beads that overlap.
Ensure each bead has enough context to execute independently."
)
```

## Feature Specification Format

Output your specification in this format:

```markdown
## Feature: <feature name>

### Business Context
<Why we're building this, user needs, what it unblocks, business requirements>

### Technical Approach
<Architectural decisions with rationale - JWT vs sessions, bcrypt vs argon2, etc.>
<Technology choices that are fixed vs flexible>

### Codebase Findings

**Existing Patterns:**
- <file:lines> - <what pattern to follow>
- <relevant code snippets showing how similar things are done>

**Key Files to Modify/Create:**
- <file> - <what changes needed>
- <file> (new) - <what this file will do>

**Database/Infrastructure:**
- <any schema changes, migrations, external services>

### Constraints
<Must-haves, patterns to follow, team preferences, library requirements>

### Edge Cases
<What happens when X? How to handle Y? Error scenarios>

### Acceptance Criteria (Feature-Level)
<Comprehensive success criteria - all of these must pass for feature to be complete>
- User can do X
- Tests pass: <specific test commands>
- No lint errors
- Build succeeds
- Integration with Y works

### User Requirements
<Everything gathered from wizard conversation - preferences, decisions made>

### Notes
<Anything else relevant - known risks, future considerations, open questions>
```

## Example: Complete Specification

```markdown
## Feature: User Authentication System

### Business Context
Users need to create accounts and securely log in. This is blocking
the checkout feature which requires authenticated users. Users have
requested "remember me" functionality for convenience.

### Technical Approach
- JWT tokens stored in httpOnly cookies (not localStorage - security)
- bcrypt for password hashing (already used in src/utils/crypto.ts)
- Refresh token rotation for long sessions
- Rate limiting on login attempts (use existing rateLimiter middleware)

Rationale: Cookies > localStorage for security, bcrypt is already
in the codebase so we maintain consistency.

### Codebase Findings

**Existing Patterns:**
- POST endpoints: `src/api/users.ts:45-78` (follow this exact pattern)
  ```typescript
  router.post('/users', validateBody(userSchema), async (req, res) => {
    const user = await UserService.create(req.body);
    res.status(201).json(user);
  });
  ```
- Validation: `src/middleware/validate.ts` with Zod schemas
- Error handling: `src/utils/errors.ts` ApiError class
- Tests: Jest + supertest, see `tests/api/users.test.ts` for pattern

**Key Files to Modify/Create:**
- `src/api/auth.ts` (new) - Auth routes
- `src/middleware/requireAuth.ts` (new) - JWT validation middleware
- `src/models/User.ts` (modify) - Add password_hash field
- `src/types/express.d.ts` (modify) - Add req.user type
- `src/schemas/auth.ts` (new) - Zod schemas for login/register

**Database:**
- Users table exists, needs: password_hash, refresh_token columns
- Migration pattern: see `src/migrations/001_create_users.ts`
- Use existing db utility in `src/utils/db.ts`

### Constraints
- Must use existing Zod validation pattern (no Joi, no manual)
- Must use existing error handling (ApiError, not custom)
- Email must be case-insensitive (lowercase before storing)
- Password minimum 8 chars, must include number
- All endpoints must have rate limiting
- Follow existing commit convention (feat/fix/test prefixes)

### Edge Cases
- Email already exists → 409 Conflict with message "Email already registered"
- Password too weak → 400 with specific message about requirements
- Login fails → Generic "Invalid credentials" (no email enumeration)
- Refresh token expired → 401, client must re-login
- Rate limiting: 5 attempts per 15 minutes per IP → 429 with retry-after
- Malformed JWT → 401 Unauthorized
- User deleted but has valid JWT → 401 (check user exists)

### Acceptance Criteria (Feature-Level)
- User can register with email/password
- User can login and receives JWT in httpOnly cookie
- Protected routes reject unauthenticated requests with 401
- Protected routes work with valid JWT
- Refresh token rotation works (new refresh token on use)
- Rate limiting prevents brute force (returns 429)
- Password reset flow works (sends email, token valid 1hr)
- All existing tests still pass (npm test)
- New tests cover auth flows: register, login, protected routes, refresh
- No lint errors (npm run lint)
- Build succeeds (npm run build)

### User Requirements
- Password reset: YES (via email, using existing email service)
- Email verification: NO (not needed for MVP)
- OAuth: NO (future consideration)
- Remember me: YES (longer refresh token - 30 days vs 1 day)

### Notes
- Email service already exists at src/services/email.ts
- Consider adding login attempt logging for security audit later
- Rate limiter is per-IP; consider per-user rate limiting for password reset
```

## What NOT to Include

**Do NOT output any of these (bead-farmer decides):**

```markdown
# WRONG - Don't structure as beads
**Bead 1: Add JWT middleware**
- Files: src/middleware/auth.ts
- Acceptance criteria: ...

**Bead 2: Implement registration**
- Depends on: Bead 1
- ...
```

```markdown
# WRONG - Don't pre-determine granularity
"This should be split into 4 beads..."
"First bead should be..."
```

```markdown
# WRONG - Don't add ralph specs
ralph_spec:
  completion_promise: BEAD COMPLETE
  max_iterations: 50
```

Your job is specification. Bead-farmer's job is decomposition.

## Missing Context (Prompt User)

```
User: /god-ralph plan

Wizard: Please provide the initial context for your plan. Describe what you want to build:

/god-ralph plan <describe your feature or task here>

Examples:
- /god-ralph plan Add user authentication with JWT and password reset
- /god-ralph plan Fix the checkout bug where totals don't update
- /god-ralph plan Refactor the API to use async/await instead of callbacks
```

## Guidelines

### What to Include in Specification

**Do include:**
- Specific file paths discovered
- 1-2 code snippets showing patterns to follow
- All constraints from user and codebase
- Every edge case you can think of
- Comprehensive acceptance criteria
- Technical decisions with rationale

**Don't include:**
- Bead structure or titles
- Dependency chains
- Granularity decisions
- Step-by-step implementation
- Ralph specs

### Good Specification Depth

The specification should be detailed enough that bead-farmer could:
- Understand the full scope without asking questions
- Make informed granularity decisions
- Know which files relate to which concerns
- Understand all constraints and edge cases

## Notes

- The wizard outputs a specification, not beads
- Bead-farmer receives the specification and decomposes it
- Use `/god-ralph start` to begin execution after beads are created
- Specifications can be saved for reference if complex
