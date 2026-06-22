---
name: gitlab-issues
description: >
  Playbook for reading and creating GitLab issues, tasks, and work items
  from the CLI. Load this BEFORE you read an issue/work-item URL, create or
  update an issue or task, choose between an issue and a task, apply or
  create labels, set start-date/estimate planning metadata, upload an image
  to an issue/task description, or write a rich issue/task body (mermaid,
  tables, templates). It covers `glab issue view` vs `glab api`, the
  work-item URL gotcha, the list→match→create→apply label workflow,
  `glab api --form` image uploads, decision-complete bodies (resolve
  forks, don't defer), and the bug/feature description templates. Do NOT load it for pull-/merge-request lifecycle work (use
  `pr-mr`) — including the PR/MR body checklist sync — or for pipeline
  monitoring (use `ci-cd-monitoring`). The "never surface an auth token"
  guardrail lives in core AGENTS.md and applies regardless.
---

# GitLab issues / tasks / work items

> Self-managed hosts (e.g. `git.jpi.app`) are addressed exactly like `gitlab.com`; the
> examples below use a placeholder host where one is needed.

## Scope guardrail — issue work only, no source edits

Reading, triaging, and creating/updating issues, tasks, and work items is **documentation
work**, not implementation. While doing it you **MUST NOT** modify any actual repository
files — no source edits, no config changes, no fixes, no refactors — unless the user has
**explicitly** asked for that change in the same request. Investigating an issue, writing a
rich description, or breaking work into tasks is **not** authorization to touch code. If the
issue clearly implies a fix and the user has not asked you to make it, stop at the
issue/task and ask before editing files.

## Reading an issue or work item

- **MUST** use `glab issue view` to read issues and work items. **MUST NOT** hit
  `glab api projects/.../issues/...` for read access — `glab issue view` already wraps the
  API, handles host resolution, renders the body cleanly, and accepts `--comments` and
  `-F json`.
- **Work items vs. issues — URL gotcha**: the web UI serves the same IID under **both**
  `/-/issues/<iid>` and `/-/work_items/<iid>`. `glab issue view` accepts `/-/issues/<iid>`
  but **rejects** `/-/work_items/<iid>` with `Invalid issue format`. **MUST** rewrite any
  `/-/work_items/<iid>` URL to `/-/issues/<iid>` before passing it. (`glab work-items` is
  EXPERIMENTAL and has no `view` subcommand.)
- `glab api` is the fallback **only** when `glab issue view` can't express the call (custom
  fields, batch queries, GraphQL work-item queries). State the reason inline when using it.

Host-resolution detail and read recipes → [`references/work-items.md`](references/work-items.md).

## Issues vs. tasks — choose the right type

An **issue** is the externally visible problem/feature/bug that owns the branch/MR, review,
and closing keyword. A **task** is a smaller implementation unit under or alongside an
issue. **MUST NOT** default to creating everything as an issue — decide whether the unit
needs independent triage/release-notes/customer visibility (issue) or is only a breakdown
item (task). Use `glab work-items` for tasks; **MUST NOT** fake tasks as checkbox prose when
the project expects task objects. Commands → [`references/work-items.md`](references/work-items.md).

## Starting work — start date and estimate

Before opening the branch/MR for a GitLab issue or task, **MUST** set or update planning
metadata: **start date** (actual day work starts, `$(date +%F)`), **estimate** (GitLab
time-tracking duration for issue-sized work, or a weight for tiny tasks), and a **due date
only when supplied** — **MUST NOT** invent a deadline. **MUST** record the estimate source
in the body when non-obvious; if the user supplied an estimate, preserve it exactly unless
new evidence makes it wrong (then update it and leave a brief comment). CLI flags →
[`references/planning-metadata.md`](references/planning-metadata.md).

## Creating an issue or work item

- **MUST** assign labels reflecting type (`bug`, `feature`, `chore`, `docs`, `refactor`),
  area/component, priority, and any other dimension already in use.
- **MUST** inspect the project's existing label set first and reuse existing labels rather
  than inventing parallel names.
