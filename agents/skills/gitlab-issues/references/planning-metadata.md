# Start date & estimate — reference

Before opening the branch/MR for a GitLab issue or task, **MUST** set or update planning
metadata:

- **Start date**: actual day work starts (`$(date +%F)`), not the day the issue was created.
- **Estimate**: GitLab time-tracking duration (`30m`, `2h`, `1d`, `1w`) for issue-sized
  work. For tiny tasks where the project uses weights, set a weight instead.
- **Due date**: only when the issue/milestone/user supplied one. **MUST NOT** invent a deadline.

Prefer direct CLI flags. `glab work-items update` supports `--startdate`, `--duedate`,
`--weight`, `--assignee`; `glab issue create` supports `--time-estimate`, `--time-spent`,
`--due-date`, `--weight`. `glab issue update` does **not** expose start-date or time-estimate
flags — use `glab work-items update` for the start date and the time-tracking API for an
estimate on an existing issue:

```bash
# Existing issue: mark the actual start date.
glab work-items update <issue-iid> -R <group>/<project> \
  --startdate "$(date +%F)" \
  --assignee "$(glab api user | jq -r '.username')"

# Existing issue: set or replace the time estimate.
glab api --method POST projects/:fullpath/issues/<issue-iid>/time_estimate -f "duration=4h"

# New issue: set estimate at creation.
glab issue create -R <group>/<project> \
  --title "fix(auth): reject expired sessions" \
  --description "$(cat "${XDG_RUNTIME_DIR:-$HOME/.cache}/issue-body.md")" \
  --time-estimate 4h --due-date 2026-05-29
```

**MUST** record the estimate source in the issue/MR body when non-obvious (e.g. "Estimate:
4h based on two UI screens plus API validation"). If the user supplied an estimate, preserve
it exactly unless new evidence makes it wrong; then update it and leave a brief comment
explaining the change.
