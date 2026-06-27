---
description: Configure this repo's Linear watcher (project ID, lane, trigger phrase)
---

You are setting up the **linear-watcher** plugin for the current repository.

Goal: write a per-repo config so the SessionStart hook knows which Linear
project to watch. The plugin is otherwise inert in this repo.

Steps:

1. Ask the user for their **Linear project ID** (a UUID). They can find it in
   the Linear app via the project's "Copy model UUID", or from the project URL.
   If they don't know it and have the Linear MCP tools available, offer to look
   it up by project name.

2. Ask (with sensible defaults — only if they care):
   - **State/lane type** to watch — default `unstarted` (Linear's "Todo" lane).
   - **Trigger phrase** the user will say to work the items — default `to-dos`.
   - **Poll interval** in seconds for the optional in-session background watcher
     — default `120`.

3. Write the values into the repo's `.claude/settings.json` under an `"env"`
   block (create the file/merge if it already exists). Example:

   ```json
   {
     "env": {
       "LINEAR_PROJECT_ID": "<uuid>",
       "LINEAR_STATE_TYPE": "unstarted",
       "LINEAR_TRIGGER_PHRASE": "to-dos",
       "LINEAR_POLL_SECONDS": "120"
     }
   }
   ```

4. Confirm the API key is available globally (env `LINEAR_API_KEY` or the file
   `~/.config/linear-watcher/key`). If neither exists, tell the user to create
   the key file:

   ```bash
   mkdir -p ~/.config/linear-watcher
   printf '%s' 'lin_api_xxxxxxxx' > ~/.config/linear-watcher/key
   ```

5. Tell the user the watcher will report the Todo lane on the next session
   start, and that they can verify now by running the check directly:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh"` (exit 0 = items exist).
