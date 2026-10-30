---
name: spec
description: Turn an idea or a human-written spec into SPEC.md, a precise spec the dev-loop agents can build from without asking questions. Interviews Ed when there is no written spec yet. Use when asked to write, convert or tighten a spec for the build loop.
argument-hint: "[path to an existing spec, or a one-line description]"
---
# Spec

Input from Ed (may be empty): $ARGUMENTS

If Ed gave a written spec (a file path or pasted text), convert it. If not, interview him using the Interview Guide below: one question at a time, with a suggested answer where you have one. When the spec is drafted, write it to `SPEC.md` at the repository root (or update the existing one), show Ed the outline and the open points, and iterate. The spec is approved when Ed says so. Approving it is also his go-ahead for everything after it: go straight on to the `plan-tasks` skill and then the `build-loop` skill, without asking him again, unless he said otherwise (Ed, Oct 29: "Build the spec and build the product rather than having to check in and approve multiple times").

When Ed approves, put `Status: approved (Ed, <date>)` as the first line under the title of SPEC.md and commit it; the `dev-loop` entry skill reads that line to know the spec is approved.

**Ask once, early.** Before Ed approves, find every step the run will need his say-so for at the end: changes to his settings or live setup (hooks, login services, shell profiles), installs outside the repo, anything that touches a real account or server. Name them in one short list in the approval turn, so his approval covers them, and write them in SPEC.md under "Approved up front" (each with what it changes). The build prepares them and runs them at the end without asking again (Oct 29: the Stream Deck run finished, then stopped to ask about setup, one more round trip from the car). Things only Ed can physically do (a sign-in, a device in his hand) go in that section too, marked as his to do. Secrets are never among them: Ed enters those himself.

**Keep the first version small.** If the spec would need more than about 25 tasks, suggest a first version that runs end to end and put the rest under "Later" in SPEC.md.

**"Send it."** When Ed says "send it" (or "just build it", "you decide the rest") at any point, stop asking. Settle every open point yourself with the answer you would have suggested, list those choices briefly under "Decided without Ed" in SPEC.md so he can change them later, approve the spec on his behalf, and carry on through `plan-tasks` and `build-loop` to a working version. Only something that truly cannot be guessed (a credential, an account only he has) still stops for him.

Ed often answers from his phone, or by voice in the car (Oct 29: "that was WAY too much text, and the questions were too much to handle at once via voice"). So, in every turn to Ed:

- Keep it short: a few sentences, no tables, nothing he would have to scroll.
- Ask one question at a time, two at most when they belong together. Keep the rest of the open points for later turns rather than listing them all.
- Number the choices 1, 2, 3, never letters (Ed, Oct 29), and say which one you suggest.
- Show the spec outline only when he asks for it or approves the draft; point to SPEC.md for the details.

Done when SPEC.md has the approved line, an "Approved up front" section (or "none"), and you have called the `plan-tasks` skill.

The rest of this skill is the conversion guide.

---

Convert this human-readable spec into an AI-optimized format for automated dev agents. Output as a single markdown document saved as SPEC.md.

This spec will be consumed by an automated development system where an architect (the coordinating session) plans task execution, Developer agents implement code (with full codebase access), and QA agents validate against acceptance criteria. Write the spec so these agents can work autonomously without asking clarifying questions.

## Formatting Rules

