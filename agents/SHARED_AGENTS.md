# Agent Instructions

> **Precedence**: Project-level `AGENTS.md` overrides any rule here on conflict. Otherwise these rules apply.
> **Style**: [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) keywords — **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**.
> **Skills**: This core holds the rules that bind on _every_ task. Operation-specific playbooks live in on-demand skills — load the named skill **before** doing the matching operation (see Routing Index). The guardrails below never depend on a skill loading.

## Routing Index

| Before you…                                                                                | Load skill            | What it covers                                                                                      |
| ------------------------------------------------------------------------------------------ | --------------------- | --------------------------------------------------------------------------------------------------- |
| **create or manage a PR/MR** — REQUIRED: load before any `gh pr create` / `glab mr create` | `pr-mr`               | draft-first ordering, duplicate/source-branch traps, issue-linking, pre-create gates, checkbox sync |
| read or create GitLab issues / tasks / work items / labels / uploads / descriptions        | `gitlab-issues`       | read flow, issue-vs-task, labels, planning metadata, image uploads, templates                       |
| monitor or fix a CI/CD pipeline                                                            | `ci-cd-monitoring`    | poll states, CLI recipes, fix-red procedure, pre-existing-failure exception                         |
| name/rename a branch, write a commit, or resolve a rebase                                  | `git-workflow`        | forbidden-shape table, rename recipes, commit-type table, rebase intent resolution                  |
| edit `package.json` deps, lifecycle-script overrides, or cooldown handling                 | `js-package-managers` | per-manager override mechanics, exact-pin correction, cooldown handling                             |
| drive a browser / run Playwright tests                                                     | `playwright-cli`      | usage (host-safety rule is in core below)                                                           |

## Secrets (guardrail)

- **MUST NOT** commit secrets, even briefly or in a squash-fixup: `.env` / `.env.*` (except `*.example` / `*.sample` templates), private keys (`*.pem`, `id_*` without `.pub`, `*.age`, GPG/SSH keys), API tokens, OAuth client / webhook / deploy secrets, cloud creds (`~/.aws/credentials`, token-bearing kubeconfigs, service-account JSON), DB connection strings with passwords.
- Accidental commit → **STOP**, notify the user, treat the secret as compromised, rotate it. **MUST NOT** rewrite history (`rebase` / `filter-repo` / `filter-branch`) without explicit instruction.
- **MUST NOT** read or pass an auth token to a non-native tool (e.g. a GitLab token into `curl`/`wget`/`httpie`, or out of a credential store / env var into another tool). Let the official CLI inject credentials itself; if auth fails, **STOP** and ask the user to re-login — never surface the secret.

## Destructive / bypass operations (guardrail)

- **MUST NOT**, without an explicit user request in the same turn: `git commit/push --no-verify`; `git push --force` / `--force-with-lease` to a shared branch (`main`/`master`/`develop` or any branch others may have pulled); `git reset --hard` / `git clean -fdx` on uncommitted work; `git commit --amend` on a pushed commit; `git rebase -i` or any history rewrite on pushed commits; `rm -rf` outside the repo's ignored / build dirs. When genuinely required, **MUST** confirm the exact command and what it destroys first.

## Git config — NEVER touch (guardrail)

- **MUST NOT** modify any git configuration at any scope (`--system` / `--global` / `--worktree` / `--local`), edit any gitconfig file, or set identity / signing / any key. **MUST NOT** override identity via `GIT_AUTHOR_*` / `GIT_COMMITTER_*`, `git commit --author`, or `-c user.email=…`. A config-driven failure → **STOP** and ask the user. No exceptions; if told to "fix the git setup," confirm the exact `git config` command first and run only that.

## Branch naming — gate before first commit

