# Checkbox-progress sync — reference

Applies to **issues and PR/MR bodies on both hosts.** `- [ ]` / `- [x]` lines render as
interactive checkboxes — the canonical, host-rendered progress surface that reviewers,
dashboards, and merge automation read. **MUST** keep them in sync with reality as work
happens, not after the fact.

**Required behaviour** (also summarized in `SKILL.md`):

- **MUST** tick each checkbox **at the moment** the corresponding item lands (commit
  pushed, file written, sub-task verified) — never batch ticks, never tick speculatively.
- **MUST** keep the issue's checklist and the PR/MR body's mirrored checklist in lock-step.
  Update both in the same turn; a mismatch is a defect.
- **MUST NOT** edit checkbox text or reorder items as a side effect of ticking. Tick state
  changes only — copy, ordering, indentation stay byte-identical so diff history is readable.
- **MUST NOT** delete unchecked items to "make progress visible". Out-of-scope items get
  `~~strikethrough~~` and an inline note (`- [ ] ~~Item Z~~ — deferred, see #N`), not deletion.
- **MUST NOT** promote a draft PR/MR to ready while the checklist has unchecked items
  unless every remaining item is explicitly marked out of scope in the same body.
- **SHOULD** post a brief progress comment when a meaningful batch flips (e.g. all items in
  one section) — silent in-place edits don't trigger notifications on either host.

## Updating from the CLI

Both hosts require a **full-body replacement**; no per-checkbox API. Fetch the current body,
flip the exact `- [ ]` → `- [x]` lines, push the whole body back. Preserve every other byte:

```bash
# Per-user scratch dir — never /tmp.
SCRATCH="${XDG_RUNTIME_DIR:-$HOME/.cache}"

# GitLab — issue
CURRENT=$(glab issue view <iid> -F json | jq -r '.description')
UPDATED=$(printf '%s' "$CURRENT" | sed 's|^- \[ \] Implement validateEmail()$|- [x] Implement validateEmail()|')
printf '%s' "$UPDATED" > "$SCRATCH/issue-body.md"
glab issue update <iid> --description "$(cat "$SCRATCH/issue-body.md")"

# GitLab — MR body (same pattern)
CURRENT=$(glab mr view <iid> -F json | jq -r '.description')
glab mr update <iid> --description "$(cat "$SCRATCH/mr-body.md")"

# GitHub — issue
CURRENT=$(gh issue view <num> --json body -q '.body')
gh issue edit <num> --body-file "$SCRATCH/issue-body.md"

# GitHub — PR body
CURRENT=$(gh pr view <num> --json body -q '.body')
gh pr edit <num> --body-file "$SCRATCH/pr-body.md"
```

**MUST NOT** pass a fresh body that omits sections you didn't regenerate — that silently
deletes prose, comments, or other checklists. Always start from the live `description` /
`body` and apply targeted line flips.

## Promotion to ready

Once every required checkbox is ticked, gates pass, and the pipeline is green:

```bash
gh pr ready <num>                              # GitHub
glab mr update <iid> --ready                   # GitLab
```

Verify the flip landed (`gh pr view <num> --json isDraft` → `false`;
`glab mr view <iid> -F json | jq .draft` → `false`). A draft that won't promote usually
means a required check is still pending — finish the check, don't work around it via API.
