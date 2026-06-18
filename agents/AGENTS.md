# agents/ Agent Instructions

Files in this directory are **cross-tool agent rule files, shared slash commands, and the runtime skill tree** linked into multiple AI assistants' global paths. Editing any linked file here changes the global rules or commands for every linked tool, on every machine running this dotfiles checkout.

> **`skills/` mixes CLI-managed and hand-authored skills.** Some skills are installed by the `skills` CLI (`npx skills`, tracked in `.skill-lock.json`) or by `glab skills install`; others are hand-authored. You MAY add or edit a skill by hand (create `skills/<name>/SKILL.md`), but **check the source first** — editing a CLI-managed skill (one in `.skill-lock.json`, or the `glab` skill) is overwritten on the next CLI run. `.skill-lock.json` itself is CLI-owned — don't hand-edit it. The rules below about tool-agnostic hand-authoring apply to `SHARED_AGENTS.md` and `commands/`, not to `skills/`.

> **The `glab` skill is auto-patched away from `/tmp`.** After each `glab skills install`, the per-OS bootstrap step `scripts/bootstrap/patch-glab-skill.{sh,ps1}` rewrites every upstream `/tmp/<file>` scratch path in `skills/glab/*.md` to `${XDG_RUNTIME_DIR:-$HOME/.cache}/<file>`, because this repo denies `/tmp` for agent tools. So `skills/glab/` deliberately diverges from upstream here. **Don't hand-fix those paths** (a hand edit is overwritten by the next `glab skills install` anyway) — if the replacement needs to change, edit the patch script.

> **Style**: Use [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) keywords (**MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**) for directives. Match the tone and structure of `SHARED_AGENTS.md`.

## Linkage

`../install.conf.yaml` defines explicit symlinks for both the shared rules file and the shared commands directory:

| Source | Linked to | Loaded by |
|---|---|---|
| `agents/SHARED_AGENTS.md` | `~/.config/opencode/AGENTS.md` | OpenCode (global rules) |
| `agents/SHARED_AGENTS.md` | `~/.codex/AGENTS.md` | Codex (global rules) |
| `agents/SHARED_AGENTS.md` | `~/.claude/CLAUDE.md` | Claude Code (global rules) |
| `agents/commands/` | `~/.config/opencode/commands` | OpenCode (slash commands) |
| `agents/commands/` | `~/.codex/prompts` | Codex (prompts) |
| `agents/skills/` | `~/.agents/skills` | OpenCode **and Codex** (runtime skills) |
| `agents/skills/` | `~/.claude/skills` | Claude Code (runtime skills) |
| `agents/.skill-lock.json` | `~/.agents/.skill-lock.json` | `skills` CLI lockfile |

