# home/

Files in this directory install into `$HOME` via dotbot links or helper scripts. Most paths mirror `$HOME` exactly (`home/.config/git/config` → `~/.config/git/config`); `home/.secrets/*.1password` files are templates rendered by the 1Password helper rather than linked directly.

| Source in repo | Installed target / behavior |
|---|---|
| `home/.z*` | `~/.z*` on Linux and macOS |
| `home/.config/git/config` | `~/.config/git/config` |
| `home/.gitconfig.d/<os>.gitconfig` | `~/.gitconfig.d/<os>.gitconfig` from the matching OS yaml |
| `home/.config/opencode/*.{json,jsonc}` | `~/.config/opencode/` (only top-level OpenCode JSON config; subdirs handled separately) |
| `home/.config/Code/User/*.json` | VS Code user settings/keybindings at the platform-specific Code user path |
| `home/.config/VSCodium/User/*.json` | VSCodium user settings/keybindings at the platform-specific VSCodium user path (Linux `~/.config/VSCodium/User/`, macOS `~/Library/Application Support/VSCodium/User/`, Windows `~/AppData/Roaming/VSCodium/User/`); only the tracked `*.json` files are linked, not the whole `User/` dir |
| `home/.config/environment.d/` | `~/.config/environment.d/` (glob-linked + pruned by `install.linux.yaml`; includes `65-containers.conf`, which sets `DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock` so Docker-API clients route through the rootless user `podman.socket` after the Docker→Podman migration, plus `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true` (.NET) and `TESTCONTAINERS_RYUK_PRIVILEGED=true` (Node) so Testcontainers' Ryuk reaper runs privileged/unconfined and isn't blocked by SELinux from writing the `user_tmp_t`-labeled `podman.sock`) |
| `home/.config/fcitx5/`, `home/.config/containers/`, `home/.config/solaar/` | Linux-only XDG config via `install.linux.yaml` |
| `home/.config/wireplumber/wireplumber.conf.d/*.conf` | Linux-only WirePlumber 0.5 drop-ins via the `install.linux.yaml` XDG config glob, currently `51-disable-bt-autoswitch.conf` (sets `bluetooth.autoswitch-to-headset-profile = false` so Bluetooth headsets stay in stable A2DP and don't collapse into fragile HFP when an app opens the mic; the mic profile stays available, just not auto-selected) |
| `home/.config/zed/` | `~/.config/zed/` |
| `home/.gnupg/*.conf` | `~/.gnupg/*.conf` on Linux and macOS |
| `home/.ssh/config` | `~/.ssh/config` |
| `home/.npmrc`, `home/.yarnrc.yml` | Cross-platform package-manager hardening config |
| `home/.config/pnpm/config.yaml` | Linux package-manager hardening config via the XDG config glob |
| `home/.bunfig.toml` | Tracked Bun hardening config source; not linked by the current install yaml |
| `home/.local/bin/opencode*`, `home/.local/bin/code*` | CLI helpers under `~/.local/bin/` for the platforms that use them. `opencode`/`opencode.ps1` is a `mise exec` wrapper that resolves the latest anomalyco/opencode release version from its `latest.json` GitHub release asset via the `gh` CLI (`gh release download`, not raw `curl`), pins that version for the invocation, and falls back to the unpinned `github:anomalyco/opencode` backend when the manifest fetch fails (offline / GitHub down / `gh` unauthenticated). Requires `gh` on PATH (POSIX side also uses `jq`). `code`/`code.ps1` is the VS Codium shim (runs `codium`) that lets the `code` command keep working in non-interactive shells and editor-launching tools after the VS Code -> VS Codium migration |
| `home/.local/share/applications/*.desktop` | Linux desktop entries under `~/.local/share/applications/` |
| `home/.config/autostart/*.desktop` | Linux XDG autostart entries under `~/.config/autostart/` (linked via the `install.linux.yaml` `~/.config/**/*` glob; not used on macOS/Windows, which autostart via LaunchAgents / the Startup registry). Each is `NoDisplay=true` + `X-GNOME-Autostart-enabled=true` so it launches at login without showing in the app menu. Currently `kleopatra.desktop` (`kleopatra --daemon`, the GnuPG/Kleopatra crypto applet) and `steam.desktop` (`steam -silent`, Steam started minimized to tray) |
| `home/.local/bin/kde-color-picker` + `home/.local/share/applications/kde-color-picker.desktop` | Linux/KDE-only (Plasma Wayland) PowerToys-style screen color picker. The desktop entry's `X-KDE-Shortcuts=Meta+Shift+C` binds a global shortcut (same mechanism as `1password.desktop`/Spectacle) that runs the `kde-color-picker` script, which calls KWin's `org.kde.kwin.ColorPicker` D-Bus `pick`, copies the picked pixel to the clipboard as `#RRGGBB` via `wl-copy`, and shows a notification. Single-platform by design (no `.ps1`); deps `gdbus` (glib2), `wl-copy` (`wl-clipboard`, already in `install-packages.sh`) and `notify-send` (libnotify) ship with a Fedora KDE install. The `kde-color-picker` binary link lives in `install.linux.yaml`; the shortcut registers on next login when KGlobalAccel scans the desktop file |
| `home/.secrets/*.1password` | Rendered by `scripts/bootstrap/inject-1password-secrets.*` to `~/.secrets/<name>` |

## Post-migration: container registry auth

After the Docker→Podman migration, registry credentials this repo used to track for `ghcr.io`, `docker.io`, and `registry.jpi.app` no longer exist on disk. Re-establish them manually on each machine with `podman login <registry>`; podman stores the new credentials in `~/.config/containers/auth.json`, which is a machine-local file and is not tracked or managed by this repo.

## Conventions

- **Cross-platform files** are linked from [`../install.conf.yaml`](../install.conf.yaml), which also runs `mise install`.
- **OS-specific files** are linked from [`../install.linux.yaml`](../install.linux.yaml), [`../install.macos.yaml`](../install.macos.yaml), or [`../install.windows.yaml`](../install.windows.yaml).
- The location of the file inside `home/` does NOT determine which OS gets it — the `link:` block in the matching yaml does. You can place a Linux-only file under `home/.config/foo/` and only link it from `install.linux.yaml`.
- Use forward slashes in YAML paths even for Windows targets (e.g. `~/AppData/...`).
- Linux-only desktop, container, `environment.d`, editor, and SSH snippets live under their mirrored `home/` paths and are linked only from `install.linux.yaml`; that installer also prunes retired `environment.d` symlinks before relinking.
- The runtime skill tree is **not** under `home/` — it lives in [`../agents/skills`](../agents/skills) (with [`../agents/.skill-lock.json`](../agents/.skill-lock.json)), linked into `~/.agents/skills` and `~/.claude/skills`. See [`../agents/README.md`](../agents/README.md).
- `home/.config/opencode/` is linked with a narrow `*.{json,jsonc}` glob (top-level JSON config only). Do not place `AGENTS.md` or a `commands/` subdir inside it — `~/.config/opencode/AGENTS.md` is already an explicit symlink to [`../agents/SHARED_AGENTS.md`](../agents/SHARED_AGENTS.md) and `~/.config/opencode/commands` is an explicit symlink to [`../agents/commands`](../agents/commands) (both managed by [`../install.conf.yaml`](../install.conf.yaml)). Edit those sources under `agents/` to change cross-tool agent rules or slash commands.

## Don't put here

- Rendered secrets — keep only `*.1password` templates here. The generated `~/.secrets/*` files are local machine output and MUST NOT be committed.
- Generated files (caches, lock files for shells, etc.) — link the *config* that produces them, not the output.
- A `home/.agents/` skill tree — it moved to [`../agents/skills`](../agents/skills); don't reintroduce it here.
- `home/.config/opencode/AGENTS.md` — it would conflict with the explicit symlink that points `~/.config/opencode/AGENTS.md` at [`../agents/SHARED_AGENTS.md`](../agents/SHARED_AGENTS.md). Edit the shared file instead.
- `home/.config/opencode/commands/` — it would conflict with the explicit symlink that points `~/.config/opencode/commands` at [`../agents/commands`](../agents/commands). Put new slash commands in `agents/commands/` instead.

See [`../AGENTS.md`](../AGENTS.md) for the repo-wide contract.