1. Structure: Use clear hierarchical sections — Overview, Tech Stack, Requirements, Technical Constraints, Data Models, API Contracts, Degraded Mode / Fallback Behavior, Error Handling, Out of Scope, Approved up front (steps Ed approves now that run at the end), Later (what is left for after the first version)
2. Requirements: Make each atomic, testable, and numbered for reference (e.g., REQ-001). The Architect agent uses these to plan tasks and the QA agent uses them to validate.
3. Precision: Replace vague terms with specifics ("fast" → "< 200ms", "secure" → "bcrypt with 12 rounds")
4. Edge cases: Explicitly list boundary conditions and error states
5. Data schemas: Define input/output shapes, field types, validation rules
6. Out of scope: State what NOT to build — prevents AI scope creep
7. Acceptance criteria: How do we know each feature is complete? These must be programmatically testable. Start each with how it is checked: `[test]` automated test, `[run]` a real run of the built thing on test data, `[look]` a screenshot or output someone opens, `[manual]` only Ed can do it. Include at least one `[run]` criterion for the whole product, and say how it runs against test data, never Ed's real data or settings.
8. Format: Bullet points over prose, no narrative fluff, use markdown headers and lists
9. Side effects & consequences: For each requirement, explicitly list ALL outputs and side effects as separate numbered items — not just the primary action. If "completing task X" should also "write to table Y" and "invalidate cache Z," those are three separate requirements (or three sub-items under one requirement), not one sentence joined by "and." Dev agents reliably implement the headline action but skip secondary effects buried in the same paragraph.
10. Degraded mode: For features that depend on background processes, caches, or other eventually-consistent data, explicitly state what happens when the dependency isn't available yet. Example: "If no session summaries exist (cron hasn't run), fall back to loading raw messages from the previous session." These fallback behaviors must be their own requirements, not implied.
11. Database performance: For any new table that will be queried at scale (especially with vector similarity, full-text search, or frequent WHERE clauses), explicitly specify required indexes in the Data Models section. Include index type (B-tree, GIN, HNSW, etc.) and any version/dimension constraints. Don't assume the dev agent will add indexes — they won't unless told.
12. Error handling as discrete requirements: Retry limits, failure tracking, circuit breakers, and graceful degradation must each be their own numbered requirement with concrete thresholds — not a sentence in a paragraph about the happy path. Example: "After 3 consecutive failures for the same session, skip permanently and log" is REQ-065, not a bullet point buried inside REQ-060.
13. Requirement coverage check: After writing all requirements, do a self-audit. List every behavioral change the spec demands and confirm each one has a REQ number. If a feature needs retry logic, channel forwarding, failure notifications, and cleanup — that's 4 requirements, not 1. Count them. A spec with 5 features and 5 REQs is almost certainly under-specified.
14. Current vs. Required framing: For every requirement that touches existing code, use the pattern: "Current behavior: [what happens now]. Required behavior: [what must happen instead]." This eliminates ambiguity about whether the requirement is already satisfied. Dev agents skip requirements when they can't tell if the code already handles them.

## Section Guidance

### Degraded Mode / Fallback Behavior

This section is commonly missed and causes real bugs. For each feature, ask:
- What happens if a background job hasn't run yet?
- What happens if a cache is cold or missing?
- What happens if an external dependency is temporarily unavailable?
- What is the user experience during the gap between "data created" and "background process catches up"?

Each answer should be a numbered requirement with testable behavior.

### Error Handling

Go beyond "log and retry." For each failure mode, specify:
- How many retries before giving up
- How failures are tracked (table, counter, flag)
- What happens after max retries (skip permanently? alert? degrade gracefully?)
- Whether the failure tracking mechanism itself is persistent (survives restarts)

### Requirements — Multi-Step Actions

When a single user action or system event triggers multiple effects, structure the requirement as a parent with explicit sub-items:

**Good:**
> REQ-060: Session summarization
> - REQ-060a: Call LLM with transcript, receive JSON containing `summary` and `new_facts` array
> - REQ-060b: Store summary in memories table via `MemoryService::writeMemory()`
> - REQ-060c: For each item in `new_facts`, store via `MemoryService::storeFact()` with individual error handling
> - REQ-060d: If fact storage fails, log warning but do not block summary creation

**Bad:**
> REQ-060: Summarize sessions and extract any new facts, storing results appropriately.

## For Existing Codebases

If this project already has code, the spec should account for it:

- Note which parts of the system already exist and should be extended vs. built fresh
- Reference existing models, services, or patterns the new work should follow
- Call out any existing conventions (naming, architecture, testing patterns) the agents should adhere to
- If the project uses a specific framework or stack, state it explicitly with version numbers so agents use the correct APIs

## Interview Guide

