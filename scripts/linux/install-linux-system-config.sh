#!/usr/bin/env bash
# scripts/linux/install-linux-system-config.sh
#
# Installs root-owned config from system/linux/etc/**/* into /etc/* using
# `sudo install -D -m <mode>`, then configures firewalld for Tailscale
# and VMware. Called from a `shell:` step in ../../install.linux.yaml
# (dotbot has no sudo / root mode, see AGENTS.md).
#
# Single-platform (Linux only) by design — no .ps1 counterpart per the
# script-parity exception in AGENTS.md.
#
# Re-runnable: `install -D` is idempotent, and every firewalld change is
# gated on a `--query-*` probe before mutating.
#
# Skip behaviour: when not running as root, stdin is not a TTY, and sudo
# has no cached credentials, the script exits 0 immediately. Dotbot
# invokes this from a non-interactive shell step during bootstrap; in
# that context an uncached sudo would hang or fail. Skipping cleanly
# keeps the rest of the dotbot run going. Re-run the script manually
# (`bash scripts/linux/install-linux-system-config.sh`) afterwards.
#
# Most files install at mode 0644. Exceptions: etc/sudoers.d/* installs at
# 0440 (sudo refuses group/world-readable drop-ins) and only on virtual
# machines, gated on `systemd-detect-virt --vm`; ThinkPad-specific
# thinkpad_acpi config installs only when `dmidecode -t system` reports a
# ThinkPad. Sudoers drop-ins are also syntax-checked with `visudo -c -f`
# before install — a broken drop-in can break sudo globally on the host.
#
# firewalld setup covers three things: (1) IPv4 masquerade on the default
# zone, required for the Tailscale exit-node and VMware NAT egress paths
# to source-NAT traffic out the host's primary interface (which lives in
# the default zone on Fedora Workstation); (2) binding tailscale0 to the
# `trusted` zone, per Tailscale's recommendation for firewalld hosts; and
# (3) opening UDP 41641 (WireGuard) + UDP 3478 (STUN) on the `public`
# zone so direct peer connections work behind a host firewall. The
# masquerade path rides on top of the IPv4/IPv6 forwarding enabled by
# etc/sysctl.d/99-tailscale.conf, which this script installs in the same
# run. The whole firewalld block is a no-op on hosts where firewalld is
# not the active backend.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_ROOT="$REPO_ROOT/system/linux"

# Use sudo only when not already root (e.g. when invoked inside chroot/container).
if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)

  # Skip cleanly when we'd need to prompt for a password but can't.
  # `[[ -t 0 ]]` is true only when stdin is a TTY; dotbot's `shell:`
  # steps connect stdin so this is true under `./install.sh` but false
  # under agent/CI runs. `sudo -n true` succeeds when sudo has cached
  # credentials (recent `sudo` invocation) or when the user has
  # password-less sudo configured — in either case we can proceed
  # without prompting. Only when both fail do we give up.
  if [[ ! -t 0 ]] && ! sudo -n true 2>/dev/null; then
    printf 'install-linux-system-config.sh: skipped (non-interactive shell, no cached sudo credentials).\n'
    printf '  Re-run manually:\n'
    printf '    bash %s/scripts/linux/install-linux-system-config.sh\n' "$REPO_ROOT"
    exit 0
  fi
fi

# Discover files at runtime so adding system/linux/etc/... config does not
# require editing this script (unless it needs a non-default mode or a
# platform/host gate — currently only sudoers.d/* qualifies).
shopt -s globstar nullglob

thinkpad_system=false
if command -v dmidecode >/dev/null 2>&1; then
  if "${SUDO[@]}" dmidecode -t system 2>/dev/null | grep -qi 'ThinkPad'; then
    thinkpad_system=true
  fi
else
  printf '  -- ThinkPad detection: skipped (dmidecode not installed)\n'
fi