OpenCode and Claude Code take a **whole-dir** symlink (`~/.agents/skills`, `~/.claude/skills` → `agents/skills/`). Codex needs no separate skill link: it scans the **USER** scope `$HOME/.agents/skills` and [follows symlinked skill folders](https://developers.openai.com/codex/skills#where-to-save-skills), so the existing `~/.agents/skills → agents/skills/` symlink already exposes **every** skill in this tree to Codex — hand-authored and CLI-managed alike. (`npx skills` may also copy CLI-managed skills into `~/.codex/skills`; `codex` is in `.skill-lock.json`'s `lastSelectedAgents`. That path is redundant for discovery and does not touch the hand-authored rule-skills.) A new hand-authored skill is therefore visible to all three tools the moment its `skills/<name>/SKILL.md` exists — no `install.conf.yaml` change.

The symlinks resolve live. Edits to `SHARED_AGENTS.md` or any file under `commands/` take effect for every linked tool the next time that tool reads them — no dotbot re-run needed unless the symlink itself is missing.

This file (`agents/AGENTS.md`) is **NOT** linked into any tool's global path. It is loaded only when an agent is editing files in this subdirectory of the repo.

## Where Things Go

| Task | Location |
|---|---|
| Add/change cross-tool agent rule | `SHARED_AGENTS.md` |
| Add/change a shared slash command or prompt | New `<name>.md` file in `commands/` (no wiring needed — the directory is already linked) |
| Add a tool-specific rule file (only OpenCode, only Codex, ...) | New file in this directory + new explicit `link:` in `../install.conf.yaml` |
| Add support for a new AI tool | New `link:` entries in `../install.conf.yaml` (rules and/or commands), then update `README.md` linkage table |
| Add a project-specific rule | The owning repo's `AGENTS.md`, NOT here |
| Add/update/remove a skill | Hand-author it under `skills/<name>/SKILL.md`, OR run `npx skills` / `glab skills install`. Before editing an existing skill, check its source — CLI-managed ones (in `.skill-lock.json` or the `glab` skill) are overwritten on the next CLI run. Never hand-edit `.skill-lock.json`. |

## Commands

Files in `commands/` are tool-agnostic markdown — each file is one slash command in OpenCode and one prompt in Codex. They are exposed at:

- OpenCode: `/<name>` (loaded from `~/.config/opencode/commands/<name>.md`)
- Codex: `/<name>` (loaded from `~/.codex/prompts/<name>.md`)

OpenCode-style frontmatter (`name`, `description`) is allowed and ignored by Codex. Keep command bodies tool-agnostic so the same file serves both surfaces; gate any tool-specific guidance inline rather than shipping divergent copies.

## Conventions

- **MUST** keep `SHARED_AGENTS.md` and files under `commands/` tool-agnostic. If guidance applies only to OpenCode (or only to Codex), put it in a separate file and link it individually.
- **MUST** add a matching row to `README.md`'s **Linkage** table whenever a new file or directory in this tree is linked from `../install.conf.yaml`. Linkage and documentation drift in lockstep.
- **MUST** keep this file, `README.md`, and `SHARED_AGENTS.md` mutually consistent. Per the repo's root `AGENTS.md`, agent workflow rule changes update every relevant `AGENTS.md` in the same commit.
- **MUST NOT** put machine-specific paths, secrets, or per-host details in any file here. These files are loaded as global agent context on every machine that runs `install.sh` / `install.ps1`.
- **MUST NOT** put project-specific rules or commands here. `SHARED_AGENTS.md` itself defers to project-level `AGENTS.md` when they conflict — keep that boundary clean.
- **MUST NOT** edit `~/.config/opencode/AGENTS.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/commands/*`, or `~/.codex/prompts/*` directly. Those are symlinks; edit the source files in `agents/` here.
- **SHOULD** hand-author a new skill (`skills/<name>/SKILL.md`) when the user **implicitly** requests functionality that doesn't yet exist — e.g. "I wish there were a skill for X", "can you always do Y this way", or any repeated workflow worth capturing. Don't wait for an explicit "install a skill" instruction. First verify no CLI-managed skill already covers it (check `.skill-lock.json` and the `glab` skill); if none does, create the hand-authored skill directly. It becomes visible to all three tools the moment `skills/<name>/SKILL.md` exists — no `install.conf.yaml` change.
- **SHOULD** use RFC 2119 keywords for directives, matching the existing style of `SHARED_AGENTS.md`.
- **MUST** write all tracked text in English (consistent with the rest of the repo).

## Anti-Patterns

| Forbidden | Why |
|---|---|
| Machine-specific paths or secrets in `SHARED_AGENTS.md` or `commands/*` | Loaded globally on every machine that links them. |
| Project-specific rules or commands in this directory | They belong in the owning repo's project-level `AGENTS.md` or `.opencode/commands/`, which already override shared rules/commands on conflict. |
| New rule file in this directory without a new `link:` in `../install.conf.yaml` | Untracked file with no consumer — clutter. Commands are the exception: `commands/` is already linked as a whole, so new files there need no extra wiring. |
| New `link:` in `../install.conf.yaml` without updating `README.md`'s **Linkage** table | Documentation drift. |
| Hand-editing `~/.config/opencode/AGENTS.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/commands/*`, or `~/.codex/prompts/*` | Those are symlinks into `agents/`; the change either fails or silently mutates the source through the link, depending on tool. Edit the source here. |
| Adding `home/.config/opencode/AGENTS.md` to make global OpenCode rules | `~/.config/opencode/AGENTS.md` is already an explicit symlink to `agents/SHARED_AGENTS.md`. A second source would conflict. Edit the shared file. |
| Adding `home/.config/opencode/commands/` | `~/.config/opencode/commands` is already an explicit symlink to `agents/commands`. A sibling source would conflict. Put new commands in `agents/commands/`. |
| Tool-specific divergent copy of the same command (e.g. one file for OpenCode, one for Codex) | Both surfaces share `commands/`. Keep one tool-agnostic file; branch inline if needed. |
| Hand-editing a CLI-managed `skills/` package (one in `.skill-lock.json` or the `glab` skill) without checking its source, or hand-editing `.skill-lock.json` | Those are CLI-owned; a manual edit is overwritten on the next `npx skills` / `glab skills install` run. Hand-authoring a *new* skill under `skills/<name>/SKILL.md` is fine — just verify it isn't already CLI-managed first. |
| Adding an `AGENTS.md` under `skills/` | `skills/` is linked into `~/.agents/skills` and `~/.claude/skills`, so a file there could be injected into every agent run. Put repo guidance in this file (`agents/AGENTS.md`), a sibling of `skills/`. |

See [`README.md`](./README.md) for the human-facing description and [`../AGENTS.md`](../AGENTS.md) for the repo-wide contract.