- **MUST NOT** open an issue/task with **zero labels** — unlabelled items rot in triage.
- **SHOULD** apply multiple labels when work spans multiple dimensions
  (`bug` + `area::auth` + `priority::high`).
- **MUST** assign the issue/task to the authenticated user on creation:
  `--assignee "$(glab api user | jq -r '.username')"`. Resolve dynamically every time —
  **MUST NOT** hard-code a username. Same rule on `glab issue update --assignee`.

The rule is **reuse first, create when missing — never skip**. A dimension with no good
existing label is **not** an excuse to omit it; it is a signal to create the label. The
list→match→**create-if-missing**→apply workflow (and the requirement that every new label
carry `--name`, `--color` HEX, `--description`) is mandatory →
[`references/label-workflow.md`](references/label-workflow.md). If the right label genuinely
can't be determined, pick the closest existing label, note the uncertainty in the body, and
ask the user in the same turn — **MUST NOT** silently downgrade to fewer labels.

## Decision-complete bodies — resolve forks, don't defer

An issue/task body **MUST** be decision-complete: a reader **MUST** be able to start
implementing without another round of questions. Every design fork you can settle from the
codebase, existing conventions, or a defensible default **MUST** be settled in the body and
written as a **decision**, not a question.

- **MUST NOT** ship an "Open questions", "TBD", "To be decided", or "Open/Notes — maybe"
  section that hands unresolved design choices to the implementer. Investigate the repo and
  decide; an empty fork is a research task, not a deliverable to defer.
- **MUST** write each settled fork as a decision, with a one-line rationale when the choice
  is non-obvious (e.g. `Decision: hide unresolved services, don't drop silently — operators
  still get a server-side warn`). When you picked a default rather than a hard requirement,
  phrase it `Decision: X — revisit if Y`, so it reads as settled with an explicit
  change-trigger instead of an open question.
- **SHOULD** scope each issue to a **single MR-sized deliverable** and settle everything in
  that scope now. **MUST NOT** structure the body as sequential delivery phases
  ("Phase 1 / Phase 2 …") that imply multiple MRs — one issue is delivered by exactly one MR
  (see `pr-mr`). Genuinely separable later work (its own maintenance window, a human/infra
  decision, an independent release) → a **separate follow-up issue** (itself one MR), named
  and linked (`Refs #N`), not a deferred phase of this one.
- A fork you **genuinely cannot** resolve — it needs product/human judgement, is
  irreversible, or needs access you lack — is the **only** thing that may stay unresolved.
  **MUST** raise it to the user **in the same turn** (options + your recommendation) and
  resolve it before finalizing rather than parking a vague question in the body. If it must
  be parked, record it as a **blocking decision needed** with options and a recommended
  default — never as an open-ended question.

## Rich content in descriptions

Plain-text bullet walls are hard to triage. **MUST** use the host's full markdown surface:

- **MUST** embed at least one of a diagram (mermaid), a screenshot/image, a state/flow
  table, or a comparison table whenever the issue describes a flow, system interaction, UI
  surface, or before/after change.
- **MUST** prefer mermaid over ASCII art; **MUST** use fenced code blocks with a language
  tag for every snippet/log/config/command; **MUST** provide alt text in every
  `![alt](url)`; **MUST NOT** hotlink Slack/Notion/Drive/Dropbox or any auth-requiring host.
- **SHOULD** use task lists for acceptance criteria and `<details>` for long logs.

Mermaid types, image hosting, math, and full guidance →
[`references/rich-content.md`](references/rich-content.md).

## Image uploads

**MUST** upload through `glab api` with `--form` (not `--field`) to `POST /projects/:id/uploads`,
and use the returned `markdown` field **verbatim**. **MUST NOT** hand-build the reference
from `url`/`full_path`. The credential-handling guardrail (never read or pass a GitLab token
to a non-glab tool; `401` → STOP and ask the user to `glab auth login`) is in core
AGENTS.md. Mechanics, endpoint payload, and worked example →
[`references/image-uploads.md`](references/image-uploads.md).

## Description templates

Bug-report and feature-request templates, plus the "pipe the description from a file"
requirement (shell quoting mangles mermaid backticks / nested fences) →
[`references/templates.md`](references/templates.md).
