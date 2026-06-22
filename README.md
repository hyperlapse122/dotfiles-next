# dotfiles

Cross-platform dotfiles for **Fedora Linux · Windows · macOS**, kept in one repo and applied with [dotbot](https://github.com/anishathalye/dotbot) — invoked **ephemerally** through [mise](https://mise.jdx.dev/)-managed `uvx`, so dotbot itself is never installed on the machine.

You bring [`mise`](https://mise.jdx.dev/); the bootstrap brings the rest. One run symlinks every config into place, installs the mise toolchain, fetches fonts, builds the local Rust/TypeScript helpers, and — on Linux — lays down `/etc` drop-ins, firewall rules, and KDE Plasma preferences. Everything is idempotent: re-run after any `git pull`.

---

## Setup

Pick your OS. Each flow is: **install prerequisites → clone → bootstrap**. The only prerequisite you install by hand is `mise` (plus `git` to clone); mise supplies [`uv`](https://docs.astral.sh/uv/) for the ephemeral `uvx dotbot` run and the Node.js the bootstrap uses.

### Fedora Linux

1. **Install `git` and `mise`** (mise ships via its COPR):

   ```sh
   sudo dnf install -y git
   sudo dnf copr enable -y jdxcode/mise
   sudo dnf install -y mise
   ```

2. **Clone the repo:**

   ```sh
   git clone https://github.com/hyperlapse122/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

3. **(Optional) Set up TPM2 LUKS auto-unlock** — only relevant on a LUKS-encrypted install with a TPM2. It enrolls a TPM2 token (PCR 7) on every encrypted disk so it unlocks automatically at boot, prompting interactively for your existing passphrase (which keeps working as a fallback):

   ```sh
   ./scripts/linux/setup-luks-tpm2-unlock.sh --dry-run   # preview, changes nothing
   ./scripts/linux/setup-luks-tpm2-unlock.sh             # apply
   ```

4. **Install the Fedora package set:**

   ```sh
   ./scripts/linux/install-packages.sh
   ```

   This enables RPM Fusion, the keyd/mise COPRs, and third-party repos (1Password, VSCodium, Google Chrome, Tailscale, Proton VPN, VirtualBox), installs the rootless Podman ecosystem and the rest of the packages (plus Discord as a Flatpak from Flathub), builds the VirtualBox akmods, and enables `keyd` / `tailscaled` / `libvirtd`. **Reboot afterward** — on UEFI + Secure Boot it queues an akmods MOK import, so on the next boot the blue *MOK Manager* screen asks for the one-time password to enroll the signing key and load the freshly-built kernel module; new group memberships also take effect after a re-login/reboot.

5. **Link the dotfiles and install the toolchain:**

   ```sh
   ./install.sh
   ```

   `install.sh` auto-detects Linux, runs `mise install`, symlinks every config, builds the local Rust/TS helpers, installs fonts, and writes the root-owned `/etc` drop-ins + KDE Plasma settings (it prompts once for `sudo`). Run it in a real terminal — the `/etc` and KDE steps skip themselves when there is no TTY.

### Windows

1. **Install the prerequisites with winget**, then enable [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/developer-mode-features-and-debugging) (or run PowerShell as Administrator) so dotbot can create symlinks:

   ```powershell
   winget install --id Git.Git -e
   winget install --id Microsoft.PowerShell -e
   winget install --id jdx.mise -e
   ```

2. **Clone and bootstrap** from PowerShell 7 (`pwsh`):

   ```powershell
   git clone https://github.com/hyperlapse122/dotfiles.git $HOME\dotfiles
   cd $HOME\dotfiles
   pwsh.exe .\install.ps1
   ```

   `install.ps1` runs `mise install`, then links every config via the ephemeral `uvx dotbot` using `install.windows.yaml`.

### macOS

1. **Install `git` (Xcode Command Line Tools) and `mise`:**

   ```sh
   xcode-select --install        # git, curl, unzip
   curl https://mise.run | sh    # or: brew install mise
   ```

2. **Clone and bootstrap:**

   ```sh
   git clone https://github.com/hyperlapse122/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ./install.sh                  # auto-detects Darwin via `uname -s`
   ```

---

## What the bootstrap does

Run once per OS, `install.sh` / `install.ps1` invoke `mise exec uv@latest -- uvx dotbot` with the shared `install.conf.yaml` plus the matching `install.<os>.yaml`, which:

- **Installs the toolchain** — `mise install` provisions Node, Bun, Go, Python, Ruby, Rust, and CLIs (`gh`, `glab`, `ast-grep`, `shellcheck`, …) from the tracked `mise` config.
- **Links your dotfiles** — zsh (Prezto-based), git, SSH, GnuPG, editor settings (VS Code, VSCodium, Zed), and cross-tool AI agent rules / slash commands for OpenCode and Codex from a single source in [`agents/`](./agents/). Shared Codex settings are *merged* into `~/.codex/config.toml` (never clobbering machine-local per-project trust).
- **Builds local helpers** — Rust [`crates/`](./crates/) into `~/.local/bin` (e.g. the MX Master 4 haptic stack — Linux + macOS, autostarted via `systemd --user` / launchd) and the TypeScript [`packages/`](./packages/) Yarn workspace in place (OpenCode plugins auto-linked into `~/.config/opencode/plugins/`).
- **Installs fonts** user-wide (no admin) — Pretendard, Pretendard JP, JetBrains Mono, D2Coding, Nerd Font variants.
- **Renders secrets** — any tracked `*.1password` template is injected into `~/.secrets/` (no-op when there are none; needs an authenticated `op` session otherwise).
- **Linux desktop polish** — root-owned `/etc` drop-ins, firewalld rules for Tailscale & VMware, and KDE Plasma 6 font/touchpad/panel/KRunner preferences. Each step skips cleanly when its prerequisites are absent.

`mise`, the npm/pnpm/Yarn/Bun configs ship hardened: lifecycle scripts disabled, exact-version pinning, and a one-week dependency cooldown gate.

## Re-running

`./install.sh` and `.\install.ps1` are **idempotent** — dotbot creates missing parents, relinks existing symlinks, and forces repo-managed links over real files at managed targets (`force: true`, overwrite behavior — not `stow --adopt`); `mise install` refreshes tools; helper scripts skip or overwrite deterministic targets safely. One deliberate exception adopts in the other direction: before relinking, `agent-of-empires`' `config.toml` is copied back into the repo when the tool has replaced its managed symlink with a real file (its in-app config save does this), so a setting you changed in the app is captured rather than clobbered — review and commit the resulting repo change. Run them again after every `git pull`.

- `scripts/linux/install-packages.sh` and `scripts/linux/setup-luks-tpm2-unlock.sh` are **manual** (they need `sudo` / an interactive passphrase) and are not part of `install.sh`.
- The Linux `/etc` and KDE steps no-op without a TTY (so agent/CI runs don't hang on `sudo`); re-run [`scripts/linux/install-linux-system-config.sh`](./scripts/linux/install-linux-system-config.sh) and [`scripts/linux/config-kde.sh`](./scripts/linux/config-kde.sh) manually if they were skipped.
- Fonts download on first run into `~/.local/share/fonts` (Linux), `~/Library/Fonts` (macOS), or `%LOCALAPPDATA%\Microsoft\Windows\Fonts` (Windows). Refresh with [`scripts/bootstrap/install-fonts.{sh,ps1}`](./scripts/bootstrap/) and `--force` / `-Force`.

## Repo structure

| Path | Purpose |
|---|---|
| [`install.sh`](./install.sh) / [`install.ps1`](./install.ps1) | Bootstrap entrypoints (POSIX / PowerShell) |
| [`install.conf.yaml`](./install.conf.yaml) | Shared dotbot tasks, loaded on every OS |
| `install.<os>.yaml` | Per-OS dotbot links and `shell:` steps |
| [`home/`](./home/) | User-owned dotfiles, runtime skill tree, and `*.1password` templates that install under `$HOME` |
| [`system/`](./system/)`<os>/` | Root-owned config installed to absolute paths (e.g. `/etc/...`) via `sudo install -D` |
| [`scripts/`](./scripts/) | Bootstrap helpers plus manual auth / package / system setup, in `.sh` + `.ps1` pairs |
| [`crates/`](./crates/) | Rust crates `cargo install`'d into `~/.local/bin` during bootstrap (e.g. the MX Master 4 haptic daemon) |
| [`packages/`](./packages/) | Private `@h82/dotfiles` Yarn Berry monorepo of TS/JS libraries — built in place, never installed |
| [`agents/`](./agents/) | Cross-tool AI agent rules and slash commands linked into OpenCode & Codex |
| [`codex/`](./codex/) | Tracked shared OpenAI Codex config (incl. MX Master 4 haptic `[[hooks.*]]`) merged into `~/.codex/config.toml` |
| [`.github/`](./.github/) | CI for the `packages/` workspace (build/typecheck/test, lint), the `crates/` Rust workspace (`rust.yml`: cargo fmt/clippy/check/test), and the rest of the repo (`tooling.yml`: shellcheck, PSScriptAnalyzer, actionlint, dotbot link guard, Codex config tests), a Socket supply-chain scan (`socket.yml`), plus the hourly opencode-plugin bump workflow |

[`AGENTS.md`](./AGENTS.md) is the authoritative source for repo conventions — read it before adding files. Every tracked top-level directory carries its own `README.md`.
