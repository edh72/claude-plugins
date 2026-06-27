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
| [`linear-watcher`](plugins/linear-watcher/) | Auto-pulls Linear "Todo" items into Claude Code at session start. Zero-token curl check; per-repo project ID. Install once, inert until a repo opts in. |

## Layout

```
.claude-plugin/marketplace.json   ← the marketplace catalog
plugins/
  linear-watcher/                 ← one plugin
    .claude-plugin/plugin.json
    hooks/  scripts/  commands/  README.md
```

Add a new plugin by dropping a folder under `plugins/` and adding an entry to
`.claude-plugin/marketplace.json`.
