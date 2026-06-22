---
name: pr-mr
description: >
  Pull-request / merge-request lifecycle playbook for GitHub (`gh`) and
  GitLab (`glab`). REQUIRED reading — load this BEFORE any `gh pr create`,
  `glab mr create`, or before promoting/editing a draft, linking an issue
  to a PR/MR, mirroring or ticking a checklist in a PR/MR body, or
  recovering from a duplicate/empty PR/MR. It covers draft-first ordering,
  the forbidden issue-linked branch flows, the duplicate-create trap, the
  source-branch substitution trap (and the verification jq), issue-linking
  keywords, pre-create gates, create rules (assign-to-self, draft), and
  checkbox-progress sync. Do NOT load it for plain local commits or branch
  naming (use `git-workflow`), for reading/creating standalone issues or
  tasks (use `gitlab-issues`), or for watching a pipeline that is already
  open (use `ci-cd-monitoring`). The high-consequence guardrails (secrets,
  destructive ops, git config) live in core AGENTS.md and apply regardless.
---

# Pull requests / merge requests

## One issue → one MR (no phase-splitting)

One issue/work item is delivered by **exactly one** MR, no matter how large:

- **MUST NOT** split an issue across multiple MRs, "stacked" MRs, or a Phase 1 / Phase 2 / Phase 3 sequence of MRs. Size is never a reason to split — add more commits to the single MR, not more MRs.
- **MUST NOT** open a second MR for "the rest" of an issue. A large checklist stays on the one draft MR; tick items as they land.
- Work that is **genuinely separable** (needs its own maintenance window, a human/infra decision, or an independent release) belongs to a **separate issue** with its **own** single MR — link it as a follow-up (`Refs #N`). It is **never** a later "phase" of the current issue's MR.
- An issue body authored as sequential delivery phases that imply multiple MRs is a **defect**: fold the in-scope phases into the one deliverable and move any truly-separate phase out to its own issue (see `gitlab-issues`).

## Required ordering — draft up-front, work against it, promote to ready

Issue linking happens **after** the PR/MR exists, never before:

1. Create the branch **manually** with a Git Flow name (see `git-workflow`). **MUST NOT**
   start from any issue-linked branch flow.
2. Make the **first real commit** carrying actual work and push it. **MUST NOT** use
   `git commit --allow-empty` or fabricate a scaffolding commit just to open the draft.
   If nothing concrete exists, the draft is premature.
3. **Immediately after the first push**, open as draft (`gh pr create --draft` /
   `glab mr create --draft`). **MUST** pin the source branch explicitly (see the
   source-branch substitution trap). Don't accumulate local commits before opening — the
   draft is the working surface.
4. Link the issue via a closing keyword in the draft body (at creation or via
   `gh pr edit --body` / `glab mr update --description`). Mirror the issue's checklist into
   the draft body (see checkbox sync).
5. Commit and push frequently. **MUST** tick checkboxes as each item lands — never batch
   at the end.
6. When work is complete, verified, and the pipeline is green, promote with
   `gh pr ready <num>` / `glab mr update <iid> --ready`. **MUST NOT** promote a draft with
   unchecked items unless they're explicitly marked out of scope in the body.

**Forbidden flows** (all fabricate branch names and bypass the rules above):

- GitHub: *Development → Create a branch*, *Linked issues* picker on the PR-creation form,
  `gh issue develop`, `gh pr create --issue <N>`.
- GitLab: *Create merge request* button on an issue, *Linked issues* picker,
  `glab issue develop`, `glab mr create --related-issue <N>`.

## Two traps that make a broken PR/MR without failing the create call

Both are silent. **MUST** read [`references/traps.md`](references/traps.md) before any
create call:

- **Duplicate-create trap** — `gh pr create` / `glab mr create` are **not** idempotent.
  **MUST** query for an existing open PR/MR on the source branch **before every** create.
  **MUST NOT** retry after lost output, `409 Conflict`, a `glab` recovery-file message, or
  a timeout without first re-running the pre-create query.
- **Source-branch substitution trap** — `--related-issue` (glab), `--issue` (gh), and the
  *Linked issues* picker silently use a host-fabricated `<N>-<slug>` branch, opening the
  PR/MR with zero commits. **MUST NOT** use them. **MUST** pin `--source-branch` /
  `--head` to `$(git branch --show-current)` and **MUST** verify after creation.

## Issue-linking keywords

Use closing keywords in the PR/MR **body**. Bare `#N` autolinks but does **not** auto-close.
Full per-host table → [`references/issue-linking.md`](references/issue-linking.md).

## GitLab project paths

**MUST** pass the project path with slashes intact (`products/examvue-duo/examvue-apps`).
**MUST NOT** URL-encode it (`products%2F…`). Prefer `:fullpath` when the repo remote points
at the target.

## Pre-create gates

- **MUST** run the project's verification commands (test / lint / typecheck / build —
  whichever it defines) on the current HEAD. **MUST NOT** submit with known-failing checks
  unless documented in the body and user-approved.
- **MUST** commit and push all changes — clean tree, upstream up to date:

```bash
git status                                              # MUST be clean
git rev-parse --abbrev-ref @{u} >/dev/null 2>&1 \
  && git log @{u}..                                     # if upstream exists, MUST be empty
                                                        # else: `git push -u origin <branch>` first
```

## Create rules

- **Title MUST** follow Conventional Commits — squash merge then produces a clean single
  commit on the default branch.
- **Body SHOULD** include: problem summary, what changed, how it was verified. Link via
  trailers (`Closes #123`, `Refs !456`). When the linked issue has a tracking checklist,
  **MUST** mirror that checklist into the PR/MR body.
- **MUST** assign the PR/MR to the authenticated user.
- **MUST** open as a draft (`--draft`) on initial creation. Promote to ready only after
  work is complete, verified, and the pipeline is green.

| Host | Assign-to-self | Additional flags |
|---|---|---|
| GitHub | `gh pr create --assignee @me` | — |
| GitLab | `glab mr create --assignee "$(glab api user \| jq -r '.username')"` | `--remove-source-branch` (cleanup after merge) |

## Checkbox-progress sync

`- [ ]` / `- [x]` lines in **issue and PR/MR bodies** are the canonical, host-rendered
progress surface. **MUST** keep them in sync with reality **as work happens**:

- **MUST** tick each checkbox **at the moment** the item lands — never batch, never tick
  speculatively.
- **MUST** keep the issue's checklist and the PR/MR's mirrored checklist in lock-step
  (update both in the same turn; a mismatch is a defect).
- **MUST NOT** edit checkbox text or reorder items as a side effect of ticking — tick
  state changes only; copy/ordering/indentation stay byte-identical.
- **MUST NOT** delete unchecked items to "make progress visible" — out-of-scope items get
  `~~strikethrough~~` + an inline note (`- [ ] ~~Item Z~~ — deferred, see #N`), not deletion.
- **MUST NOT** promote a draft to ready while the checklist has unchecked items unless
  every remaining item is explicitly marked out of scope in the same body.
- **SHOULD** post a brief progress comment when a meaningful batch flips — silent in-place
  edits don't notify on either host.

CLI update recipes (full-body replacement; no per-checkbox API) and promotion verification
→ [`references/checkbox-sync.md`](references/checkbox-sync.md).

## After every push that opens or updates a PR/MR

**MUST** monitor the pipeline to a terminal state and fix it red-to-green — load
`ci-cd-monitoring` for the poll states, CLI recipes, and the fix-red procedure.
