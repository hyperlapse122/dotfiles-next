#!/usr/bin/env bash
# scripts/bootstrap/adopt-agent-of-empires-config.sh
#
# POSIX wrapper for adopt-agent-of-empires-config.mjs. Keeps script parity with
# adopt-agent-of-empires-config.ps1 while the adopt logic runs through
# mise-managed Bun (matching the other bootstrap helpers, e.g.
# configure-codex-config.sh).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MISE_BIN="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"
if command -v mise >/dev/null 2>&1; then
  MISE_BIN="mise"
elif [[ -x "$MISE_BIN" ]]; then
  :
else
  printf 'adopt-agent-of-empires-config.sh: mise not found. Install mise yourself and re-run.\n' >&2
  printf 'adopt-agent-of-empires-config.sh: expected mise on PATH or at %s.\n' "$MISE_BIN" >&2
  exit 1
fi

exec "$MISE_BIN" exec bun@latest -- bun "$SCRIPT_DIR/adopt-agent-of-empires-config.mjs" "$@"
