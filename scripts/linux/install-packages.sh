#!/usr/bin/env bash

set -euo pipefail

# Use sudo only when not already root (matches install-linux-system-config.sh).
# Throw early if neither root nor sudo is available — dnf/systemctl need it.
if [[ "${EUID}" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  printf 'install-packages.sh: requires root or sudo for package installation.\n' >&2
  exit 1
fi

configure-kr-mirrorlists() {
  local chassis_type=''
  if [[ -r /sys/class/dmi/id/chassis_type ]]; then
    chassis_type="$(</sys/class/dmi/id/chassis_type)"
  fi

  case "${chassis_type}" in
    3|4|5|6|7|13|15|16|35) ;;
    *)
      printf 'install-packages.sh: chassis type "%s" is not desktop-class; leaving Fedora mirrorlists unchanged.\n' "${chassis_type:-unknown}"
      return 0
      ;;
  esac

  local -a repo_options=(
    "fedora.metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch&country=KR"
    'fedora.mirrorlist='
    "updates.metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f\$releasever&arch=\$basearch&country=KR"
    'updates.mirrorlist='
    "updates-testing.metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-testing-f\$releasever&arch=\$basearch&country=KR"
    'updates-testing.mirrorlist='
  )

  "${SUDO[@]}" dnf config-manager setopt "${repo_options[@]}"
}

