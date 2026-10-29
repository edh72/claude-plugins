# SPEC: dev-loop deploy

Researched and drafted Oct 29, 2026 (Ed: "We're also going to want a build script or a build agent to help us deploy this… a Laravel Forge deployed web app as the common case (although we want to stay flexible for other app types; they just don't auto deploy yet)"). Not yet approved by Ed. The open decisions are under "Decisions for Ed" at the end; everything else is settled enough to build.

## Overview

- **What:** a `deploy` skill in the dev-loop plugin, backed by a script (`scripts/deploy.sh`) that does every Forge and GitHub call. It takes a project that dev-loop built (a working version on a `dev-loop/<date>` branch) and puts it online: first-time setup of a new Laravel app on Ed's Forge server, a preview of a branch, a production deploy, a health check after each deploy, and a rollback when the check fails.
- **Why:** dev-loop stops at "a working version for review" and never pushes or deploys. Today every new app is set up by hand in Forge's dashboard. This closes the gap, with Ed approving each live step on his phone through WhenBox.
- **Shape (recommended):** a script with a skill wrapper, inside dev-loop. Reasons:
  - The parts that must never depend on the model (which commit is live, whether the health check passed, when to roll back, refusing without an approval) belong in a script, the same way `loop.sh` owns the build loop's state.
  - dev-loop already has the push/deploy guard (`scripts/guard.sh`). The approval gate for deploys is the same kind of hook and must sit next to it, so a separate plugin would duplicate it and could disagree with it.
  - The skill stays small: it chooses the step, writes the plain-language description Ed sees on the card, and reports back.
  - A separate plugin was considered and rejected for v1. If non-dev-loop repos later need it, the script and its adapters move out unchanged.
- **Common case:** a Laravel 13 app on PHP 8.5 with Postgres, on Ed's existing Forge server. Other app types (static, Node, Mac/iPhone) are recognised and reported as "not auto-deployed yet", through the same adapter interface they will later plug into.

## Tech Stack

