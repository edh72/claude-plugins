---
description: Configure this repo's Linear watcher — scan the board's columns and pick which to watch / move feedback into
---

You are setting up the **linear-watcher** plugin for the current repository. Goal:
write a per-repo config so the watcher knows which Linear project to watch, which
column new work is picked up from, and which column needs-review work moves into.
The plugin is otherwise inert in this repo.

Steps:

1. **Get the Linear project.** Ask the user which Linear project this repo maps to.
   Resolve it to a project **ID** (UUID) — use the Linear MCP tools (e.g.
   `list_projects` / `get_project`) to look it up by name if they don't have the ID
   handy. Capture the project's **team** too (you'll need it next).

2. **Scan the board's columns.** Call the Linear MCP `list_issue_statuses` for that
   team and show the user the actual status/column names (with their type, e.g.
   Backlog / Todo / In Progress / Needs Feedback / Done). Don't assume names — use
   what the board actually has.

3. **Ask the two configurable choices** (everything else is inferred):
   - **Which column should new tasks be picked up from?** (the one the watcher
     polls — usually the "Todo"/unstarted column). Record its exact name as
     `LINEAR_TODO_STATUS`.
   - **Which column should items needing the user's review/feedback move into?**
     (e.g. "Needs Feedback" / "In Review"). Record its exact name as
     `LINEAR_FEEDBACK_STATUS`.
   Also offer (with defaults, only if they care): **trigger phrase**
   (`LINEAR_TRIGGER_PHRASE`, default `to-dos`) and **poll interval seconds**
   (`LINEAR_POLL_SECONDS`, default `120`).

4. **Write the config** into the repo's `.claude/settings.json` under an `"env"`
   block (create/merge if it exists). Use the exact column names from the board:

   ```json
   {
     "env": {
       "LINEAR_PROJECT_ID": "<uuid>",
       "LINEAR_TODO_STATUS": "Todo",
       "LINEAR_FEEDBACK_STATUS": "Needs Feedback",
       "LINEAR_TRIGGER_PHRASE": "to-dos",
       "LINEAR_POLL_SECONDS": "120"
     }
   }
   ```

   (Done / Backlog / In Progress are inferred and don't need configuring. If you
   omit `LINEAR_TODO_STATUS`, the watcher falls back to the board's `unstarted`
   column via `LINEAR_STATE_TYPE`.)

5. **Confirm the API key** is available globally (env `LINEAR_API_KEY` or the file
   `~/.config/linear-watcher/key`). If neither exists, tell the user to create it:

   ```bash
   mkdir -p ~/.config/linear-watcher
   printf '%s' 'lin_api_xxxxxxxx' > ~/.config/linear-watcher/key
   ```

6. Tell the user it'll report the watched column on the next session start, and
   they can verify now with: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh"`
   (exit 0 = items exist).
