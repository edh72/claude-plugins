---
name: plan-tasks
description: Turn an approved SPEC.md into the dev-loop task list (.dev-loop/tasks.json), each task with its files, acceptance criteria and dependencies, in the order the build loop will run them. Use after the spec is approved and before build-loop.
argument-hint: "[path to the spec, default SPEC.md]"
---
# Plan tasks

Spec to plan from: $ARGUMENTS (default `SPEC.md` at the repository root).

Write the task list to `.dev-loop/tasks.json` (create the folder if needed) and validate it with `jq . .dev-loop/tasks.json`. Then tell Ed in one or two sentences how many tasks there are and what the first few are, and go straight on to the `build-loop` skill: his approval of the spec (or "send it") was the go-ahead (Ed, Oct 29). Wait for him only if he asked to see the tasks first.

The build loop runs the tasks strictly in the order they appear in the file, skipping none, so the order is the plan. A task only starts once every task in its `dependencies` is approved.

Two additions to the format below:
- An optional top-level `"test_command"` (for example `"node --test"`), which the build loop runs once at the end. Include it whenever the project has one obvious command.
- If the repository already has a `.dev-loop/state.json` (a run has started), do not renumber or reorder existing tasks; append new ones with new IDs.

The rest of this skill is the task-generation guide.

---

## Instructions

Generate a task list from the specification using the exact JSON format shown at the end of this guide, written to `.dev-loop/tasks.json` as valid JSON only. Each task needs a unique ID (TASK-001, TASK-002, etc.), a title, description, files to create/modify, acceptance criteria as an array, and dependencies listing any task IDs that must complete first. Order tasks so dependencies come before the tasks that need them.

---

## How Tasks Are Executed

Tasks are executed by an automated 3-agent system (the build-loop skill), not a human developer. Understanding this changes how you write tasks:

- **Architect** (the coordinating session) runs the tasks in order and makes decisions about rework and approval. It does NOT write code and does not rewrite tasks, so each task must stand on its own.
- **Developer agent** implements the task with full codebase access — it can read/write files, run commands, execute tests, and use git. It produces a handoff document summarizing what it built.
- **QA agent** validates the implementation against the task's acceptance criteria. It can read code, run tests, and inspect output. It produces a pass/fail report.

This means:
- Acceptance criteria must be **machine-verifiable** (testable via code, not subjective judgment)
- Task descriptions should be **self-contained enough** that the Developer agent can work without asking questions
- File paths should be **concrete and accurate** — the agents will look for these exact paths

---

## Task Decomposition Principles

1. **Group by feature, not by layer.** Organize as vertical slices (e.g., "Listing feature: migration + model + controller + tests") rather than horizontal layers ("all migrations, then all models, then all controllers"). Ship working features, not disconnected pieces.

2. **Don't over-split framework-native work.** Database migrations, model definitions, and similar scaffolding that naturally belongs together should stay as single tasks. If the framework expects you to run `migrate:fresh` and test everything together, don't break it into separate tasks that can't be validated independently.

3. **Right-size for AI context.** A capable AI agent can handle 10 related migrations or 5 related models in one task. The goal is logical coherence, not arbitrary smallness. Ask: "Can this be tested as a unit?" and "Does splitting this create artificial dependencies?"

4. **Call out integration points explicitly.** Tasks touching external services (Stripe, S3, AWS, email providers, etc.) should be flagged clearly so the implementer knows to set up mocks/fakes. Don't bury these in the middle of acceptance criteria. **Also flag internal integration points** — if completing an action in Service A should trigger a write in Service B, that's a discrete acceptance criterion, not an implied consequence. Example: "AgentRun task completion writes summary to memories table via MemoryService::writeMemory()" is its own AC, separate from "AgentRun updates task status to completed."

5. **Include a "skip if obvious" clause.** If the framework has a standard way to do something, just do it that way — don't wait for explicit instructions. This applies to things like Form Requests, Eloquent relationships, middleware registration, etc.

6. **Keep each task completable in one session.** If a task would require the agent to stop, wait for external setup (like real API keys), then resume — split it. Tasks should be executable start-to-finish with mocks/fakes.

7. **Include a spec-verification task as the final task.** The last task in the list should be: "Verify all spec requirements are implemented." Its acceptance criteria should reference every REQ- item from the spec, and its job is to read the codebase and confirm each one is present — not just that tests pass, but that the specified behavior exists in the code. This catches the "tests pass but feature is incomplete" failure mode that occurs when dev agents write tests for what they built rather than what the spec required.

---

## Working With Existing Codebases

If the project already has code:

1. **Check what exists before creating tasks.** Don't create a "Set up User model" task if User.php already exists. Use the `modify` array for existing files.

2. **Reference real file paths.** The Developer agent has codebase access and will look for these files. Guessed paths that don't exist cause wasted time.

3. **Follow existing patterns.** If the codebase uses repository pattern, service classes, or specific testing conventions, tasks should follow suit. Note the convention in the task description.

---

## Acceptance Criteria Principles

1. **Don't restate framework built-ins.** Skip obvious validation like "title must be 10-200 chars" or "price must be >= 0" — that's just Form Request boilerplate the framework handles. Focus on actual business logic.

2. **Acceptance criteria should be verifiable and non-obvious.** Good: "Cannot offer on own listing", "Thread depth limited to 10 counter-offers", "Price changes trigger watcher notifications". Bad: "Validates required fields", "Returns 422 on invalid input", "Uses proper HTTP status codes".

