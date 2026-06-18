# CI/CD CLI recipes — reference

## Wait with ONE blocking command (do NOT loop one-shot polls as separate tool calls)

Run **a single** command that returns only when the pipeline reaches a terminal state. Use a
native `--watch` blocker where one exists; otherwise wrap a one-shot status check in a shell
loop so the **one** invocation blocks internally. Never re-run a one-shot status command as
repeated tool calls to fake waiting.

> **Shell-variable naming.** The loop variable is `ci_status`, not `status` or `state`. In
> zsh `status` is a read-only special parameter (an alias for `$?`), so `status=$(…)` aborts
> with `read-only variable: status` when a recipe is pasted into an interactive zsh — and
> `state` is avoided alongside it. Keep loop variables prefixed (`ci_status`); don't "simplify"
> them back to the bare names.

```bash
# GitHub — native blockers (already wait to completion; non-zero exit on failure)
gh pr checks <num> --watch --fail-fast                      # blocks on ALL checks for the PR
gh run watch <run-id> --exit-status                         # blocks on ONE run; exit 1 if it fails

# GitHub — shell loop fallback when you only have a run id and want custom handling
while :; do
  ci_status=$(gh run view <run-id> --json status,conclusion \
    | jq -r '.conclusion // .status')                       # conclusion set only when done
  case "$ci_status" in
    success) echo "green"; break ;;
    failure|cancelled|timed_out|action_required)
      echo "terminal: $ci_status"; gh run view <run-id> --log-failed; exit 1 ;;
    *) sleep 15 ;;                                           # queued/in_progress → keep waiting
  esac
done
```

```bash
# GitLab — no native --watch on `glab ci status`; block in ONE call with a shell loop.
# Drives off the latest pipeline for the current branch via the API.
branch=$(git branch --show-current)
while :; do
  ci_status=$(glab api "projects/:fullpath/pipelines?ref=$branch&per_page=1" \
    | jq -r '.[0].status')
  case "$ci_status" in
    success) echo "green"; break ;;
    failed|canceled|skipped)
      echo "terminal: $ci_status"
      pid=$(glab api "projects/:fullpath/pipelines?ref=$branch&per_page=1" | jq -r '.[0].id')
      glab ci get --pipeline-id "$pid"                       # show failed jobs; then trace them
      exit 1 ;;
    *) sleep 15 ;;                                           # created/pending/running → keep waiting
  esac
done

# GitLab — block on a SPECIFIC pipeline by ID, e.g. a `.../-/pipelines/2842` URL → id 2842
# (the equivalent of `gh run watch <run-id>`). `glab ci get` infers project + host from the
# repo remote inside a checkout; add `-R host/group/sub/project` to target another project.
pipeline_id=2842
while :; do
  ci_status=$(glab ci get --pipeline-id "$pipeline_id" --output json | jq -r '.status')
  case "$ci_status" in
    success) echo "green"; break ;;
    failed|canceled|skipped)
      echo "terminal: $ci_status"
      glab ci get --pipeline-id "$pipeline_id" --output json \
        | jq -r '.jobs[] | select(.status=="failed") | "\(.id)\t\(.stage)/\(.name)"'  # failed jobs
      exit 1 ;;
    *) sleep 15 ;;                                           # created/pending/running → keep waiting
  esac
done
```

`:fullpath` resolves the slash-separated project path from the repo remote; pass an explicit
`group/sub/project` (slashes intact, never URL-encoded) when the remote doesn't point at the
target. GitLab terminal statuses: `success`, `failed`, `canceled`, `skipped` (also `manual`
/ `scheduled` when a stage is gated); non-terminal: `created`, `waiting_for_resource`,
`preparing`, `pending`, `running`.

## One-shot status / log inspection (for diagnosis, NOT for waiting)

```bash
# GitHub
gh run list --branch "$(git branch --show-current)" --limit 5
gh run view <run-id> --log-failed                           # failed-job logs only

# GitLab
glab ci status                                              # current branch's pipeline summary
glab ci view                                                # interactive pipeline view (humans, not agents)
glab ci trace <job-id>                                      # stream a job's log
glab ci get --pipeline-id <id> --output json \             # one pipeline by ID — full schema
  | jq '{id, iid, status, source, ref, web_url, jobs: [.jobs[] | {name, stage, status}]}'
glab api "projects/$PROJECT/merge_requests/$MR_IID/pipelines" \
  | jq '.[0] | {id, status, sha, web_url}'
```

Pipeline `status` enum (the `.status` field above): non-terminal `created`,
`waiting_for_resource`, `preparing`, `pending`, `running`; terminal `success`, `failed`,
`canceled`, `skipped`, `manual`, `scheduled`. `detailed_status.group` collapses to the same
buckets and is handy for a coarse pass/fail check.

`$PROJECT` is the slash-separated project path (never URL-encoded); prefer `:fullpath` when
the repo remote points at the target.

## Terminal vs. non-terminal states

- **Terminal** (stop polling): `success`, `failure`, `cancelled`, `timed_out`,
  `action_required`.
- **Non-terminal** (keep polling): `pending`, `queued`, `running`, `in-progress`.
