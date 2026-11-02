# edh-claude-plugins

Ed Holloway's personal [Claude Code](https://code.claude.com) plugin marketplace.

## Use it

```
/plugin marketplace add  https://github.com/edh72/claude-plugins
/plugin install <plugin>@edh-claude-plugins
```

Refresh later with `/plugin marketplace update`.

## Plugins

| Plugin | What it does |
|---|---|
| [`dev-loop`](plugins/dev-loop/) | Spec, task list and a build loop: developer and QA subagents per task, verdicts with capped rework, resumable state in the repo. Never pushes or deploys. |

`linear-watcher` was retired on 2 November 2026, when Ed left Linear. WhenBox picks up filed tasks by itself now.

## Layout

```
.claude-plugin/marketplace.json   ← the marketplace catalog
plugins/
  dev-loop/                       ← one plugin
    .claude-plugin/plugin.json
    agents/  skills/  hooks/  scripts/  README.md
```

Add a new plugin by dropping a folder under `plugins/` and adding an entry to
`.claude-plugin/marketplace.json`.
