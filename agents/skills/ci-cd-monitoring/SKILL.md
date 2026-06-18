---
name: ci-cd-monitoring
description: >
  Playbook for monitoring and fixing a CI/CD pipeline (GitHub Actions /
  GitLab CI). Load this BEFORE running ANY pipeline command or touching a
  run/job. Triggers (any = load now): running `gh run`/`gh pr checks`/`glab
  ci` (`status`/`view`/`trace`/`list`); checking, watching, polling, or
  waiting on a pipeline/build/checks/run/workflow/job after a push or PR/MR;
  the build is red/failing and you need the log, the failing job, or to fix
  it until green; deciding whether a failing check is pre-existing or your
  regression; a flaky job or re-run decision. Phrases: "check CI", "why is
  the build failing", "is the pipeline green".
  Covers the terminal-state poll list, `gh`/`glab` recipes
  for watching runs and fetching failed-job logs, the fix-red-until-green
  procedure, the forbidden fixes (disable/skip/rerun/`[skip ci]`/force-push),
  the pre-existing-failure exception, and the auto-merge caveat. Do NOT load
  it for opening/promoting a PR/MR (use `pr-mr`) or for local-only test runs
  that never touch a pipeline.
---

# CI/CD pipeline monitoring

The pipeline is the canonical verification surface. Local runs are necessary but not
sufficient — the pipeline runs in a clean environment with additional jobs (integration
tests, security scans, matrix builds, deploy previews) and is the gate reviewers and merge
automation trust.

**MUST monitor the pipeline to completion on every push that opens or updates a PR/MR.**
"Push and walk away" is forbidden. The task is done when the pipeline lands green, not when
the push succeeds.

## Poll until a terminal state

**MUST poll until a terminal state**: `success`, `failure`, `cancelled`, `timed_out`,
`action_required`. `pending` / `queued` / `running` / `in-progress` are **NOT** terminal —
keep polling. CLI recipes (`gh pr checks --watch`, `gh run view --log-failed`,
`glab ci status`, `glab ci trace`, the pipelines `jq`) →
[`references/commands.md`](references/commands.md).

### Use ONE blocking command, NOT repeated one-shot polls

**MUST wait with a single blocking call** — either a native `--watch` command or a shell
loop that polls internally and only returns at a terminal state. **MUST NOT** fire a
one-shot status command (`gh run view`, `glab ci status`, the pipelines `jq`) over and over
as separate tool calls to simulate waiting — that burns turns, spams the session, and races
the pipeline. One command goes in, blocks until the pipeline is terminal, comes back once.

- **GitHub** — prefer the built-in blockers, which already wait to completion and set a
  non-zero exit on failure: `gh pr checks <num> --watch --fail-fast`,
  `gh run watch <run-id> --exit-status`.
- **GitLab** — `glab ci status` is one-shot; wrap it (or `glab ci get --pipeline-id <id>`,
  to block on a specific pipeline by ID) in a `while` loop with a `sleep` so the **single**
  invocation blocks until terminal.

Both the GitHub `--watch` recipes and the GitLab shell-loop recipe are in
[`references/commands.md`](references/commands.md) — copy one, run it as a single command,
and wait for it to return.

## If the pipeline fails, fix it until green

A red pipeline is an open defect on the PR/MR — in-scope regardless of whether the failing
job tests code you touched directly:

1. Read the failing job's log. Identify the actual error, not just the exit code.
2. Diagnose root cause — real regression, flake, env drift, missing secret, dependency
   cooldown, lint trip.
3. Fix at the source. For genuinely flaky tests outside the change, **surface the flake to
   the user** before retrying — don't mask flakes by re-running.
4. Commit, push, resume monitoring.
5. Repeat until `success`.

**MUST NOT** declare ready, hand off, or mark complete while the pipeline is failing,
cancelled, or still running.

## Forbidden "fixes" for a red pipeline

**MUST NOT** "fix" a red pipeline by:

- Disabling, skipping, or deleting the failing job/check.
- Marking the failing test as skipped/expected-failure without explicit user approval.
- Re-running failed jobs hoping for a different result (more than once, only for genuinely
  flaky unrelated jobs, and only after surfacing the flake).
- Pushing `[skip ci]` / `[ci skip]` / `--ci-skip` on a change-bearing commit.
- Force-pushing to hide failed pipeline history.

## Exception — pre-existing failures

If the failing job was already red on the default branch (**verify against the latest
default-branch pipeline**), document in the PR/MR body, surface to the user, don't block.
**MUST NOT** assume "pre-existing" without verifying — "looks unrelated" is not verification.

## Auto-merge

Auto-merge (GitHub auto-merge, GitLab "Merge when pipeline succeeds") does **not** absolve
monitoring. It merges on green; it does not fix red.