- Every branch name **MUST** start with a Git Flow prefix: `feature/` `bugfix/` `hotfix/` `refactor/` `docs/` `chore/` `release/` (or the project's documented equivalent set).
- Before the **first commit** on any new or newly-switched branch, **MUST** run `git branch --show-current` and confirm the prefix. Treat every fresh branch as failing until confirmed; run the gate once per branch and never skip it on the first commit.
- Gate fails → **MUST** `git branch -m <old> <prefix>/<slug>` **before** the first commit lands; renaming after a commit/push is **forbidden**. The gate rejects shape, not provenance — a hand-picked bare slug (`add-auth`) is as forbidden as an auto-generated name (`opencode/playful-engine`, `13-feat-x`).
- Slug **MUST** be a 3–6 word human summary (`-`-separated), not the issue title / number / a placeholder. **One task = one branch**; **MUST NOT** create a sibling branch — rename instead. (Forbidden-shape table, rename recipes, naming table → `git-workflow`.)

## Commit messages

- **MUST** follow Conventional Commits: `<type>(<scope>)<!>: <description>`.
- Subject **MUST** be entirely lowercase — no exceptions for acronyms, brands, or proper nouns (commitlint `subject-case` rejects any uppercase; put canonical-case tokens in the body) — imperative, no trailing period, ≤50 chars (≤72 max).
- **MUST NOT**: emojis, sentence case, trailing periods, vague subjects (`update stuff`, `fix things`, `wip`), or AI-tool branding (no "Generated with Claude", no `🤖`, no AI `Co-authored-by:`). (Type table, scope/body/breaking-change, trailers, examples → `git-workflow`.)

## Rebase

- During a rebase Git's `--ours` / `--theirs` are **reversed** vs merge: `--ours` is the rebase target (`main`), `--theirs` is the feature commit being applied. Wrong side / direction → `git rebase --abort` and restart; **MUST NOT** continue. (Intent-based conflict resolution → `git-workflow`.)

## Issue ↔ MR scope

- One issue / work item is delivered by **exactly one** MR, regardless of size — **MUST NOT** split it into "phases", stacked/sequential MRs, or a chain of follow-up MRs. Deliver more commits in the single MR, not more MRs.
- **MUST NOT** author or restructure an issue body as sequential delivery "Phase 1 / Phase 2 …" sections that imply multiple MRs. Genuinely separable later work (a prod cut-over, a future migration) → a **separate issue** (itself one MR), linked as a follow-up — never a numbered delivery phase of the current issue. (Detail → `pr-mr`, `gitlab-issues`.)

## CI/CD

- **MUST** monitor the pipeline to a terminal state on every push that opens or updates a PR/MR — the task is done when it lands green, not when the push succeeds. **MUST NOT** declare ready / complete while a pipeline is failing, cancelled, or running.
- **MUST NOT** "fix" a red pipeline by disabling / skipping / deleting a job, re-running hoping for green, pushing `[skip ci]` on a change-bearing commit, or force-pushing to hide history. (Poll states, CLI recipes, fix-red procedure, pre-existing-failure exception → `ci-cd-monitoring`.)

## Task completion — no silent deferral (guardrail)

- A task / issue / MR is **done** only when **every** in-scope item and stated acceptance criterion is actually delivered and verified in it. **MUST NOT** mark work complete while any item is unimplemented, stubbed, reverted, replaced with a weaker substitute, or pushed to a "follow-up" issue/PR, a `TODO`/`FIXME`, or a "known limitation" note. Difficulty or size is not a reason to defer — deliver more commits, not fewer items.
- Genuinely blocked (confirmed upstream/tooling bug, missing access, irreversible/destructive step, or a decision needing human judgment) → **STOP** and surface it to the user with concrete evidence + a proposed path + an explicit ask, then wait. Never silently defer and report done; a user-acknowledged blocker is the only acceptable incomplete item.

## Figma

- **MUST** use the `figma` MCP for any Figma URL; **MUST NOT** fetch via web fetch, browser, or screenshot tools. MCP unavailable → **STOP** and ask the user to fix it; **MUST NOT** improvise an alternative.
- **MUST** re-fetch the latest node every time a node ID is mentioned (cache only within the current turn), and **MUST** diff the fresh response against the implementation before declaring Figma parity, stating any gap explicitly.

## Interactive / long-running processes

- **MUST** use the `tmux` tool (`mcp_interactive_bash`) for dev servers, watch modes, TUIs, REPLs, build watchers — anything that does not terminate. Regular shell execution blocks the session and is **forbidden** for non-terminating commands.

## Temporary / scratch files

- The **shared system temp** dir is **denied** — **MUST NOT** read, write, or execute under `/tmp`, `/var/tmp`, or `/dev/shm`; every operation on those paths fails. This covers ad-hoc scripts, captured logs / command output, and PR / MR / issue body drafts.
- **MUST** use a **per-user** temp dir instead: `$XDG_RUNTIME_DIR` (or `~/.cache` when it is unset or the file is large) on Linux, `$TMPDIR` on macOS, `$env:TEMP` / `%TEMP%` on Windows. Keep scratch in a task-scoped subdir (e.g. `"$XDG_RUNTIME_DIR/agent-scratch"`) and **SHOULD** remove it when the task ends.
- **SHOULD** prefer a git-ignored path **inside the workspace** for files that belong to the task; reserve the per-user temp dir for throwaway scratch that must stay outside the repo.

## Container runtime — rootless Podman (guardrail)

- This host uses **rootless Podman** as its sole container runtime. Docker is not installed.
- **MUST** use `podman` (or the `docker` CLI shim provided by `podman-docker`) for all container operations — `podman run`, `podman build`, `podman compose`, etc.
- **MUST NOT** install Docker, reference `docker.io/docker-ce`, or assume the Docker daemon (`dockerd`) is present. The `docker` binary on this host is the `podman-docker` compatibility shim; it forwards to `podman` and does not start a daemon.
- **MUST NOT** use `sudo podman` unless explicitly required for a root-owned resource. Rootless is the supported mode; all user-space container work runs without `sudo`.
- The rootless socket is at `$XDG_RUNTIME_DIR/podman/podman.sock`. Docker-API clients that read `DOCKER_HOST` are already pointed there via `~/.config/environment.d/65-containers.conf` — no manual override needed.
- Registry auth uses `podman login <registry>` (credentials stored in `~/.config/containers/auth.json`). **MUST NOT** write to or rely on `~/.docker/config.json` — that file is not managed on this host.

## Browser automation (Playwright) — host safety

- This host is Fedora. **MUST NOT** run Playwright browsers directly on a non-Ubuntu-LTS host (`npx playwright test` / `install`, `playwright install-deps`, or a host-installed browser) — unsupported, crashes.
- **MUST** run inside `mcr.microsoft.com/playwright:v<X.Y.Z>-noble`, tag pinned to the project's **exact** Playwright version. **MUST** run non-root (`--user pwuser`, or `--user "$(id -u):$(id -g)"` for user-owned bind mounts); **MUST** pass `--ipc=host` and **SHOULD** pass `--init`. Use rootless `podman` for the container runtime (Docker is not installed on this host). (Test/automation usage → `playwright-cli`.)

## Scripting runtime

- **MUST NOT** use Python for any new scripting, tooling, or codegen; **MUST** use Node.js / Deno / Bun (TypeScript preferred). Shell (`bash` / PowerShell) is acceptable for system bootstrap and OS glue only — **MUST NOT** use it for application logic or codegen. Exception: an established Python project with existing Python tooling — match it and state the exception.

## JavaScript package managers

- User-global config hardens npm / pnpm / Yarn / Bun via three switches — lifecycle scripts disabled, exact-version pinning, 1-week cooldown. **MUST** preserve all three; **MUST NOT** edit user-global configs to relax any of them.
- **MUST** pin every `dependencies` / `devDependencies` / `optionalDependencies` entry to an exact version (no `^` `~` `>=` `latest` `*` `x`); **MUST** correct an existing range when editing a `package.json` for any reason; **MUST NOT** introduce a range or hand-edit a lockfile to dodge the rule.
- `peerDependencies` are the **exception**: they **MUST NOT** be exact-pinned — declare the widest compatible range (`^<major>`, `>=`, `^18 || ^19`, or `*`). **MUST NOT** "correct" a peer range to an exact pin. Internal lockstep/prerelease-versioned peers are the sub-exception and stay exact-pinned; a project `AGENTS.md` may codify this. (Detail → `js-package-managers`.)
- Cooldown: a version **MUST** be ≥1 week old — pin the most recent that qualifies. **MUST NOT** add a package to a preapproved / exclude list, nor lower the cooldown, without explicit per-package user approval. (Per-manager override mechanics, exceptions → `js-package-managers`.)

## mise (tool version manager)

- If any command fails with a `mise ERROR … not trusted` message, **MUST** immediately run `mise trust <path-to-mise.toml>` (or `mise trust` in the project root) before retrying. **MUST NOT** proceed with the original command while the trust error persists.
- After trusting, re-run the original command in the same turn — do not ask the user to do it.

## GitLab CLI (glab)

- **MUST** pass project paths to `glab` / `glab api` with slashes intact (`group/sub/project`), never URL-encoded (`group%2Fsub%2Fproject`); prefer `:fullpath` when the repo remote points at the target. (Issue / MR / pipeline playbooks → `gitlab-issues`, `pr-mr`, `ci-cd-monitoring`.)
