# Reading & work-items — reference

## Reading an issue or work item

**MUST** use `glab issue view`. **MUST NOT** hit `glab api projects/.../issues/...` for read
access — `glab issue view` already wraps the API, handles host resolution, renders the body
cleanly, and accepts `--comments` and `-F json`.

**Work items vs. issues — URL gotcha**: GitLab is migrating issues to the unified *work
items* system. The web UI serves the same IID under **both** `/-/issues/<iid>` and
`/-/work_items/<iid>`. `glab issue view` accepts the `/-/issues/<iid>` form but **rejects**
`/-/work_items/<iid>` with `Invalid issue format`. **MUST** rewrite any `/-/work_items/<iid>`
URL to `/-/issues/<iid>` before passing it. (`glab work-items` is EXPERIMENTAL and has no
`view` subcommand — list/create/update/delete only.)

## Issues vs. tasks

An **issue** is the externally visible problem/feature/bug that owns the branch/MR, review,
and closing keyword. A **task** is a smaller implementation unit under or alongside an
issue. **MUST NOT** default to creating everything as an issue. Decide whether the unit
needs independent triage/release notes/customer visibility (issue) or is only a breakdown
item (task).

Use the task-specific `glab work-items` commands for tasks — **MUST NOT** fake tasks as
checkbox prose when the project expects task objects:

```bash
# List existing tasks before creating duplicates.
glab work-items list --type task -R <group>/<project> --per-page 100 --output json

# Create a task. Reference the parent issue in the description when the CLI can't express hierarchy directly.
# Scratch goes under the per-user temp dir — never /tmp.
BODY="${XDG_RUNTIME_DIR:-$HOME/.cache}/task-body.md"
cat > "$BODY" <<'EOF'
Parent: #42

Acceptance:
- [ ] Reject addresses without @
EOF

glab work-items create --type task -R <group>/<project> \
  --title "Implement validateEmail()" \
  --description "$(cat "$BODY")" \
  --output json

# Update task state fields.
glab work-items update <task-iid> -R <group>/<project> \
  --assignee "$(glab api user | jq -r '.username')" \
  --startdate "$(date +%F)" \
  --duedate "2026-05-29" \
  --weight 1
```

`glab work-items` is EXPERIMENTAL but is the CLI surface that creates/updates task work
items. Use `glab issue ...` for issue-specific operations (comments, close/reopen, boards,
time tracking, descriptions).

## Self-managed host resolution

`glab` resolves the host in this order: (1) current repo's git remote, (2) host embedded in
a URL argument, (3) `GITLAB_HOST` env var, (4) global default (`gitlab.com`). Inside a clone
of the target project, bare `glab issue view <iid>` works. The env var is only required when
none of the higher-priority sources point at the right host **and** you don't want to pass
the full URL:

```bash
# Inside the target project clone.
glab issue view 22 --comments

# From an unrelated cwd — full URL (preferred for one-off reads).
glab issue view "https://git.jpi.app/products/examvue-duo/examvue-apps/-/issues/22" --comments

# From an unrelated cwd, scripting multiple calls.
GITLAB_HOST=git.jpi.app glab issue view 22 -R products/examvue-duo/examvue-apps --comments

# JSON.
glab issue view 22 -F json | jq .
```

`glab api` is the fallback **only** when `glab issue view` can't express the call (custom
fields, batch queries, GraphQL work-item queries). State the reason inline when reaching for
`glab api`.
