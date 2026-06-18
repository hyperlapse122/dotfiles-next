# MR Review — Draft Notes, Code Suggestions, Discussions

Use **draft notes** to batch all review comments into a single review event. This avoids spamming the MR with individual notifications and groups your feedback visibly.

For **discussions (replying, resolving)** → [Discussions section below](#discussions)

## Fetching MR data

The `/diffs` endpoint returns full diff content for every file (including the complete patch text). Use `jq` to filter client-side. Add `unidiff=true` (GitLab 16.5+) for standard unified diff format, which can be easier to parse programmatically.

```bash
# Extract just the list of changed file paths (response still includes full diff content)
glab api "projects/<project_id>/merge_requests/<mr_iid>/diffs?per_page=100" \
  | jq '.[].new_path'

# Fetch diff for a specific file
glab api "projects/<project_id>/merge_requests/<mr_iid>/diffs?per_page=100" \
  | jq '.[] | select(.new_path == "path/to/file.rb")'

# Use unidiff=true for standard unified diff format (easier to parse)
glab api "projects/<project_id>/merge_requests/<mr_iid>/diffs?unidiff=true&per_page=100" \
  | jq '.[] | select(.new_path == "path/to/file.rb") | .diff'

# Page through large responses
glab api "projects/<project_id>/merge_requests/<mr_iid>/diffs?per_page=20&page=2"

# MR metadata (state, title, author, target branch)
glab api "projects/<project_id>/merge_requests/<mr_iid>"
```

## MR version SHAs

Inline draft notes require three SHAs from the latest version. Always fetch these before posting inline comments:

```bash
# ⚠️ The API returns base_commit_sha / head_commit_sha / start_commit_sha
# but the position object expects base_sha / head_sha / start_sha — jq renames them here
glab api "projects/<project_id>/merge_requests/<mr_iid>/versions" \
  | jq '.[0] | {base_sha: .base_commit_sha, head_sha: .head_commit_sha, start_sha: .start_commit_sha}'
```

## Draft notes

### General draft note (not inline)

Use `-f` flags — no position object needed:

```bash
glab api --method POST \
  "projects/<project_id>/merge_requests/<mr_iid>/draft_notes" \
  -f note="Your summary comment here"
```

### Inline draft note

**⚠️ Do NOT use `-f` flags for inline draft notes** — the nested `position` object will not serialize correctly and the comment will silently appear as a general (non-inline) note instead of attached to the diff line.

**Use JSON piped with `Content-Type: application/json` instead:**

```bash
echo '{"note":"your comment","position":{"position_type":"text","base_sha":"BASE_SHA","head_sha":"HEAD_SHA","start_sha":"START_SHA","old_path":"path/to/file.rb","new_path":"path/to/file.rb","new_line":42}}' \
  | glab api --method POST \
    "projects/<project_id>/merge_requests/<mr_iid>/draft_notes" \
    -H "Content-Type: application/json" --input -
```

For multi-line note bodies, write the JSON to a temp file first:

```bash
cat > ${XDG_RUNTIME_DIR:-$HOME/.cache}/draft.json << 'DRAFT'
{
  "note": "your comment here",
  "position": {
    "position_type": "text",
    "base_sha": "BASE_SHA",
    "head_sha": "HEAD_SHA",
    "start_sha": "START_SHA",
    "old_path": "path/to/file.rb",
    "new_path": "path/to/file.rb",
    "new_line": 42
  }
}
DRAFT
glab api --method POST \
  "projects/<project_id>/merge_requests/<mr_iid>/draft_notes" \
  -H "Content-Type: application/json" --input ${XDG_RUNTIME_DIR:-$HOME/.cache}/draft.json
```

**Do NOT use `<(...)` process substitution** — it is not available in plain `sh`.

## Position object — line type rules

The `position` object must use the correct line field(s) depending on diff prefix:

| Diff prefix | Use | Omit |
|-------------|-----|------|
| `+` (added line) | `new_line` | `old_line` |
| `-` (removed line) | `old_line` | `new_line` |
| ` ` (context line) | both `old_line` and `new_line` | — |

### Extracting line numbers from diff output

Line numbers come from the diff hunk headers, not from the source file's absolute line numbers. Hunk headers look like:

```
@@ -old_start,count +new_start,count @@
```

Count lines down from `old_start` / `new_start` to find the `old_line` / `new_line` for your target line. Lines prefixed with `-` advance `old_line`, lines prefixed with `+` advance `new_line`, and context lines (no prefix) advance both.

### Setting `old_path` and `new_path`

For most files (no rename): copy `new_path` to both `old_path` and `new_path`.

For renames (`renamed_file: true` in the diff response): use the `old_path` and `new_path` values directly from the diff object — they will differ.

## Code suggestions

When you want to propose a specific code change, use GitLab's suggestion syntax in the note body. GitLab renders this as an "Apply suggestion" button.

Single-line replacement (comment on that line):

````text
```suggestion:-0+0
replacement code here
```
````

Multi-line replacement (adjust offsets — `-N` includes N lines above, `+M` includes M lines below the anchor):

````text
```suggestion:-2+1
all replacement lines here
```
````

Use suggestions when you have a concrete fix. Use plain text comments for questions or patterns.

Suggestions go in inline draft notes — include the suggestion block in the `note` field of the JSON position body (see [Inline draft note](#inline-draft-note) above).

## Bulk publish

After creating all draft notes, publish them as a single review event:

```bash
glab api --method POST \
  "projects/<project_id>/merge_requests/<mr_iid>/draft_notes/bulk_publish"
```

This sends one notification to the MR participants with all your comments grouped together.

## Discussions

Always check existing discussions before posting — earlier threads may already be resolved or outdated.

```bash
# Fetch all discussions (each thread has id, notes array, position info)
glab api "projects/<project_id>/merge_requests/<mr_iid>/discussions?per_page=100"

# Extract key fields
glab api "projects/<project_id>/merge_requests/<mr_iid>/discussions?per_page=100" \
  | jq '.[] | {id, resolved: .notes[0].resolved, body: .notes[0].body}'
```

### Reply to a discussion

Use a draft note with `in_reply_to_discussion_id` — no position needed:

```bash
glab api --method POST \
  "projects/<project_id>/merge_requests/<mr_iid>/draft_notes" \
  -f note="your reply" \
  -f in_reply_to_discussion_id="DISCUSSION_ID"
```

### Resolve a discussion

```bash
glab api --method PUT \
  "projects/<project_id>/merge_requests/<mr_iid>/discussions/DISCUSSION_ID" \
  -f resolved=true
```

## Gotchas

- **`-f` for inline notes → silently broken** — position won't serialize; use `--input -` with JSON and `-H "Content-Type: application/json"`
- **No process substitution** — `<(...)` is bash-only; write JSON to `${XDG_RUNTIME_DIR:-$HOME/.cache}/` file if the note body is multi-line
- **SHA field name mismatch** — API returns `base_commit_sha` etc.; position object wants `base_sha` etc. — always apply the jq rename
- **SHAs expire** — always fetch `/versions` fresh; cached SHAs from a previous version may be rejected
- **Line numbers are diff-relative, not file-absolute** — count from hunk headers (`@@ -old,count +new,count @@`), not from the raw file
- **Draft notes are per-user** — `bulk_publish` publishes YOUR drafts; it won't publish drafts belonging to other users
