# .github/

GitHub-specific repository configuration. GitHub only reads this directory at
the repository root.

> **Why this file is not `README.md`.** GitHub gives `.github/README.md`
> precedence over the root `README.md` for the repository landing page. A readme
> here would shadow the top-level [`README.md`](../README.md), so this directory
> is documented in `WORKFLOWS.md` instead (GitHub does not treat that filename as
> a profile readme). See the root [`AGENTS.md`](../AGENTS.md).

## Layout

| Path | Purpose |
|---|---|
| [`workflows/packages.yml`](workflows/packages.yml) | CI for the [`packages/`](../packages/) Yarn workspace — builds, typechecks, and tests every member on pushes to `main` and on PRs that touch `packages/**`. |
| [`workflows/lint.yml`](workflows/lint.yml) | CI for the [`packages/`](../packages/) Yarn workspace — ESLint lint + Prettier format-check on every member, on the same triggers. Split from `packages.yml` so a style regression is reported independently of a build/test failure. |
| [`workflows/rust.yml`](workflows/rust.yml) | CI for the [`crates/`](../crates/) Rust workspace — `cargo fmt --check`, `cargo clippy -D warnings`, `cargo check --all-targets`, and `cargo test` on pushes to `main` and PRs that touch `crates/**`. |
| [`workflows/tooling.yml`](workflows/tooling.yml) | CI for everything outside `packages/` and `crates/` — shellcheck (`*.sh`), PSScriptAnalyzer (`*.ps1`), actionlint (the workflows), a dotbot link-source guard (`install*.yaml`), and the Codex config merger Bun tests. Five independent jobs. |
| [`workflows/socket.yml`](workflows/socket.yml) | Supply-chain security gate — runs a [Socket](https://socket.dev) scan (`socketcli`) on every push (all branches), PR (opened/synchronize/reopened), and issue comment, flagging risky dependency changes before they land. Needs the `SOCKET_SECURITY_API_KEY` repo secret. |
| [`workflows/opencode-plugin-updates.yml`](workflows/opencode-plugin-updates.yml) | Hourly (cron) + manual dispatcher that fans out over a matrix of opencode plugins, calling the reusable `update-opencode-plugin.yml` once per plugin. |
| [`workflows/update-opencode-plugin.yml`](workflows/update-opencode-plugin.yml) | Reusable (`workflow_call`) workflow that compares one plugin's pinned version across one or more opencode config files (e.g. [`opencode.json`](../home/.config/opencode/opencode.json) + [`tui.json`](../home/.config/opencode/tui.json)) against the latest GitHub release of its upstream repo and opens a single PR bumping every file that references it. |

## `workflows/packages.yml`

- **Toolchain via mise.** Node and Yarn are installed by
  [`jdx/mise-action`](https://github.com/jdx/mise-action) from
  [`packages/mise.toml`](../packages/mise.toml) (the action runs with
  `working_directory: packages`). This keeps CI and local development on the
  same pinned versions.
- **Caching.** The action caches the mise tool installs (keyed on the mise
  config); a separate `actions/cache` step caches Yarn 4's global package cache
  at `~/.yarn/berry/cache` (keyed on `packages/yarn.lock`).
- **Steps.** `yarn install --immutable` (the committed lockfile must already be
  up to date), then `yarn turbo run build typecheck test` — Turborepo runs and
  caches each member's tasks.

## `workflows/lint.yml`

- **Same toolchain + caching as `packages.yml`.** mise installs Node + Yarn from
  [`packages/mise.toml`](../packages/mise.toml); the mise tool installs and Yarn 4's
  global cache (`~/.yarn/berry/cache`) are both cached.
- **Steps.** `yarn install --immutable`, then `yarn turbo run lint format:check` —
  ESLint (per-member `eslint.config.mjs`) plus Prettier `--check`. Neither task
  `dependsOn ^build` in `turbo.json`, so no build runs.
- **Why a separate workflow.** Lint/format checks are split from build/test so a
  style regression surfaces independently. There is intentionally **no Biome** —
  the workspace uses ESLint for linting and Prettier for formatting.

## `workflows/rust.yml`

- **Scope.** Gates the [`crates/`](../crates/) Rust workspace (currently the
  `mxm4-haptic` bin+lib crate). Triggers on pushes to `main` and PRs touching
  `crates/**` (or this workflow).
- **Toolchain.** rustup is preinstalled on `ubuntu-24.04`, so there is no
  third-party Rust action — the job just logs `rustc`/`cargo --version`. The
  Linux build needs libudev headers (the hidapi hidraw backend), installed via
  `apt-get install -y libudev-dev`.
- **Caching.** `actions/cache` caches `~/.cargo/registry`, `~/.cargo/git`, and
  `crates/mxm4-haptic/target`, keyed on `crates/mxm4-haptic/Cargo.lock`.
- **Steps.** `rustup component add clippy rustfmt`, then `cargo fmt --check`,
  `cargo clippy --all-targets --all-features -- -D warnings`,
  `cargo check --all-targets`, and `cargo test` (all via
  `--manifest-path crates/mxm4-haptic/Cargo.toml`).

## `workflows/tooling.yml`

Gates everything outside the `packages/` and `crates/` workspaces. Triggers on
pushes to `main` and PRs touching any `*.sh`, `*.ps1`, `install*.yaml`, a
workflow, `scripts/ci/**`, or the Codex config merger files. Five independent
jobs on `ubuntu-24.04`:

- **shellcheck.** Runs `shellcheck` over every tracked `*.sh`
  (`git ls-files '*.sh' | xargs shellcheck`); installs shellcheck only if the
  runner lacks it.
- **psscriptanalyzer.** `Invoke-ScriptAnalyzer -Recurse -Severity Error` under
  the preinstalled `pwsh`; any Error-severity finding fails the job.
- **actionlint.** Downloads the pinned actionlint release binary, verifies it
  against a hardcoded SHA256, then lints the workflows (no third-party action).
- **dotbot-links.** Runs [`scripts/ci/check-dotbot-links.mjs`](../scripts/ci/check-dotbot-links.mjs),
  a zero-dependency Node guard that fails if any dotbot `link:` source in the
  four `install*.yaml` files does not resolve to a real path in the repo.
- **codex-config.** Uses `jdx/mise-action` to provision Bun, then runs
  `mise exec bun@latest -- bun test scripts/bootstrap/` so the surgical Codex
  config merger is tested before bootstrap changes ship.

## `workflows/socket.yml`

Supply-chain protection: catches malicious or risky dependency changes via
[Socket](https://socket.dev) before they merge.

- **Triggers.** Every `push` on **all** branches, `pull_request`
  (opened/synchronize/reopened), and `issue_comment` (created — for Socket's PR
  comment interactions). A `concurrency` group keyed on ref + SHA cancels
  superseded runs.
- **Steps.** `actions/checkout` (full history on push; depth 2 on PRs for diff
  analysis) → `actions/setup-python` (3.12) → `pip install socketsecurity
  --upgrade` → `socketcli --target-path "$GITHUB_WORKSPACE" --scm github
  --pr-number <n>`. The CLI auto-detects repo, branch, commit, committer, and
  changed files from git.
- **Secrets + permissions.** Requires the `SOCKET_SECURITY_API_KEY` repo secret;
  uses the default `GITHUB_TOKEN` (as `GH_API_TOKEN`) to post PR comments.
  Declares `issues: write`, `pull-requests: write`, `contents: read`.
- **Python is intentional here.** Socket's CLI is distributed only as a Python
  package (`socketsecurity`), so this workflow uses Python to run an external
  tool — it is **not** repo-authored Python and is exempt from the Node/Bun
  scripting rule in [`AGENTS.md`](../AGENTS.md).

## `workflows/opencode-plugin-updates.yml` + `workflows/update-opencode-plugin.yml`

Keep the opencode plugins pinned in the config files under
[`home/.config/opencode/`](../home/.config/opencode/) — currently
[`opencode.json`](../home/.config/opencode/opencode.json) and
[`tui.json`](../home/.config/opencode/tui.json) — up to date with their upstream
GitHub releases.

- **Dispatcher (`opencode-plugin-updates.yml`).** Runs hourly (`cron: "0 * * * *"`,
  UTC) and on manual `workflow_dispatch`. A single job uses a `matrix` (one entry
  per plugin) to call the reusable workflow with three inputs: the plugin's package
  name *exactly as written in the config `plugin` array*, the GitHub
  `owner/repo` that publishes its releases, and `config-paths` — the
  newline-separated list of config files that pin it (`oh-my-openagent` lists both
  `opencode.json` and `tui.json`; the rest default to `opencode.json`). **To track
  a new plugin, add one matrix entry — nothing else changes.** `fail-fast: false`
  keeps one plugin's failure from aborting the others.
- **Reusable worker (`update-opencode-plugin.yml`, `workflow_call`).** For one
  plugin: reads the latest release tag via `gh release view` (strips the
  `tag-prefix`, default `v`), reads the currently pinned version from the first
  listed config that references the plugin, and when it differs from the latest,
  bumps the version in **every** listed config that references it and opens a
  single PR (assigned to the repo owner) on a per-version branch
  `automation/opencode-plugin/<slug>/<version>`. It is idempotent — an existing
  branch for that exact version short-circuits — and it closes superseded
  automation PRs for the same plugin so only the newest bump stays open.
- **Format-preserving bump.** The worker does a literal substitution (Perl
  `\Q..\E`) on the version token rather than a `jq` rewrite, so each config's
  exact formatting (tabs, key order, spacing) is preserved and the diff stays
  minimal. A `jq` pass would reserialize and reformat the whole file. The match is
  anchored on the leading quote + `"<plugin>@<version>"` and leaves any export
  subpath after the version (e.g. `"<plugin>@<version>/tui"` in `tui.json`)
  intact.
- **Requirements.** Both workflows declare `contents: write` + `pull-requests: write`.
  The repo setting *Settings → Actions → General → Workflow permissions → Allow
  GitHub Actions to create and approve pull requests* must be enabled for the
  default `GITHUB_TOKEN` to open the PRs. PRs opened by `GITHUB_TOKEN` do not
  trigger further workflow runs.

There is intentionally no bootstrap/dotbot wiring here: workflows are consumed by
GitHub Actions, not symlinked into `$HOME`.

## Adding a workflow

1. Add `workflows/<name>.yml`.
2. Add a row to the layout table above (this directory's hard
   documentation-sync requirement).
3. If the change is repo-structure-visible, update the root
   [`AGENTS.md`](../AGENTS.md) and [`README.md`](../README.md) in the same
   commit.
