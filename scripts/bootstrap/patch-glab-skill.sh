#!/usr/bin/env bash
# scripts/bootstrap/patch-glab-skill.sh
#
# Re-patch the CLI-managed `glab` skill after `glab skills install` (the
# install.conf.yaml shell step) overwrites it with upstream content.
#
# Upstream writes scratch files under the shared /tmp. This repo DENIES /tmp for
# agent tools (see agents/SHARED_AGENTS.md "Temporary / scratch files" and the
# opencode.json permission blocks), so every `/tmp/<file>` path in the skill is
# rewritten to the per-user temp dir `${XDG_RUNTIME_DIR:-$HOME/.cache}/<file>`
# (the exact fallback the rule prescribes; safe when $XDG_RUNTIME_DIR is unset,
# e.g. on macOS). The literal shell expression is written into the markdown so
# the agent copy-pastes a working, /tmp-free command.
#
# dotbot processes install.conf.yaml fully before the per-OS yaml that invokes
# this, so the `glab skills install` has already run. Idempotent: a second run
# finds no `/tmp/` left and writes nothing. PowerShell counterpart:
# patch-glab-skill.ps1 (must produce byte-identical output).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GLAB_SKILL_DIR="$SCRIPT_DIR/../../agents/skills/glab"

if [[ ! -d "$GLAB_SKILL_DIR" ]]; then
  printf 'patch-glab-skill.sh: glab skill dir not found at %s; nothing to patch.\n' "$GLAB_SKILL_DIR"
  exit 0
fi

patched=0

while IFS= read -r -d '' file; do
  tmp="$file.patch-tmp"
  # Literal /tmp/ -> per-user temp dir. Single-quoted sed program keeps $ literal
  # in the OUTPUT (we want the shell expression in the file, not its expansion);
  # the | delimiter means the slashes in pattern and replacement need no escaping.
  # shellcheck disable=SC2016 # the unexpanded $ is intentional: it must reach the file
  sed 's|/tmp/|${XDG_RUNTIME_DIR:-$HOME/.cache}/|g' "$file" >"$tmp"
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
    patched=$((patched + 1))
    printf 'patch-glab-skill.sh: patched %s\n' "$file"
  fi
done < <(find "$GLAB_SKILL_DIR" -type f -name '*.md' -print0)

if [[ "$patched" -eq 0 ]]; then
  printf 'patch-glab-skill.sh: glab skill already free of /tmp scratch paths; no changes.\n'
fi
