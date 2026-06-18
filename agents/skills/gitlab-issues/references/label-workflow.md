# Label workflow — reference

## Creating an issue or work item — label rules

- **MUST** assign labels yourself reflecting type (`bug`, `feature`, `chore`, `docs`,
  `refactor`), area/component, priority, and any other dimension already in use.
- **MUST** inspect the project's existing label set first and reuse existing labels rather
  than inventing parallel names.
- **MUST NOT** open an issue/task with zero labels. Unlabelled items rot in triage.
- **SHOULD** apply multiple labels when work spans multiple dimensions (e.g. `bug` +
  `area::auth` + `priority::high`).
- **MUST** assign the issue/task to the authenticated user on creation:
  `--assignee "$(glab api user | jq -r '.username')"`. Resolve dynamically every time —
  **MUST NOT** hard-code a username (yours, the user's, or anyone else's). Same rule on
  `glab issue update --assignee`.

## Required workflow (list → match → create-if-missing → apply)

The rule is "**reuse first, create when missing — never skip**". A dimension with no good
existing label is **not** an excuse to omit that dimension; it is a signal to create the
label. The list-and-skip pattern (search, find nothing matching, create with zero labels or
only the labels that happened to exist) is the primary failure mode this section forbids.

1. **List** project labels (and parent group's, since group labels are inherited):

   ```bash
   glab label list -R <group>/<project> --per-page 100 -F json | jq -r '.[].name'
   glab label list -g <group> --per-page 100 -F json | jq -r '.[].name'   # inherited
   ```

2. **Match** the work across every dimension already in use: type, area/component,
   priority, status, plus any other axis visible in the listed labels. If a dimension has
   an existing label that fits, reuse it.

3. **Create-if-missing** — for every dimension where no existing label fits, **MUST** create
   the missing label *before* opening the issue:

   ```bash
   # Project scope.
   glab label create -R <group>/<project> \
     --name "area::reporting" --color "#1F75CB" \
     --description "Reporting and analytics surface"

   # Group scope (inherited — prefer for cross-project taxonomies like type/priority).
   glab label create -g <group> \
     --name "priority::high" --color "#D9534F" \
     --description "Should be picked up in the current iteration"
   ```

   Every new label **MUST** carry `--name`, `--color` (HEX), `--description`. A label
   without a description rots in triage. Scoped labels (`scope::value`) auto-replace
   siblings within their scope — prefer scoped labels for mutually-exclusive dimensions
   (priority, status, area, severity).

4. **Apply** — pass the full set on `glab issue create` (`--label` is comma-separated and
   accepts pre-existing and just-created names):

   ```bash
   glab issue create -R <group>/<project> --title "..." \
     --description "$(cat "${XDG_RUNTIME_DIR:-$HOME/.cache}/issue-body.md")" \
     --label "bug,area::reporting,priority::high"
   ```

## When uncertain

If the right label genuinely can't be determined from existing context, pick the closest
existing label, note the uncertainty in the issue body, and ask the user in the same turn.
**MUST NOT** silently downgrade to fewer labels or omit the uncertain dimension.