install-fedora-packages() {
  # Install repository manager only when missing — dnf would otherwise hit the
  # network just to discover the package is already installed.
  if ! rpm -q fedora-workstation-repositories >/dev/null 2>&1; then
    "${SUDO[@]}" dnf install fedora-workstation-repositories -y
  fi

  configure-kr-mirrorlists

  # Enable third party repositories
  "${SUDO[@]}" fedora-third-party enable

  # Enable keyd COPR
  "${SUDO[@]}" dnf copr enable alternateved/keyd -y
  "${SUDO[@]}" dnf copr enable jdxcode/mise -y

  # Install RPM Fusion (free + nonfree) — skip the network install when both
  # release packages are already present. fedora-cisco-openh264 is enabled
  # unconditionally (setopt is idempotent) so steam deps resolve.
  if ! rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then
    "${SUDO[@]}" dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
  fi
  "${SUDO[@]}" dnf config-manager setopt fedora-cisco-openh264.enabled=1

  # Add the NVIDIA CUDA repository only on hosts with an NVIDIA GPU; the driver
  # packages themselves are installed later via the main packages array (also
  # GPU-gated). Scan /sys/bus/pci/devices/*/vendor for NVIDIA's PCI vendor id
  # (0x10de) rather than shelling out to lspci — pciutils is not guaranteed
  # installed this early, and the sysfs vendor files are always present.
  if grep -qx '0x10de' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
    "${SUDO[@]}" dnf config-manager addrepo --from-repofile https://developer.download.nvidia.com/compute/cuda/repos/fedora"$(rpm -E %fedora)"/x86_64/cuda-fedora"$(rpm -E %fedora)".repo --overwrite
  else
    printf 'install-packages.sh: no NVIDIA GPU detected; skipping CUDA repo and drivers.\n'
  fi

  # Install 1Password repository. Quoted heredoc keeps $basearch literal so
  # dnf substitutes it at install time (not at script-eval time).
  "${SUDO[@]}" rpm --import https://downloads.1password.com/linux/keys/1password.asc
  "${SUDO[@]}" tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey="https://downloads.1password.com/linux/keys/1password.asc"
EOF

  # Install VSCodium repository (written to vscode.repo so it overwrites any
  # prior Microsoft VS Code repo file in place)
  "${SUDO[@]}" rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
  "${SUDO[@]}" tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF

  # Install Google Chrome repository. Overwrites the disabled google-chrome.repo
  # that fedora-workstation-repositories ships, pinning Google's own published
  # definition. baseurl is hardcoded to x86_64 (not $basearch) because Google
  # publishes no other Linux arch — aarch64/i386 would 404. gpgcheck only, no
  # repo_gpgcheck: Google's repo metadata is not signed for it (omitting it
  # matches Google's official definition; adding it would break makecache).
  "${SUDO[@]}" rpm --import https://dl.google.com/linux/linux_signing_key.pub
  "${SUDO[@]}" tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

  # Add Tailscale repository
  "${SUDO[@]}" dnf config-manager addrepo --from-repofile https://pkgs.tailscale.com/stable/fedora/tailscale.repo --overwrite

  # Add Proton VPN repository. The GUI package is still named
  # proton-vpn-gnome-desktop upstream; Proton documents limited support for
  # other Fedora desktop environments such as KDE.
  if ! rpm -q protonvpn-stable-release >/dev/null 2>&1; then
    "${SUDO[@]}" dnf install -y \
      "https://repo.protonvpn.com/fedora-$(rpm -E %fedora)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.4-1.noarch.rpm"
  fi

  # Update package metadata before installing anything, since we've added new repos and some of them (e.g. 1Password) are needed to resolve dependencies of packages
  "${SUDO[@]}" dnf makecache

  "${SUDO[@]}" dnf install -y clang21-libs kernel kernel-devel kernel-devel-matched kernel-headers

  # Install packages, grouped by purpose and alphabetised within each group.
  # steam are bare-metal-only — systemd-detect-virt exits 0 when
  # virtualization is detected, 1 on bare metal.
  "${SUDO[@]}" dnf group install development-tools virtualization "c-development" -y
  local -a packages=(
    # Build tooling
    clang
    gcc-c++
    pkg-config
    # libudev headers (libudev.pc) for the mxm4-haptic crate's hidapi
    # linux-static-hidraw backend; provided by systemd-devel on Fedora.
    systemd-devel

    # CLI utilities
    btop
    fd-find
    gh
    # kdotool: Wayland xdotool clone that queries KWin's active window via KWin
    # scripting (no X11 dependency). Installed to support focus-gating the
    # .zshrc long-command haptic hook — so a finished long command can stay
    # silent when the focused window is the terminal you are already watching.
    kdotool
    nvtop
    ripgrep
    xxd
    yp-tools

    # Korean input method
    fcitx5
    fcitx5-hangul

    # Keyboard remapper
    keyd

    # Language toolchains + version manager
    dotnet-sdk-10.0
    dotnet-sdk-8.0
    mise

    # Ruby build dependencies (consumed by mise's ruby-build).
    # The runtime libs libffi/libyaml are pulled in transitively.
    libffi-devel
    libyaml-devel

    # Hardware sensors / fan control
    lm_sensors

    # Logitech device manager
    solaar
    solaar-udev

    # Password manager
    1password
    1password-cli

    # Editor
    codium

    # Web browser
    google-chrome-stable

    # Container runtime (rootless Podman + tooling)
    podman
    podman-docker
    podman-compose
    buildah
    containers-common
    passt
    fuse-overlayfs
    slirp4netns

    # Screen recording / streaming / video editing
    kdenlive
    obs-studio

    # Mesh networking / VPN
    proton-vpn-gnome-desktop
    tailscale
    wl-clipboard

    # Virtualization
    akmod-VirtualBox
    akmods
    # Dynamic Kernel Module Support — builds/signs out-of-tree modules (e.g.
    # the NVIDIA dkms driver); its MOK signing key lives at /var/lib/dkms/mok.pub
    # and is enrolled by enable-services below.
    dkms
    # refs-fuse (unsound/refsprogs) build deps for read-only ReFS / Windows
    # Dev Drive access on vhdx mounts; autotools come from development-tools.
    fuse3
    fuse3-devel
    guestfs-tools
    kernel-devel
    libguestfs
    ntfs-3g
    qemu-img
    systemd-container
    virtualbox

    # Tauri
    curl
    file
    libappindicator-gtk3-devel
    librsvg2-devel
    libxdo-devel
    openssl-devel
    webkit2gtk4.1-devel
    wget
  )
  if ! systemd-detect-virt --quiet; then
    # Bare-metal-only
    packages+=(
      steam
    )
  fi
  # NVIDIA-only — same PCI vendor (0x10de) gate as the CUDA repo above; pulled
  # from the CUDA repo added earlier in this function.
  if grep -qx '0x10de' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
    packages+=(
      cuda-drivers
      cuda-toolkit-13-3
      kmod-nvidia-latest-dkms
      nvidia-driver
    )
  fi
  "${SUDO[@]}" dnf install -y "${packages[@]}"
}

install-dotnet-tools() {
  dotnet tool install -g git-credential-manager
  dotnet tool install -g powershell
}

build-akmods() {
  # If vboxdrv loads cleanly the prebuilt akmod already matches the running
  # kernel, so a plain akmods run suffices. If modprobe fails (stale or
  # missing module after a kernel bump), force a full rebuild instead.
  if "${SUDO[@]}" modprobe vboxdrv 2>/dev/null; then
    "${SUDO[@]}" akmods
  else
    "${SUDO[@]}" akmods --force --rebuild
  fi
}