count=0
skipped=0
for src in "$SRC_ROOT"/etc/**; do
  [[ -f "$src" ]] || continue

  rel="${src#"$SRC_ROOT"/}"
  dst="/$rel"

  # Per-path overrides. Defaults: mode 0644, install unconditionally.
  mode=644
  install_this=true
  skip_reason=

  case "$rel" in
    etc/modprobe.d/thinkpad_acpi.conf|etc/modules-load.d/thinkpad_acpi.conf)
      if [[ "$thinkpad_system" != true ]]; then
        install_this=false
        skip_reason='not a ThinkPad system'
      fi
      ;;
    etc/sudoers.d/*)
      # sudoers(5): drop-ins must be mode 0440 (sudo ignores
      # group/world-writable files) and the filename must not contain '.'
      # or end in '~'. We also gate these on `systemd-detect-virt --vm`
      # so the rule only lands on virtual machines, never on bare metal.
      mode=440
      if ! systemd-detect-virt --vm --quiet 2>/dev/null; then
        install_this=false
        skip_reason='not a VM'
      fi
      # Validate syntax unconditionally (even when we won't install on
      # this host) so contributors catch broken drop-ins on bare-metal
      # dev machines before they hit a VM.
      if ! visudo -c -f "$src" >/dev/null; then
        printf '  !! %s: visudo syntax check failed; aborting\n' "$dst" >&2
        exit 1
      fi
      ;;
  esac

  if [[ "$install_this" != true ]]; then
    printf '  -- %s (skipped: %s)\n' "$dst" "$skip_reason"
    skipped=$((skipped + 1))
    continue
  fi

  printf '  -> %s (mode %s)\n' "$dst" "$mode"
  "${SUDO[@]}" install -D -m "$mode" "$src" "$dst"
  count=$((count + 1))
done

printf 'install-linux-system-config.sh: %d installed, %d skipped\n' "$count" "$skipped"

if [[ "$thinkpad_system" == true ]]; then
  printf '  -> modprobe thinkpad_acpi\n'
  "${SUDO[@]}" modprobe thinkpad_acpi
else
  printf '  -- thinkpad_acpi: skipped (not a ThinkPad system)\n'
fi

# /etc/ paths that this script previously installed but no longer ships
# in system/linux/etc/. Listed explicitly so every machine — including
# ones that pull a committed deletion — removes the orphan on the next
# bootstrap run. `rm -f` is idempotent, so leaving entries here for a
# release cycle or two after the deletion is safe (no-op once gone).
#
# When deleting a tracked file from system/linux/etc/, add its absolute
# /etc path to this list in the same commit. Re-deriving the list from
# git history is intentionally not done (`git status` only sees local
# uncommitted changes; `git log --diff-filter=D` would catch committed
# deletions but has no idempotency story and would re-attempt removal
# forever). An explicit manifest is the simplest mechanism that works
# across all clones.
REMOVED_ETC_PATHS=(
  /etc/NetworkManager/conf.d/80-lo.conf
  /etc/NetworkManager/conf.d/90-unmanaged-vmware.conf
  /etc/NetworkManager/conf.d/91-tailscale.conf
  /etc/NetworkManager/conf.d/92-docker.conf
  /etc/NetworkManager/conf.d/93-veth.conf
  /etc/modprobe.d/audio-hda-no-powersave.conf
  /etc/systemd/system/docker-prune.service
  /etc/systemd/system/docker-prune.timer
)

removed_listed=0
for dst in "${REMOVED_ETC_PATHS[@]}"; do
  if [[ -e "$dst" || -L "$dst" ]]; then
    printf '  -> removing %s (listed in REMOVED_ETC_PATHS)\n' "$dst"
    "${SUDO[@]}" rm -f "$dst"
    removed_listed=$((removed_listed + 1))
  fi
done
if [[ ${#REMOVED_ETC_PATHS[@]} -eq 0 ]]; then
  printf '  -- REMOVED_ETC_PATHS: empty (nothing to clean)\n'
elif [[ "$removed_listed" -eq 0 ]]; then
  printf '  -- REMOVED_ETC_PATHS: %d entries, all already absent\n' "${#REMOVED_ETC_PATHS[@]}"
else
  printf '  -- REMOVED_ETC_PATHS: cleaned %d of %d listed path(s)\n' "$removed_listed" "${#REMOVED_ETC_PATHS[@]}"
fi

# Reload systemd when system/linux/etc/systemd/system/ ships any unit
# files so systemd notices the newly-installed units. Harmless no-op when
# the directory exists but ships no units.
if [[ -d "$SRC_ROOT/etc/systemd/system" ]]; then
  "${SUDO[@]}" systemctl daemon-reload
fi

# Enable lingering for the invoking user so their `systemd --user` units
# (e.g. rootless podman socket + prune timer) keep running without an
# active login session and start at boot. Uses the real invoking user, not
# root, when the script runs under sudo. Guarded so it never aborts the run.
loginctl enable-linger "${SUDO_USER:-$USER}" 2>/dev/null || true

# Mask the rootful podman API socket — blocks the system-level rootful API only, not sudo podman (which is daemonless)
if command -v systemctl >/dev/null 2>&1; then
  "${SUDO[@]}" systemctl mask podman.socket podman.service 2>/dev/null || true
fi

# Disable zram swap. Fedora's zram-generator-defaults instantiates the
# systemd-zram-setup@.service template to create a zram-backed swap device
# (zram0) at boot. Masking the template disables every instance, so the
# generator's swap setup never runs again. Also turn off any currently-active
# /dev/zram* swap (swapoff, then `zramctl --reset` to free the device) so the
# running system matches the next boot. Every step is best-effort and guarded:
# hosts without zram-generator, without an active zram device, or where swapoff
# can't free pages under memory pressure must not abort the bootstrap run.
if command -v systemctl >/dev/null 2>&1; then
  printf '  -> masking systemd-zram-setup@.service (disable zram swap)\n'
  "${SUDO[@]}" systemctl mask systemd-zram-setup@.service 2>/dev/null || true
fi
for zdev in /dev/zram*; do
  [[ -b "$zdev" ]] || continue
  printf '  -> swapoff %s\n' "$zdev"
  "${SUDO[@]}" swapoff "$zdev" 2>/dev/null || true
  if command -v zramctl >/dev/null 2>&1; then
    "${SUDO[@]}" zramctl --reset "$zdev" 2>/dev/null || true
  fi
done

# Reload udev rules so freshly-installed rules under /etc/udev/rules.d/
# (e.g. logitech-receiver.rules, 99-veth-no-ipv6.rules from
# system/linux/etc/udev/rules.d/) take effect without a reboot.
# `udevadm control --reload` re-reads the rules database; it does not
# retrigger events for existing devices (`udevadm trigger` would, and
# is intentionally omitted to avoid disrupting connected hardware on
# every bootstrap run).
if [[ -d "$SRC_ROOT/etc/udev/rules.d" ]]; then
  printf '  -> udevadm control --reload\n'
  "${SUDO[@]}" udevadm control --reload
fi

# Apply sysctl settings so freshly-installed drop-ins under
# /etc/sysctl.d/ (e.g. 99-tailscale.conf, 99-disable-ipv6-containers.conf
# from system/linux/etc/sysctl.d/) take effect without a reboot.
# `sysctl --system` re-reads /etc/sysctl.conf and every conf.d/ drop-in
# in the documented load order (see sysctl.d(5)), which is the same path
# systemd-sysctl.service runs at boot — so runtime state matches what a
# reboot would produce.
if [[ -d "$SRC_ROOT/etc/sysctl.d" ]]; then
  printf '  -> sysctl --system\n'
  "${SUDO[@]}" sysctl --system >/dev/null
fi

# Configure firewalld for Tailscale and VMware:
#
#   1. Masquerade on the default zone — required for the Tailscale
#      exit-node and VMware NAT egress paths (see header comment) to
#      source-NAT out the host's primary interface. Scope is the default
#      zone (`FedoraWorkstation` on Fedora Workstation), which by default
#      binds the host's primary network interfaces.
#
#   2. Bind `tailscale0` to the `trusted` zone — Tailscale's own
#      recommendation for hosts running firewalld. The trusted zone
#      accepts all traffic by default, which is what we want for the
#      mesh interface (peer ACLs are enforced at the Tailscale layer,
#      not the host firewall).
#      https://tailscale.com/kb/1077/secure-server-linux/
#
#   3. Open UDP 41641 (Tailscale's WireGuard listener) and UDP 3478
#      (STUN, used for NAT traversal) on the `public` zone so direct
#      peer connections work when the host sits behind a firewall.
#      https://tailscale.com/kb/1082/firewall-ports/
#
# Gate: `firewall-cmd --state` is firewalld's own liveness probe
# (https://firewalld.org/documentation/howto/get-firewalld-state.html).
# It returns 0 when the daemon is running and non-zero when firewalld is
# masked, missing, or replaced by a different backend (raw nftables,
# iptables-services). In every non-running case all firewalld steps are
# skipped — we don't program a backend that isn't there.
#
# Idempotency: every change is gated on a `--query-*` probe so we only
# mutate when something would change. A single `--reload` at the end
# applies all permanent changes to the runtime without restarting
# firewalld (https://firewalld.org/documentation/configuration/runtime-versus-permanent.html).
if "${SUDO[@]}" firewall-cmd --state >/dev/null 2>&1; then
  fw_changed=0

  if "${SUDO[@]}" firewall-cmd --permanent --query-masquerade >/dev/null 2>&1; then
    printf '  -- firewalld masquerade: already enabled (default zone)\n'
  else
    printf '  -> firewalld masquerade: enabling on default zone\n'
    "${SUDO[@]}" firewall-cmd --permanent --add-masquerade >/dev/null
    fw_changed=1
  fi

  if "${SUDO[@]}" firewall-cmd --permanent --zone=trusted --query-interface=tailscale0 >/dev/null 2>&1; then
    printf '  -- firewalld: tailscale0 already bound to trusted zone\n'
  else
    printf '  -> firewalld: binding tailscale0 to trusted zone\n'
    "${SUDO[@]}" firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 >/dev/null
    fw_changed=1
  fi

  for port in 41641/udp 3478/udp; do
    if "${SUDO[@]}" firewall-cmd --permanent --zone=public --query-port="$port" >/dev/null 2>&1; then
      printf '  -- firewalld: public/%s already open\n' "$port"
    else
      printf '  -> firewalld: opening public/%s\n' "$port"
      "${SUDO[@]}" firewall-cmd --permanent --zone=public --add-port="$port" >/dev/null
      fw_changed=1
    fi
  done

  if [[ "$fw_changed" -eq 1 ]]; then
    printf '  -> firewall-cmd --reload\n'
    "${SUDO[@]}" firewall-cmd --reload >/dev/null
  fi
else
  printf '  -- firewalld: skipped (firewalld not running)\n'
fi

# Remove dangling symlinks under /etc/NetworkManager/conf.d/. A drop-in
# installed by another tool as a symlink into a store/cache path becomes a
# broken link once that target is removed; NetworkManager then logs
# warnings on every reload and `ls -l` flags it red. We only delete
# symlinks whose targets are missing — regular files and live symlinks are
# left untouched, so this can't accidentally remove a drop-in placed by
# another tool.
if [[ -d /etc/NetworkManager/conf.d ]]; then
  stale=0
  for link in /etc/NetworkManager/conf.d/*; do
    [[ -L "$link" && ! -e "$link" ]] || continue
    printf '  -> removing stale symlink: %s\n' "$link"
    "${SUDO[@]}" rm -f "$link"
    stale=$((stale + 1))
  done
  if [[ "$stale" -eq 0 ]]; then
    printf '  -- NetworkManager conf.d: no stale symlinks\n'
  else
    printf '  -- NetworkManager conf.d: removed %d stale symlink(s)\n' "$stale"
  fi
fi

# Reload NetworkManager so any freshly-installed drop-ins under
# /etc/NetworkManager/conf.d/ (e.g. the unmanaged-devices rules from
# system/linux/etc/NetworkManager/conf.d/) take effect without a reboot.
# `systemctl reload` triggers NetworkManager's SIGHUP handler, which
# re-reads NetworkManager.conf and every conf.d/ drop-in without
# disrupting active connections (unlike `restart`, which would).
#
# Gate: `systemctl is-active --quiet NetworkManager` returns 0 only when
# the unit exists and is currently running, covering both "service
# present" and "service running" in a single check. Hosts without
# NetworkManager (systemd-networkd, netctl, no network stack at all)
# skip cleanly.
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
  printf '  -> systemctl reload NetworkManager\n'
  "${SUDO[@]}" systemctl reload NetworkManager
else
  printf '  -- NetworkManager reload: skipped (service not running)\n'
fi