- Bash 3.2+ (macOS default), `curl`, `jq`, `gh` (GitHub CLI, logged in as `edh72`), `ssh` (the Mac's key, already accepted as `forge@146.190.70.213`), `security` (macOS Keychain). Same tools as `loop.sh` and `guard.sh`; nothing to install.
- **Laravel Forge API (new API, "v2")**: base `https://forge.laravel.com/api`, `Authorization: Bearer <token>`, `Accept: application/json`, JSON:API responses (`data.id`, `data.attributes`). Every resource is under `/orgs/{organization}/…`; Ed's organization slug is `ed-holloway`. Rate limit 60 requests a minute per user (`X-RateLimit-Remaining` header). Docs: https://forge.laravel.com/docs/api-reference/introduction, OpenAPI: https://forge.laravel.com/api/docs.openapi (fetched Oct 29, 2026). The docs call the API "Early Access, subject to change".
- Do not use the Forge CLI (`forge`, v2.0.0 in Herd's bin): it has no commands to create sites, databases or workers, and it keeps its own login in `~/.config/forge/token`.
- Do not use a third-party Forge MCP server (`isapp/laravel-forge-mcp`, `@ranium/forge-mcp`, `@vitrion/laravel-forge-mcp`; none is from Laravel). They would hand an agent the whole API with no approval gate.

## What exists today (verified Oct 29, 2026, read-only)

- **Server** `EDH-APPS`, Forge server ID `1209288`, `146.190.70.213`, PHP 8.5, Postgres 18, 1 vCPU / 2 GB, shared by seven sites (WhenBox, mcp-personal, wristy, agent-chat, distinctive, news-personal, duo-checker). Ed will not resize it (memory: server-capacity-watch).
- **Ed's site pattern** (every recent site): created with a free `<name>-<random>.on-forge.com` address, zero-downtime deployments on, push to deploy on `main`, deployment retention 4, shared path `storage`, a custom domain added later as an alias (for example `whenbox.edholloway.com`). Queue workers are server background processes running `php8.5 /home/forge/<site>/current/artisan queue:work database …`.
- **Ed's deploy script** (WhenBox, same shape on wristy): `$CREATE_RELEASE()`, `cd $FORGE_RELEASE_DIRECTORY`, `$FORGE_COMPOSER install --no-dev --no-interaction --prefer-dist --optimize-autoloader`, `npm ci || npm install`, `npm run build`, `$FORGE_PHP artisan optimize`, `$FORGE_PHP artisan storage:link`, `$FORGE_PHP artisan migrate --force`, `$ACTIVATE_RELEASE()`, `$RESTART_QUEUES()`.
- **Releases on the server:** `/home/forge/<site>/releases/<deployment id>/`, `current` is a symlink owned by `forge`, `.env` and `storage` live beside them. So the previous release can be re-activated over SSH as `forge` without sudo.
- **No Forge health check is set** on WhenBox (`healthcheck_endpoint: null`).
- **GitHub:** Forge's GitHub connection clones over HTTPS with its OAuth token for zero-downtime sites (no deploy key needed) and adds its own push webhook to the repo. Ed's account is on GitHub Free: branch protection on a private repo returns 403 "Upgrade to GitHub Pro or make this repository public".
- **DNS** for `edholloway.com` is at GoDaddy (`ns75/ns76.domaincontrol.com`).
- **Lessons that bind this spec:**
  - Every push to `main` deploys on a small shared server; about 20 deploys in a day slowed every site (Oct 27). Deploys must be batched and one at a time.
  - Forge's Reverb panel rewrote server-wide nginx limits and took every site down (Oct 28). This tool never touches server-level settings, nginx or Reverb.
  - A Forge site API response includes the site's deploy-hook URL with its token (`deployment_url`), and the repo's webhook URL contains a token. Neither may reach a log, a card or agent text.

## Starting Point — what exists in dev-loop today

- `scripts/guard.sh` (PreToolUse on Bash): refuses `git push` and deploy commands while `.dev-loop/state.json` says `running`.
  **What must change:** nothing in its rule. The deploy skill must refuse to start while a build run is in progress (REQ-004), so the two never meet.
- `hooks/hooks.json`: one PreToolUse hook (guard).
  **What must change:** add the deploy gate hook (REQ-030) after the guard.
- `skills/build-loop/SKILL.md` "Finishing": writes `.dev-loop/summary.md`.
  **What must change:** the summary ends with one line saying how to put the work online (`/dev-loop:deploy`), only when the repo has a `deploy.json` or is a Laravel app (REQ-090).
- `README.md`: says the plugin never pushes or deploys.
  **What must change:** add a "Deploy" section and change the guardrail wording to "the build loop never pushes or deploys; the deploy skill does, only with Ed's approval" (REQ-091).
- `.claude-plugin/marketplace.json` (repo root): dev-loop description says "Never pushes or deploys." **What must change:** same correction, and bump dev-loop to 0.2.0 (REQ-091).

## Requirements

Every REQ below is `[IMPLEMENT]` (new code) unless marked `[VERIFY]`.

### Files and configuration

- **REQ-001 `[IMPLEMENT]` Per-repo app description `deploy.json`** at the repository root, committed, never containing secrets. Written by the deploy skill on first setup (from what it detects) and editable by Ed. Shape in "Data Models".
- **REQ-002 `[IMPLEMENT]` Per-Mac site registry** at `~/.config/dev-loop/sites.json` (mode 600), keyed by GitHub `owner/repo`. Holds the Forge IDs and addresses created for that repo (server, site, preview site, database, workers). Not in the repo, because IDs are per Forge account and agents in the repo must not be able to point a deploy at another site by editing a committed file.
- **REQ-003 `[IMPLEMENT]` Repo level.** The script reads the repo's level (Experiment, Personal, Client) from `~/.config/dev-loop/levels.json` (keyed by `owner/repo`, mode 600). Missing entry = Experiment, as the car plan says for new repos. When WhenBox Host exposes repo levels (car plan, step 3), the script asks it first and uses the file only when Host is not running. The script never writes this file.
- **REQ-004 `[IMPLEMENT]` No overlap with a build run.** Every `deploy.sh` command except `status` exits 2 with "A build run is in progress; deploy after it finishes" when `.dev-loop/state.json` has status `running`.

### Commands (`scripts/deploy.sh <command>`)

All commands print one JSON line on stdout as their last output (`{"ok":true|false,"step":…,"message":…,…}`), plain progress lines on stderr, and append one line per Forge or GitHub call to `.dev-loop/deploy-log.jsonl` (method, path with IDs, status code, duration; never bodies).

- **REQ-010 `detect`**: reads the repo and prints the app type and what it needs, without calling any service.
  - REQ-010a: Laravel when `artisan` and `composer.json` with `laravel/framework` exist. Records `php` from `composer.json` `require.php` (default `8.5`), `node_build: true` when `package.json` has a `build` script, `queue: true` when the code dispatches jobs or `QUEUE_CONNECTION` in `.env.example` is not `sync`, `scheduler: true` when `routes/console.php` uses `Schedule::`, `database: pgsql` unless `.env.example` says otherwise.
  - REQ-010b: `static` when there is an `index.html` at the root or in `public/` and no server code; `node` when `package.json` has a `start` script and no `artisan`; `apple` when there is a `project.yml` with an iOS or macOS target or an `*.xcodeproj`; otherwise `other`.
  - REQ-010c: lists `required_env`: every key in `.env.example` whose value is empty and which REQ-022 cannot fill (for example `ANTHROPIC_API_KEY`). Names only.
  - REQ-010d: writes nothing when `--write` is absent; with `--write`, creates or updates `deploy.json`.
- **REQ-011 `check`**: preflight for the other commands. Fails with a numbered list of what is missing, each with its fix:
  - REQ-011a: the Forge token is readable (REQ-060) and `GET /orgs/ed-holloway` returns 200.
  - REQ-011b: `gh auth status` succeeds.
  - REQ-011c: for Laravel, `ssh -o BatchMode=yes forge@<server ip> true` succeeds (needed for rollback and backups).
  - REQ-011d: the target server is `EDH-APPS` (or the server named in Decision 2) and `GET /orgs/ed-holloway/servers/{id}` shows it is ready.
  - REQ-011e: the working tree is clean and the branch to deploy exists on `origin`.
- **REQ-012 `setup`**: first-time setup of a new Laravel app (detail in REQ-020 to REQ-029). Refuses when `sites.json` already has a site for this repo.
- **REQ-013 `preview <branch>`**: deploys a branch to the app's preview site (REQ-040 to REQ-044).
- **REQ-014 `production <commit sha>`**: deploys `main` at exactly that commit (REQ-045 to REQ-049).
- **REQ-015 `rollback`**: re-activates the previous release of production (REQ-050 to REQ-054).
- **REQ-016 `status`**: read-only; prints for production and preview: address, deployed commit, last deployment status and time, health check result, pending migrations between the deployed commit and `main`.
- **REQ-017 `domain <name>`**: adds a custom domain to production and prints the DNS records Ed must add (REQ-029).
- **REQ-018 Adapters.** `deploy.sh` routes `setup`, `preview`, `production`, `rollback` and `status` to `scripts/deploy/adapters/<type>.sh` with the same arguments. v1 ships `laravel-forge.sh`. `static.sh`, `node.sh`, `apple.sh` and `other.sh` exist and exit 3 with `{"ok":false,"step":"unsupported","message":"<type> apps are not auto-deployed yet","manual":[…]}`, where `manual` is `deploy.json`'s `manual_steps` (for Apple apps, for example `apple/scripts/testflight.sh` and `apple/scripts/release.sh`). `check` and `detect` work for every type.

### First-time setup of a Laravel app on Forge (`setup`)

Runs in this order. Each step records what it created in `sites.json` as soon as it succeeds, so a failed setup can be resumed by running `setup` again (it skips what exists and continues).

- **REQ-020 GitHub repository.**
  - REQ-020a: if there is no `origin` remote, `gh repo create edh72/<repo dir name> --private --source . --remote origin`. Always private; never public.
  - REQ-020b: push `main` (the first push only; later changes reach `main` through REQ-045). If the repo is on a `dev-loop/…` branch with an approved working version, that branch is pushed and merged through REQ-045's merge step instead.
  - REQ-020c: if the repo already exists on GitHub, use it unchanged.
- **REQ-021 Database.** `POST /orgs/ed-holloway/servers/{server}/database/schemas` with `name` = repo name in snake case (≤ 63 chars, `[a-z0-9_]`), `user` = same name, `password` = 32 random characters from `openssl rand`. The password goes straight into the `.env` (REQ-022) and is never printed or logged. If a database of that name exists, stop and ask (never reuse another app's database).
- **REQ-022 Site.** `POST /orgs/ed-holloway/servers/{server}/sites` with:
  - `type: "laravel"`, `domain_mode: "on-forge"`, `name: <repo name>` (Forge adds a random suffix, as with Ed's existing sites), `php_version` from `deploy.json`, `zero_downtime_deployments: true`, `shared_paths: ["storage"]`, `source_control_provider: "github"`, `repository: "edh72/<repo>"`, `branch: "main"`, `database_id` and `database_user_id` from REQ-021, `install_composer_dependencies: true`, `push_to_deploy: false` (turned on in REQ-027, after the first deploy succeeds).
  - REQ-022a: the call is asynchronous. Poll `GET …/sites/{site}` every 5 seconds until `status` is `installed`, at most 5 minutes.
  - REQ-022b: if the site disappears or fails (Forge removes a site whose first clone fails), stop with "Forge could not clone edh72/<repo>. Check that Forge's GitHub connection can see this repository" and remove the site's entry from `sites.json`.
- **REQ-023 Environment file.** Build the production `.env` from `.env.example` and `PUT …/sites/{site}/environment` with `{environment, cache: true, queues: true}`:
  - `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://<site address>`, `APP_KEY=base64:<32 random bytes, base64>`.
  - `DB_CONNECTION=pgsql`, `DB_HOST=127.0.0.1`, `DB_PORT=5432`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` from REQ-021.
  - `QUEUE_CONNECTION=database` when `queue: true`, else `sync`; `CACHE_STORE=database`; `SESSION_DRIVER=database`; `LOG_CHANNEL=daily`; `MAIL_MAILER=log` unless `deploy.json` names a mailer.
  - Keys in `required_env` are written empty and reported as "needs Ed" (REQ-061). The build is not blocked by them; the health check decides whether the app works without them.
  - The content is built in a file under a `mktemp -d` directory (mode 700) and deleted after the call.
- **REQ-024 Deploy script.** `PUT …/sites/{site}/deployments/script` with Ed's script (see "What exists today"), dropping `npm ci || npm install` and `npm run build` when `node_build` is false. Never adds `reverb:restart` or anything that touches server services.
- **REQ-025 Workers and scheduler.**
  - REQ-025a: when `queue: true`, `POST …/servers/{server}/background-processes` with `name: "<repo> queue"`, `site_id`, `command: "php8.5 /home/forge/<site name>/current/artisan queue:work database --sleep=3 --tries=3 --timeout=120 --queue=default"`, `user: "forge"`, `processes: 1`.
  - REQ-025b: when `scheduler: true`, `POST …/sites/{site}/integrations/laravel-scheduler`.
  - REQ-025c: never creates Horizon, Octane, Reverb or Pulse integrations (out of scope).
- **REQ-026 Health check address.** `PUT …/sites/{site}/healthcheck` with `healthcheck_endpoint: "https://<site address><health_path>"` (default `/up`, which Laravel 11+ apps answer), so Forge's own post-deploy check and failure email also run.
- **REQ-027 First deploy.** Run REQ-046 to REQ-048 for the current `main` commit. On success, `POST …/sites/{site}/deployments/push-to-deploy` so later merges to `main` deploy by themselves (Decision 5). On failure, leave push to deploy off and report.
- **REQ-028 Record and report.** Write `deploy.json` (if absent) and the `sites.json` entry; commit `deploy.json` on the current branch as `Deploy: describe the app for dev-loop deploy`; report the address, what needs Ed (REQ-061) and the approval it ran under.
- **REQ-029 Custom domain (`domain <name>`, optional).**
  - REQ-029a: `POST …/sites/{site}/domains` with `name`, then `GET …/domains/{domain}/configurations` and print the DNS records exactly as Forge gives them, for Ed to add at GoDaddy.
  - REQ-029b: then `POST …/domains/{domain}/certificates` with `type: "letsencrypt"` (Forge uses DNS-01 through a CNAME it names, which stays valid for renewals).
  - REQ-029c: `domain --check` reports whether the domain and certificate are active; it never changes DNS.

### Approvals (the gate)

- **REQ-030 `[IMPLEMENT]` Deploy gate hook** `scripts/deploy-gate.sh`, PreToolUse on Bash, registered in `hooks/hooks.json`. For a command that runs `deploy.sh` with `setup`, `preview`, `production`, `rollback` or `domain` (not `--check`), or that merges into `main` (`gh pr merge`, `git push` to `main`/`master`), it returns `hookSpecificOutput.permissionDecision: "ask"` with a `permissionDecisionReason` naming the step in plain words. Claude Code then raises a permission request, which the WhenBox plugin already turns into a card on Ed's phone and Mac and only accepts when signed by one of his devices. `detect`, `check`, `status` and `domain --check` pass through.
- **REQ-031 The approval names exactly what runs.** The skill always calls the script with the full target on the command line (`deploy.sh production <full sha>`, `deploy.sh preview <branch>@<sha>`), and the Bash description is the plain sentence Ed sees, for example "Deploy news-personal to production: commit 3f2a91c 'Add weekly digest', 2 new migrations (additive)". The script refuses when `main` (or the branch) on `origin` is not at that commit, so an approval cannot be used for something newer than what Ed read.
- **REQ-032 Approval by repo level** (from the car plan's matrix: deploying is action 9, anything a client sees is 10, pushing a branch is 7, pushing to main is 8, secrets are 11):

  | Step | Experiment | Personal | Client |
  |---|---|---|---|
  | Push a branch for a preview (7) | no card while dev-loop already allows it; voice in car mode | voice on a `mobile/…` branch, else tap | tap |
  | `setup` (8 + 9) | one card; voice may approve in car mode | tap | not in v1 (REQ-035) |
  | `preview` (9) | one card; voice OK | tap | tap |
  | Merge to `main` + `production` (8 + 9, 10 for Client) | one card covering both; voice OK | tap | tap |
  | `rollback` started by the script after a failed check | covered by the deploy's approval | covered | covered |
  | `rollback` asked for later | card; voice OK | tap | tap |
  | `domain` | card; voice OK | tap | tap |
  | Entering secrets (11) | never through an agent (REQ-061) | never | never |

  "Tap" means the card must be answered on Ed's phone or Mac. Until car mode exists, every approval is a tap. When car mode exists, the gate passes the level with the request so WhenBox Host can refuse a voice approval the matrix does not allow; the script itself does not judge voice versus tap.
- **REQ-033 One card per deploy.** A merge-and-deploy is one approval: the skill runs `deploy.sh production <sha> --merge <pr number>`, which merges the PR with `gh pr merge <n> --merge` and then watches the deploy that push to deploy starts. No second card for the deploy itself.
- **REQ-034 Refusal is final for that request.** If Ed declines, the skill reports "Not deployed" with the reason he gave and does not ask again in the same turn.
- **REQ-035 Client repos in v1:** `setup` refuses for Client repos ("Client apps are set up by Ed"); `preview`, `production` and `rollback` work only for sites already in `sites.json` (which Ed can add by hand with `deploy.sh adopt <site id>`, REQ-036).
- **REQ-036 `adopt <forge site id>`** (tap for every level): records an existing Forge site (for example WhenBox) in `sites.json` after checking that its repository matches `origin`. Changes nothing on Forge.

### Preview sites

- **REQ-040** One preview site per app, created on first `preview`: same steps as REQ-021 to REQ-026, with name `<repo>-preview`, database `<repo>_preview`, `APP_ENV=staging`, `MAIL_MAILER=log`, `QUEUE_CONNECTION=sync`, no workers, no scheduler, push to deploy off. Never a copy of production data.
- **REQ-041** Each `preview <branch>@<sha>`: check the branch on `origin` is at `<sha>` (push it first if needed, under REQ-032's rule for step 7), `PUT …/sites/{preview}/git` with `source_control_provider: "github"`, `repository`, `branch`, then deploy and check as REQ-046 to REQ-048.
- **REQ-042** After migrations on preview, run `db:seed --force` through the deploy script only when `deploy.json` has `seed_preview: true`.
- **REQ-043** A failed preview health check is reported, never rolled back (preview is where failures belong).
- **REQ-044** Experiment repos may skip preview: `production` does not require a preview first. For Personal repos, the card for `production` says whether the same commit passed a preview.

### Production deploys

- **REQ-045 Merge.** With `--merge <pr>`: the PR must target `main`, be mergeable, and its head must be the commit being deployed; then `gh pr merge <pr> --merge --match-head-commit <sha>` (never squash, so the approved commit stays in `main`'s history). The card names the PR head commit; the script deploys the merge commit this creates and records both in `sites.json`.
- **REQ-046 One deploy at a time per server.** Before starting, `GET …/servers/{server}/deployments`; if any deployment on the server is running, wait (poll every 15 s, at most 10 minutes), then go on. This also spaces out Ed's batched pushes.
- **REQ-047 Start and watch.**
  - REQ-047a: if push to deploy started it (after a merge), find it with `GET …/sites/{site}/deployments?filter[commit_hash]=<sha>`, waiting up to 60 s for it to appear; otherwise `POST …/sites/{site}/deployments`.
  - REQ-047b: poll `GET …/deployments/{deployment}` every 5 s until `status` is `finished` or `failed`, at most 12 minutes (Forge stops a deployment after 10).
  - REQ-047c: on `failed`, fetch `GET …/deployments/{deployment}/log`, keep the last 40 lines with secrets masked (REQ-062), report them. Forge keeps the previous release live when a zero-downtime deployment fails, so no rollback is needed; say so.
- **REQ-048 Health check after deploy.**
  - REQ-048a: `GET https://<address><health_path>` must return 200 within 10 s. Try 3 times, 10 s apart.
  - REQ-048b: each path in `deploy.json` `smoke_paths` must return a status below 500.
  - REQ-048c: the release Forge reports as deployed must carry the expected commit (`commit.hash` of the deployment).
  - REQ-048d: on failure in production, roll back at once (REQ-050) and report both the failure and the rollback.
- **REQ-049 Migrations safety.**
  - REQ-049a: before deploying, list migration files added between the live commit and the new one (`git diff --name-only --diff-filter=AM <live>..<new> -- database/migrations`).
  - REQ-049b: flag a migration as destructive when it contains `dropColumn`, `dropTable`, `dropIfExists` on an existing table, `renameColumn`, `rename(`, `->change()`, or raw `DROP`/`ALTER … TYPE`. The card says "N new migrations, M destructive". Destructive migrations need a tap at every level, even when voice could approve the deploy.
  - REQ-049c: when there are new migrations, before deploying take a database copy over SSH as `forge`: `pg_dump` of the site's database (credentials read on the server from the site's `.env`, never sent back) to `~/deploy-backups/<site>/<UTC timestamp>-<sha7>.sql.gz`, keeping the 5 newest per site. A failed backup stops the deploy.
  - REQ-049d: rollback never runs `migrate:rollback`. Migrations are expected to be additive (old code must work with the new schema); the developer and QA prompts already build to the spec, and REQ-049b is the backstop.

### Rollback

- **REQ-050** Rollback re-activates the release that was live before the current one: over SSH as `forge`, find `/home/forge/<site>/releases/<id>` for the previous successful deployment ID, check it exists, and `ln -sfn <that dir> /home/forge/<site>/current` (atomic; no sudo needed, `forge` owns the symlink).
- **REQ-051** Then, on the server, `php8.5 current/artisan queue:restart` when the site has a worker, and `php8.5 current/artisan optimize` (each release has its own caches).
- **REQ-052** Then run the health check (REQ-048a). If it fails too, stop and tell Ed plainly: "Production is down and the previous release did not fix it", with the deploy log tail. Never try a third release by itself.
- **REQ-053** Turn push to deploy off for the site after an automatic rollback (`DELETE …/deployments/push-to-deploy`), so the next push to `main` does not redeploy the broken commit; the report says so and `production` turns it back on after the next good deploy.
- **REQ-054** A rollback records the bad commit in `sites.json` (`last_rollback: {from, to, at, reason}`); `production` refuses that exact commit again unless called with `--retry-rolled-back`.

### Credentials and secrets

- **REQ-060 Forge token.** Read from the macOS Keychain: `security find-generic-password -s dev-loop-forge -a ed-holloway -w`. Fallback: `FORGE_API_TOKEN` in the environment (for a headless test). Never from `~/.config/forge/token` (that is Ed's broader CLI login). Passed to curl through a header file in a mode-700 temporary directory or `--header @-`, never on the command line where `ps` shows it.
- **REQ-061 App secrets come from Ed, never through an agent.** For keys in `required_env`, the report lists the names and says: "Add these in Forge: <site> → Environment, then run status". The skill never asks Ed to paste a secret into a conversation or a WhenBox reply, and never reads the production `.env` back (`GET …/environment` is never called). `status` checks that required keys are set by asking the server over SSH for key names with non-empty values only.
- **REQ-062 Masking.** Before anything is printed, logged or put in a card, the script removes `deployment_url`, any URL containing `token=` or `/push/`, and every value of `password`, `token`, `secret`, `key`, `APP_KEY`, `DB_PASSWORD` fields. Deploy log lines matching `(?i)(password|secret|token|key)=\S+` have the value replaced with `***`.
- **REQ-063** Nothing secret is ever written to the repo, `deploy.json`, `.dev-loop/`, or `sites.json` (which holds IDs and addresses only).

### The skill (`skills/deploy/SKILL.md`)

- **REQ-070** Arguments: empty (= the next sensible step), `setup`, `preview [branch]`, `production`, `rollback`, `status`, `domain <name>`.
- **REQ-071** With no argument: run `check` and `status`, then pick: no site → `setup`; a `dev-loop/…` branch with a finished run and no PR → push it and open a PR (`gh pr create --base main`), then `preview` for Personal/Client or `production --merge` for Experiment; otherwise report status.
- **REQ-072** Talk to Ed the dev-loop way: a few sentences, one question at a time, numbered choices, suitable for voice (car plan). The card sentence follows REQ-031.
- **REQ-073** Report after every live step: address, commit, health result, what needs Ed. Under 6 lines.
- **REQ-074** Never edit `deploy.sh`, `deploy-gate.sh`, `sites.json` or `levels.json` from the skill, and never call the Forge API except through `deploy.sh`.

### Documentation

- **REQ-090** `skills/build-loop/SKILL.md` Finishing step 2: add "How to put it online: `/dev-loop:deploy`" to the summary for Laravel apps.
- **REQ-091** README "Deploy" section (commands, what Ed sets up once, where credentials live) and the guardrail correction; marketplace description and version 0.2.0.

## Data Models

`deploy.json` (repo root, committed):

```jsonc
{
  "type": "laravel",                  // laravel | static | node | apple | other
  "php": "8.5",
  "node_build": true,
  "database": "pgsql",
  "queue": true,
  "scheduler": false,
  "health_path": "/up",
  "smoke_paths": ["/"],
  "seed_preview": false,
  "required_env": ["ANTHROPIC_API_KEY"],
  "mailer": null,
  "manual_steps": []                  // for unsupported types: commands Ed runs, e.g. "apple/scripts/testflight.sh"
}
```

`~/.config/dev-loop/sites.json` (per Mac, mode 600):

```jsonc
{
  "edh72/news-digest": {
    "org": "ed-holloway",
    "server_id": "1209288",
    "server_ip": "146.190.70.213",
    "production": {"site_id": "…", "name": "news-digest-ab12cd34.on-forge.com", "database_id": "…", "database_user_id": "…", "worker_id": "…", "domains": []},
    "preview": {"site_id": "…", "name": "…", "branch": "dev-loop/2026-10-29-1530"},
    "last_deploy": {"sha": "…", "deployment_id": "…", "at": "…", "health": "ok"},
    "last_rollback": null
  }
}
```

`~/.config/dev-loop/levels.json` (per Mac, mode 600, written only by Ed): `{"edh72/whenbox": "personal", "edh72/some-client-app": "client"}`.

`.dev-loop/deploy-log.jsonl`: `{"at","command","call":"POST /orgs/…/sites","status":201,"ms":812}` per call; `{"at","command","result":{…REQ-016 shape…}}` per command.

## Degraded Mode / Fallback Behavior

- **REQ-080** Forge API returns 429: wait for `X-RateLimit-Reset` (or 60 s), retry the same call up to 3 times, then stop with "Forge is limiting requests; try again in a minute".
- **REQ-081** Forge API returns 5xx or 503 (maintenance) or times out (30 s per call): retry twice, 10 s apart, then stop. A setup stopped this way resumes from `sites.json` (REQ-012 ordering).
- **REQ-082** SSH unreachable: `setup`, `preview` and deploys without migrations go on; a deploy with migrations stops before deploying (no backup, no deploy); an automatic rollback cannot run, so the report says "Forge kept the site up if the deploy failed; if the health check failed, roll back in Forge's dashboard: <site> → Deployments" and the push-to-deploy switch-off (REQ-053) still runs through the API.
- **REQ-083** WhenBox not reachable: the permission request falls back to Claude Code's own prompt at the terminal (the WhenBox plugin's existing behaviour); nothing deploys without an approval.
- **REQ-084** Forge's site creation is still running after 5 minutes: stop with "Forge is still creating the site; run setup again later", which resumes.
- **REQ-085** The Forge API changes shape (it is Early Access): any response missing an expected field is a hard stop naming the call and field, never a guess.

## Error Handling

- **REQ-086** Each Forge/GitHub call: at most 3 attempts as above; failures are counted in `.dev-loop/deploy-log.jsonl`. After 3 failed `production` attempts for the same commit (failed deployment or failed health check), `production` refuses that commit until `--retry-rolled-back` (REQ-054 shares this record).
- **REQ-087** Any step that fails leaves a clear state: what was created (from `sites.json`), what was not, and the one command to continue.
- **REQ-088** Exit codes: 0 done, 1 failed, 2 refused (build running, missing approval target, commit mismatch, Client setup), 3 unsupported app type.

## What Ed does once

1. Create a Forge API token named "dev-loop deploy" at https://forge.laravel.com/profile/api with only these scopes: `server:view`, `site:create`, `site:meta`, `site:manage-project`, `site:manage-deploys`, `site:manage-environment`, `site:manage-ssl`, `site:manage-queues`, `site:manage-integrations`, `server:create-databases`, `server:create-daemons`, `server:create-schedulers`, `user:view`, `organization:view`. Not included on purpose: anything that deletes, `server:create`, `server:manage-*`, `site:manage-commands`, `site:manage-nginx`, `credential:*`, `billing:manage`, `server:web-terminal`. Set an expiry (a year). Save it with `security add-generic-password -s dev-loop-forge -a ed-holloway -w` (prompts for the token; it is never typed into a conversation).
2. Check Forge's GitHub connection can see new private repos (Forge → Source control). If it is limited to chosen repositories, allow all of `edh72`'s, or add each new one.
3. Set levels for the repos that are not Experiment in `~/.config/dev-loop/levels.json` (WhenBox `personal`, client repos `client`).
4. Answer the decisions below.

## Out of Scope (v1)

- Creating Forge servers, resizing, or any server-level setting (nginx, PHP, firewall, Reverb panel).
- Reverb, Horizon, Octane, Pulse, Redis setup, managed databases, object storage.
- DNS changes (GoDaddy) — Ed adds the records `domain` prints.
- Scheduled database backups to S3 (only the pre-migration copy of REQ-049c).
- Deleting sites, databases or workers (the token cannot).
- A preview per pull request, created and removed automatically.
- Client first-time setup; deploying to servers not in Ed's Forge organization (jarvis on CloudPanel, wristy-website's rsync).
- Automating static, Node, Mac and iPhone releases (adapters exist and say "not yet").
- Laravel Cloud and Envoyer.
- Rolling back database migrations.
- GitHub branch protection (Decision 1).

## Acceptance Criteria

Tests live in `tests/deploy/` and run with `bash tests/deploy/run.sh`. They put a stub `curl`, `gh` and `ssh` first on `PATH` that answer from fixture files (recorded from the real API shapes above) and record every call, so no test touches Forge, GitHub or the server.

- **AC-01** `detect` on fixture repos prints `laravel` (with `queue`, `scheduler`, `node_build`, `required_env` right), `static`, `node`, `apple`, `other`.
- **AC-02** With `.dev-loop/state.json` status `running`, every command but `status` exits 2 and makes no call.
- **AC-03** `setup` makes, in order: create database, create site (with every field in REQ-022, `push_to_deploy: false`), poll until installed, put environment, put deploy script, create worker (only when `queue: true`), put healthcheck, create deployment, poll, health check, enable push to deploy. `sites.json` is written after each.
- **AC-04** `setup` killed after the site is created and run again creates nothing twice and finishes.
- **AC-05** The environment sent contains `APP_ENV=production`, `APP_DEBUG=false`, a 44-character `APP_KEY` value after `base64:`, the database password from the create-database call, and empty values for `required_env`; that password, the APP_KEY and the token appear in no output, log line or file left behind (grep stdout, stderr, `.dev-loop/`, `$TMPDIR`).
- **AC-06** No call ever uses `GET …/environment`, any `DELETE` except push-to-deploy, `POST …/servers`, `…/nginx`, `…/commands`, or `…/integrations/reverb`.
- **AC-07** `production <sha>` exits 2 when `origin/main` is not at `<sha>`.
- **AC-08** With a running deployment on the server, `production` waits and starts only after it finishes.
- **AC-09** A deployment fixture ending `failed` produces a report with the masked log tail and no rollback; one ending `finished` with `/up` returning 500 three times produces the SSH symlink command for the previous release ID, `queue:restart`, a second health check, and push to deploy switched off.
- **AC-10** `production` refuses a commit recorded in `last_rollback` without `--retry-rolled-back`.
- **AC-11** A diff adding a migration with `dropColumn` is reported as destructive; any new migration triggers the `pg_dump` SSH call before the deployment call, and a failing `pg_dump` stops before it.
- **AC-12** The gate hook returns `permissionDecision: "ask"` for `deploy.sh setup|preview|production|rollback|domain <x>`, `gh pr merge`, `git push origin main`; and nothing (allow to continue) for `deploy.sh status|check|detect` and `domain --check`.
- **AC-13** A 429 response is retried after the reset time; three 503s stop with REQ-081's message.
- **AC-14** Masking: fixture responses containing `deployment_url`, a `/github/push/<token>` URL and `DB_PASSWORD=x` never appear unmasked anywhere.
- **AC-15** `setup` exits 2 for a repo whose level is `client`; `static`/`node`/`apple` repos exit 3 with `manual` steps.
- **AC-16** Live run, after Ed approves it on a card: a fresh throwaway Experiment app made by dev-loop is set up on EDH-APPS, deployed, passes `/up`, gets a deliberately broken commit that fails `/up` and is rolled back automatically, and `status` shows the earlier commit live. Ed removes the test site in Forge afterwards.
- **AC-17** Every REQ above is present in the code (the plan-tasks final verification task).

## Decided without Ed (change any of these)

- Deploys use the Forge API directly from a bash script; not the Forge CLI and not a third-party MCP server.
- New apps go on `on-forge.com` addresses; custom domains are added later with `domain`.
- Rollback switches the `current` symlink over SSH, because the new Forge API has no rollback endpoint.
- Merges keep a merge commit (no squash), so the approved head is in `main`'s history.
- Preview sites send mail to the log and never get production data.

## Decisions for Ed

1. **Protecting `main`.** GitHub Free can't protect a branch on a private repo, and even with GitHub Pro an agent using Ed's GitHub login could still merge. Suggest: rely on the Mac-side gate (REQ-030); no GitHub Pro for now.
2. **Which server new apps go on.** EDH-APPS already has seven sites on 1 vCPU / 2 GB. Choices: 1) EDH-APPS, and the script stops and asks once it would hold more than 10 sites; 2) a second small server just for agent-built apps. Suggest 1.
3. **Previews.** Choices: 1) one preview site per app, used for Personal (and Client) repos, while Experiment apps go straight to production; 2) previews for every app; 3) no previews in v1. Suggest 1.
4. **The Forge token.** Suggest a new scoped token in the Keychain (above), not the existing CLI login.
5. **Push to deploy after setup.** Choices: 1) on, as on Ed's other sites (merging is the approval); 2) off, so only the script deploys. Suggest 1.

## Sources (fetched Oct 29, 2026)

- Forge API introduction and rate limits: https://forge.laravel.com/docs/api-reference/introduction, https://forge.laravel.com/docs/api-reference/rate-limiting
- Forge OpenAPI: https://forge.laravel.com/api/docs.openapi
- Deployments (zero-downtime macros, retention, push to deploy, deploy hooks, health checks): https://forge.laravel.com/docs/sites/deployments.md
- Sites, on-forge.com domains, deploy keys: https://forge.laravel.com/docs/sites/the-basics.md, https://forge.laravel.com/docs/sites/repository-access.md
- Domains and Let's Encrypt DNS-01: https://forge.laravel.com/docs/sites/domains.md
- Environment variables: https://forge.laravel.com/docs/sites/environment-variables.md
- API tokens and scopes: https://forge.laravel.com/docs/api.md
- Forge CLI: https://forge.laravel.com/docs/cli.md
- Old Forge rollback (git reset, 2021, classic Forge): https://laravel.com/blog/forge-deployment-rollbacks
- Laravel Cloud preview environments (alternative, not chosen): https://cloud.laravel.com/docs/preview-environments
- GitHub branch protection on Free: live API answer for `edh72/whenbox`, Oct 29, 2026