install-virtualbox-extension-pack() {
  if ! command -v VBoxManage >/dev/null 2>&1; then
    printf 'install-packages.sh: VBoxManage not installed; skipping extension pack.\n'
    return 0
  fi

  # VBoxManage --version emits e.g. "7.2.8_RPMFUSIONr173730" (RPM Fusion build)
  # or "7.2.8r166737" (upstream). Strip from the first non-version character
  # to recover "7.2.8", which is what download.virtualbox.org publishes the
  # matching extpack under.
  local vbox_version installed_version pack_file base_url
  vbox_version="$(VBoxManage --version 2>/dev/null | awk -F_ '/^[0-9]+\.[0-9]+\.[0-9]+_/ {print $1}')"
  if [[ -z "${vbox_version}" ]]; then
    printf 'install-packages.sh: could not parse VirtualBox version; skipping extension pack.\n' >&2
    return 1
  fi

  # Skip if the installed extpack already matches the running VirtualBox.
  installed_version="$(VBoxManage list extpacks 2>/dev/null \
    | awk '/^Pack no\. 0:/{found=1} found && /^Version:/{print $2; exit}')"
  if [[ "${installed_version}" == "${vbox_version}" ]]; then
    printf 'install-packages.sh: VirtualBox Extension Pack %s already installed; skipping.\n' "${vbox_version}"
    return 0
  fi

  pack_file="Oracle_VirtualBox_Extension_Pack-${vbox_version}.vbox-extpack"
  base_url="https://download.virtualbox.org/virtualbox/${vbox_version}"

  # Subshell scopes the EXIT trap so the tmpdir is cleaned up whether the
  # work succeeds or fails under set -e, without leaking a RETURN trap
  # into subsequent functions.
  (
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT

    curl -fsSL -o "${tmpdir}/${pack_file}" "${base_url}/${pack_file}"
    curl -fsSL -o "${tmpdir}/SHA256SUMS"   "${base_url}/SHA256SUMS"

    # SHA256SUMS lines are "<sha256> *<filename>". Pull the line for our exact
    # filename; refuse to proceed if it is missing (sha256sum -c on empty
    # stdin exits 0, which would silently skip verification).
    cd "${tmpdir}"
    expected="$(awk -v f="*${pack_file}" '$2 == f' SHA256SUMS)"
    if [[ -z "${expected}" ]]; then
      printf 'install-packages.sh: %s missing from upstream SHA256SUMS; aborting.\n' "${pack_file}" >&2
      exit 1
    fi
    printf '%s\n' "${expected}" | sha256sum -c -

    # VBoxManage accepts --accept-license=<sha256 of bundled
    # ExtPack-license.txt> for non-interactive install. Compute it from the
    # verified archive so a future license change is picked up automatically.
    license_hash="$(tar -xOzf "${pack_file}" ./ExtPack-license.txt | sha256sum | awk '{print $1}')"

    "${SUDO[@]}" VBoxManage extpack install --replace \
      --accept-license="${license_hash}" "${tmpdir}/${pack_file}"
  )

  # A user-owned VBoxSVC started before this install caches "no extpacks"
  # in-process; without restarting it the user keeps seeing the pre-install
  # list until next login. See https://www.virtualbox.org/ticket/17034.
  local target_user="${SUDO_USER:-$USER}"
  if [[ -n "${target_user}" && "${target_user}" != "root" ]]; then
    pkill -u "${target_user}" -x VBoxSVC 2>/dev/null || true
  fi
}