3. **Provide concrete examples for ambiguous requirements.** Instead of "handle edge cases appropriately", say "if offer thread depth >= 10, return 422 with error code `max_thread_depth`". AI generates better code when it knows the exact expected output.

4. **Mark optional enhancements separately.** If something is nice-to-have, mark it clearly with "(Optional)" prefix. Prevents the agent from blocking on non-essential features or gold-plating.

5. **Write for automated QA.** The QA agent validates by reading code and running tests. Criteria like "feels intuitive" or "looks clean" can't be verified. Instead: "endpoint returns 403 when user lacks permission" is testable.

6. **One assertion per criterion.** Each acceptance criterion should test exactly one behavior. "Summarizes sessions and extracts new facts" is two criteria: "LLM prompt requests JSON with summary and new_facts fields" and "Each returned fact is stored via MemoryService::storeFact()." Dev agents implement up to the first conjunction and move on. If you find yourself writing "and" or "also" in a criterion, split it.

7. **Error handling and defensive behavior are discrete criteria, not afterthoughts.** If the spec mentions retry limits, failure tracking, circuit breakers, or graceful degradation, each one is its own acceptance criterion with a concrete threshold. "After 3 consecutive failures for the same session, skip permanently" is testable and must be a standalone AC — not buried in a description paragraph or tacked onto a happy-path criterion.

8. **Side effects are discrete criteria.** If an action should trigger a secondary write, emit an event, invalidate a cache, or update a related model, each side effect is its own criterion. "Task completion updates status to completed" and "Task completion writes summary to memories table" are two separate criteria, even though they happen in the same method. Dev agents implement the primary action and skip side effects that aren't explicitly called out.

---

## Testing & Definition of Done

**General Testing Requirement:** Every task must include appropriate test coverage. Unit tests for business logic, feature tests for API endpoints, and mocked external services where needed. This is assumed for all tasks — only note testing details when something unusual is required.

**Definition of done by task type:**
- **Migration/model tasks:** Migrations run cleanly, factories create valid instances, relationships return expected results
- **Endpoint tasks:** Feature tests cover happy path and key error cases
- **Service tasks:** Unit tests cover business logic and edge cases

Only call out unusual testing needs per-task (like "requires mocked S3" or "needs seeded data from TASK-003").

---

## Optimizations for AI Code Generation

1. **Include file paths in each task.** Be explicit about what files get created or modified. AI agents work better with concrete targets than abstract descriptions.

2. **Reference spec sections, don't duplicate them.** Instead of restating business rules in the task, point to the source: "Implement trust tier calculation per SPEC section 'Trust Tiers'". The agent can read the spec itself — duplicating creates drift and bloat.

3. **Specify error response formats once in the spec.** Don't repeat "return 422 with proper error format" everywhere. Define the standard error envelope in the spec and reference it. The agent will apply it consistently.

4. **Flag tasks that need predecessor data.** If a task requires seeded data or specific database state to test, say so explicitly in the "requires" array. Saves the agent from discovering this mid-task.

---

## JSON Schema

```json
{
  "tasks": [
    {
      "id": "TASK-001",
      "title": "Short descriptive title",
      "description": "1-2 sentence description of what this task delivers",
      "files": {
        "create": ["path/to/new/file.php", "path/to/another.php"],
        "modify": ["path/to/existing.php"]
      },
      "acceptance_criteria": [
        "Verifiable, non-obvious criterion",
        "Business logic requirement with concrete example",
        "(Optional) Nice-to-have enhancement"
      ],
      "requires": ["Seeded data from TASK-001", "Mocked external service: Stripe"],
      "dependencies": []
    }
  ]
}
```

---

## Example Output

```json
{
  "tasks": [
    {
      "id": "TASK-001",
      "title": "Core database schema and models",
      "description": "Create migrations and Eloquent models for users, listings, and offers with proper relationships and factories.",
      "files": {
        "create": [
          "database/migrations/create_users_table.php",
          "database/migrations/create_listings_table.php",
          "database/migrations/create_offers_table.php",
          "app/Models/User.php",
          "app/Models/Listing.php",
          "app/Models/Offer.php"
        ],
        "modify": []
      },
      "acceptance_criteria": [
        "User hasMany Listings and hasMany Offers (as buyer)",
        "Listing belongsTo User and hasMany Offers",
        "Offer belongsTo Listing, belongsTo User (buyer), belongsTo Offer (parent, nullable)",
        "All factories generate valid instances that pass validation"
      ],
      "requires": [],
      "dependencies": []
    },
    {
      "id": "TASK-002",
      "title": "Offer creation and negotiation threading",
      "description": "Implement POST /listings/{id}/offers endpoint for creating offers with 48hr expiration, and POST /offers/{id}/counter for counter-offers with parent threading.",
      "files": {
        "create": [
          "app/Http/Controllers/OfferController.php",
          "app/Http/Requests/CreateOfferRequest.php",
          "tests/Feature/OfferTest.php"
        ],
        "modify": ["routes/api.php"]
      },
      "acceptance_criteria": [
        "Cannot offer on own listing (buyer_id != listing.user_id)",
        "Counter-offer creates new offer with parent_offer_id linking to original",
        "Thread depth >= 10 returns 422 with error code max_thread_depth",
        "Offer expires_at set to 48 hours from creation",
        "Original offer status changes to countered after counter-offer created"
      ],
      "requires": ["Seeded data: at least one verified user and one active listing"],
      "dependencies": ["TASK-001"]
    }
  ]
}
```