Use this section when helping a user develop their spec through conversation rather than converting an existing document.

### Phase 1: Initial Scoping

Start by understanding the big picture before drilling into details:

- **What are you building?** Get a one-sentence summary of the project/feature.
- **Why does this need to exist?** Understand the motivation — this shapes priority decisions later.
- **What's the tech stack?** Framework, language, database, hosting. Pin down versions.
- **Greenfield or existing codebase?** If existing, ask for repo access or a description of current architecture.
- **What are the hard constraints?** Deadlines, budget limits, must-use technologies, compliance requirements.
- **Who are the users?** Internal team, public users, API consumers, other services.

### Phase 2: Feature Discovery

Walk through each feature the user mentions. For each one:

- **What's the happy path?** Step through the normal user flow from trigger to completion.
- **What are the inputs and outputs?** Data shapes, validation rules, response formats.
- **What are the edge cases?** Empty states, concurrent access, rate limits, large data sets.
- **What happens on failure?** Error messages, retry behavior, fallback modes.
- **What are the side effects?** Notifications, audit logs, cache invalidation, webhook calls.
- **What's explicitly out of scope?** Prevent scope creep by naming what you're NOT building.

Ask follow-up questions when answers are vague. "It should be fast" → "What's the target response time?" "Standard error handling" → "What does the user see when X fails?"

### Phase 3: Coverage Checklist

Before drafting, verify you have enough detail on:

- [ ] Data models and relationships
- [ ] API contracts (endpoints, methods, request/response shapes)
- [ ] Authentication and authorization rules
- [ ] Error handling strategy (retries, circuit breakers, user-facing messages)
- [ ] Fallback behavior for external dependencies
- [ ] What's explicitly out of scope

Don't force answers for sections that don't apply — skip what's irrelevant.

### When to Wrap Up

You have enough information to draft the spec when:

- Every feature has a defined happy path and at least one failure mode
- Data models are clear enough to write migrations
- You haven't heard "I'm not sure, whatever you think" more than twice in a row (sign of decision fatigue — draft what you have and iterate)

Draft the spec, share it, and iterate. A good spec often takes 2-3 rounds of feedback. Don't aim for perfection on the first pass.

### Existing Code Sections — Preventing "Already Done" Misinterpretation

When a spec references existing code, dev agents frequently conclude "this is already implemented" and skip the actual work. This is the single most common failure mode for specs that build on existing codebases. To prevent it:

1. **Label existing code as "Starting Point," not "Existing Code."** The heading matters. "Existing Code — What Already Exists" reads as "this is done." Use "Starting Point — What Exists Today" or "Current State" instead.

2. **Pair every existing-code reference with an explicit "What Must Change" block.** For each file listed as existing, state what's missing or needs modification. Don't leave it to the dev agent to diff the spec requirements against the code — they won't.

   **Good:**
   > **Starting Point:** `app/Jobs/AgentRun.php` — has `agentTaskId` param and basic task status tracking.
   > **What Must Change:** Add `$tries = 3` and `$backoff` properties (REQ-008). Wrap `writeMemory()` in try/catch (REQ-013). Broadcast failure to user on exception (REQ-001). Extract JSON output from response (REQ-002).

   **Bad:**
   > **Existing Code:** `app/Jobs/AgentRun.php` — Has `agentTaskId` param, task status tracking, memory write on completion, error handling.

3. **Tag requirements as NEW vs. VERIFY.** If a requirement is fully implemented and just needs confirmation, mark it `[VERIFY]`. If it requires new code, mark it `[IMPLEMENT]`. Dev agents need this disambiguation — without it, they default to verification when existing code is nearby.

4. **Put "No Changes Required" items in a separate section at the bottom.** Don't interleave "already done" items with "needs work" items. When dev agents see a mix, they pattern-match the "no changes" framing onto adjacent items that actually need implementation.

5. **In the Requirements section, every REQ must explicitly state whether it's already implemented.** Don't rely on a separate "existing code" table to convey this. At the requirement level: "Current behavior: X. Required behavior: Y." makes the gap unmistakable.