enable-services() {
  "${SUDO[@]}" systemctl enable --now keyd
  "${SUDO[@]}" systemctl enable --now tailscaled
  "${SUDO[@]}" systemctl enable --now libvirtd.service

  # Enable the NVIDIA persistence daemon only on NVIDIA hosts, matching the
  # CUDA driver install gate in install-fedora-packages (PCI vendor 0x10de).
  if grep -qx '0x10de' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
    "${SUDO[@]}" systemctl enable nvidia-persistenced
  fi

  # Set up time synchronization
  "${SUDO[@]}" systemctl unmask systemd-timesyncd
  "${SUDO[@]}" systemctl enable --now systemd-timesyncd
  
  # this may fail until the user reboots to load the vboxdrv kernel module, but enable it anyway so it starts on next boot
  "${SUDO[@]}" systemctl enable vboxdrv

  # Enabling akmods.service ensures kernel modules are automatically signed and loaded
  "${SUDO[@]}" systemctl enable --now akmods.service

  # Import the MOK signing keys for out-of-tree kernel modules: every akmods
  # key under /etc/pki/akmods/certs/ (currently virtualbox) plus the dkms key
  # at /var/lib/dkms/mok.pub (NVIDIA dkms driver). Skipped entirely unless
  # booted via UEFI with Secure Boot enabled — otherwise unsigned modules load
  # fine and `mokutil --import` would queue a pointless MOK Manager prompt on
  # next boot.
  #
  # /etc/pki/akmods/certs/ is mode 0750 root:akmods, so every read of the
  # directory and its contents (listing, existence check, mokutil
  # --test-key, openssl fingerprint) goes through sudo — a normal user
  # cannot see files in there even though only --import strictly needs
  # root. The dkms key is read through sudo for the same uniformity. Both are
  # DER-encoded so a single `openssl x509 -inform DER` covers them. Per-cert
  # enrollment check uses `mokutil --test-key` (which confusingly exits 1 when
  # the key IS enrolled, so we grep its stdout for "is already enrolled") and a
  # pending-enrollment check against `mokutil --list-new` by SHA1 fingerprint so
  # re-runs between import and reboot don't re-prompt for the one-time password
  # and replace the pending request. Both key sources are collected into one
  # array and the approved-to-import keys are batched into a single
  # `mokutil --import key1 key2 ...` call so the user enters the one-time
  # password once for all of them.
  if [[ ! -d /sys/firmware/efi ]]; then
    printf 'install-packages.sh: not booted via UEFI; skipping MOK import.\n'
  elif ! mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
    printf 'install-packages.sh: Secure Boot disabled; skipping MOK import.\n'
  else
    local -a certs=() to_import=()
    local cert fp
    if "${SUDO[@]}" test -d /etc/pki/akmods/certs; then
      readarray -t certs < <("${SUDO[@]}" find /etc/pki/akmods/certs -maxdepth 1 -type f -name '*.der' -print | sort)
    fi
    if "${SUDO[@]}" test -f /var/lib/dkms/mok.pub; then
      certs+=(/var/lib/dkms/mok.pub)
    fi
    if [[ ${#certs[@]} -eq 0 ]]; then
      printf 'install-packages.sh: no akmods/dkms MOK keys found; skipping MOK import.\n'
    else
      for cert in "${certs[@]}"; do
        if "${SUDO[@]}" mokutil --test-key "${cert}" 2>/dev/null | grep -q 'is already enrolled'; then
          printf 'install-packages.sh: %s already enrolled; skipping.\n' "${cert}"
          continue
        fi
        fp="$("${SUDO[@]}" openssl x509 -in "${cert}" -inform DER -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//')"
        if [[ -n "${fp}" ]] && mokutil --list-new 2>/dev/null | grep -qi "${fp}"; then
          printf 'install-packages.sh: %s already queued for enrollment on next boot; skipping.\n' "${cert}"
          continue
        fi
        to_import+=("${cert}")
      done
      if [[ ${#to_import[@]} -gt 0 ]]; then
        "${SUDO[@]}" mokutil --import "${to_import[@]}"
      else
        printf 'install-packages.sh: all akmods/dkms MOK keys already enrolled or queued.\n'
      fi
    fi
  fi
}

configure-time() {
  "${SUDO[@]}" timedatectl set-local-rtc 0
  "${SUDO[@]}" timedatectl set-ntp true
}

configure-user-groups() {
  "${SUDO[@]}" usermod -aG keyd,libvirt,vboxusers "$USER"
  if getent group docker >/dev/null 2>&1; then "${SUDO[@]}" gpasswd -d "$USER" docker 2>/dev/null || true; fi

  # Allocate subordinate UID/GID ranges for rootless Podman user namespaces.
  # usermod --add-subuids fails if a range already exists, so only add when
  # the user has no entry yet.
  grep -q "^$USER:" /etc/subuid || "${SUDO[@]}" usermod --add-subuids 100000-165535 "$USER"
  grep -q "^$USER:" /etc/subgid || "${SUDO[@]}" usermod --add-subgids 100000-165535 "$USER"

  # Group changes only take effect on next login. Notify when the current
  # shell is missing either group — silent on re-runs after re-login.
  if ! id -nG | grep -qw keyd || ! id -nG | grep -qw libvirt || ! id -nG | grep -qw vboxusers; then
    printf '\n'
    printf 'NOTE: Added "%s" to groups: keyd, libvirt, vboxusers\n' "$USER"
    printf '      Log out and back in (or reboot) for group membership to take effect.\n'
  fi
}

install-fedora-packages
install-dotnet-tools
build-akmods
install-virtualbox-extension-pack
configure-time
enable-services
configure-user-groups
