#!/usr/bin/env bash
# scripts/linux/config-kde.sh
#
# Combined KDE Plasma 6 user-side configuration. Thirteen independent steps,
# each guarded so a missing prerequisite skips that step alone (returning 0)
# without taking the whole script down:
#
#   1. fonts    - kwriteconfig6 -> ~/.config/kdeglobals
#                 sans (font, menuFont, toolBarFont, smallestReadableFont,
#                       [WM] activeFont)            -> Pretendard
#                 mono (fixed)                      -> JetBrainsMono Nerd Font
#                 Errors (exit 1) when a requested font isn't installed - run
#                 scripts/bootstrap/install-fonts.sh first.
#
#   2. touchpad - busctl --user -> KWin's org.kde.KWin.InputDeviceManager
#                 For each touchpad whose libinput name appears in
#                 TOUCHPAD_TARGET_NAMES:
#                   naturalScroll          -> true
#                   clickMethodClickfinger -> true
#                   clickMethodAreas       -> false
#                 Other touchpads (e.g. external USB trackpads) untouched.
#                 Skips cleanly when busctl is missing or no Plasma session
#                 owns org.kde.KWin (chroot, headless, GNOME, ...).
#
#   3. panel    - kwriteconfig6 -> ~/.config/plasma-org.kde.plasma.desktop-appletsrc
#                 For every org.kde.plasma.icontasks / org.kde.plasma.taskmanager
#                 applet at the panel level (NOT under systemtray):
#                   [Configuration][General] groupingStrategy = 0
#                 i.e. "Do not group" / TasksModel::GroupDisabled. Matches
#                 the dropdown labelled "Group: Do not group" in the
#                 Icons-Only Task Manager configuration dialog.
#
#   4. kickoff  - kwriteconfig6 -> ~/.config/plasma-org.kde.plasma.desktop-appletsrc
#                 For every org.kde.plasma.kickoff applet at the panel level:
#                   [Configuration][General] favoritesDisplay    = 1
#                   [Configuration][General] applicationsDisplay = 1
#                 1 = "In a list" (per the kickoff main.xml schema:
#                 "0 = Grid, 1 = List"). Matches the radio buttons labelled
#                 "Show favorites: In a list" and "Show other applications:
#                 In a list" in the Application Launcher configuration dialog.
#
#   5. virtual  - kwriteconfig6 -> ~/.config/kwinrc
#      keyboard   [Wayland] InputMethod = /usr/share/applications/fcitx5-wayland-launcher.desktop
#                 Selects Fcitx 5 Wayland Launcher as the KWin virtual
#                 keyboard / input-method launcher (matches the System
#                 Settings > Keyboard > Virtual Keyboard panel). The kcfg
#                 type is `Path` (per /usr/share/config.kcfg/kwin.kcfg),
#                 so we use `--type path` and let KConfig write the
#                 canonical `InputMethod[$e]=...` form. Skips cleanly when
#                 fcitx5-wayland-launcher is not installed - install
#                 fcitx5 (scripts/linux/install-packages.sh on Fedora) and re-run.
#
#   6. digital  - kwriteconfig6 -> ~/.config/plasma-org.kde.plasma.desktop-appletsrc
#      clock      For every org.kde.plasma.digitalclock applet at the panel level:
#                   [Configuration][Appearance] dateFormat = longDate
#                 Matches the "날짜 형식: 긴 날짜" / "Date format: Long Date"
#                 dropdown in the Digital Clock configuration dialog
#                 (e.g. preview "2026년 5월 21일 목..."). Valid values per
#                 the upstream schema are shortDate, longDate, isoDate,
#                 custom. Defaults to shortDate.
#
#   7. calendar - Three writes that together enable the calendar popup
#                 features in the Digital Clock - holidays + PIM events
#                 for South Korea, with every locally-available PIM
#                 calendar (personal ical + birthdays) selected:
#                   a) kwriteconfig6 -> ~/.config/plasma-org.kde.plasma.desktop-appletsrc
#                      For every org.kde.plasma.digitalclock applet at the panel level:
#                        [Configuration][Appearance] enabledCalendarPlugins
#                            = holidaysevents,pimevents
#                      Matches the "공휴일" + "캘린더 이벤트" checkboxes
#                      under the "달력 / Calendar" tab. Other plugins
#                      ("대체 달력" / "천문 현상") stay disabled.
#                   b) kwriteconfig6 -> ~/.config/plasma_calendar_holiday_regions
#                        [General] selectedRegions = kr_ko
#                      Matches the "South Korea" entry under the "공휴일
#                      / Holidays" tab.
#                   c) kwriteconfig6 -> ~/.config/plasmashellrc
#                        [PIMEventsPlugin] calendars = <comma-separated Akonadi collection IDs>
#                      IDs are discovered at runtime by querying the
#                      local Akonadi MariaDB over its UNIX socket for
#                      every CollectionTable row carrying a calendar
#                      MIME type (text/calendar,
#                      application/x-vnd.akonadi.calendar.event,
#                      .calendar.todo, .calendar.journal). Matches the
#                      "캘린더 이벤트 / Calendar Events" tab with every
#                      calendar checked. Sub-steps (a) and (b) write
#                      regardless; sub-step (c) soft-skips when mariadb
#                      client is missing, the akonadi socket is absent
#                      (akonadi not running), or the query returns zero
#                      collections (no PIM resources configured yet).
#
#   8. edges    - kwriteconfig6 -> ~/.config/kwinrc
#                   [ElectricBorders] Top/TopRight/Right/BottomRight/
#                                     Bottom/BottomLeft/Left/TopLeft = None
#                   [EdgeBarrier] CornerBarrier = false
#                                 EdgeBarrier   = 0
#                 Disables every screen edge/corner action and the Plasma 6
#                 multi-monitor pointer barrier that resists cursor movement
#                 across monitor edges. Applies after restarting KWin or
#                 logging out/in.
#
#   9. krunner  - kwriteconfig6 -> ~/.config/krunnerrc
#                   [General] FreeFloating    = true
#                   [General] historyBehavior = ImmediateCompletion
#                 Makes KRunner behave like macOS Spotlight: a free-floating
#                 box centered on screen instead of docked at the top, with
#                 inline history auto-completion as you type. Maps to the
#                 KRunner settings dialog:
#                   "Position on screen: Center"  (FreeFloating; default false
#                                                  = Top)
#                   "History: Enable autocompletion"  (historyBehavior; per
#                       krunnersettingsbase.kcfg the enum is Disabled /
#                       ImmediateCompletion / CompletionSuggestion, default
#                       CompletionSuggestion = "Enable suggestions").
#                 Writes krunnerrc directly (kwriteconfig6 creates it if
#                 absent), so no file-exists guard is needed. Applies on the
#                 next KRunner launch (kquitapp6 krunner to reload a running
#                 instance).
#
#  10. killruner - kwriteconfig6 -> ~/.config/krunnerrc
#                   [Runners][krunner_kill] useTriggerWord = true
#                   [Runners][krunner_kill] triggerWord    = kill
#                   [Runners][krunner_kill] sorting        = 1
#                 Configures the "Terminate Applications" (kill) runner: a
#                 fixed English trigger word "kill" (the default is i18n("kill"),
#                 which localizes - e.g. Korean "죽이기" - so we pin it), and
#                 sorts process matches by CPU usage. Keys and the storage group
#                 are from plasma-workspace runners/kill: the KCM writes
#                 [Runners][<KRUNNER_PLUGIN_NAME>] with KRUNNER_PLUGIN_NAME =
#                 "krunner_kill" (CMakeLists target_compile_definitions), and the
#                 sorting enum (config_keys.h) is NONE=0, CPU=1, CPUI=2 -> 1 is
#                 "CPU usage". Same direct-write rationale and KRunner-launch
#                 reload caveat as step 9.
#
#  11. dolphin  - kwriteconfig6 -> ~/.config/dolphinrc
#                   [General] RememberOpenedTabs = false
#                   [General] HomeUrl            = $HOME
#                 Makes Dolphin open the home folder on startup instead of
#                 restoring the previous session's folders/tabs. Maps to the
#                 Dolphin "Startup" settings page: clearing "Remember open
#                 folders and tabs" (RememberOpenedTabs, default true) makes
#                 Dolphin open the "Start in:" location (HomeUrl) on launch,
#                 which we pin to $HOME. Keys/types are from Dolphin's
#                 dolphin_generalsettings.kcfg (RememberOpenedTabs = Bool,
#                 HomeUrl = String, default QDir::homePath()). Like krunnerrc,
#                 dolphinrc is read by Dolphin at launch (not owned by a
#                 long-lived process), so kwriteconfig6 creates/edits it
#                 directly with no file-exists guard. Applies to the next
#                 Dolphin launch; the write is idempotent.
#
#  12. dimscreen - kwriteconfig6 -> ~/.config/powerdevilrc
#                   [AC][Display]         DimDisplayWhenIdle       = false
#                                         DimDisplayIdleTimeoutSec = -1
#                   [Battery][Display]    DimDisplayWhenIdle       = false
#                                         DimDisplayIdleTimeoutSec = -1
#                   [LowBattery][Display] DimDisplayWhenIdle       = false
#                                         DimDisplayIdleTimeoutSec = -1
#                 Disables PowerDevil's inactivity screen-dimming action in
#                 every power profile (AC / Battery / LowBattery). Matches the
#                 "자동으로 어둡게 하기 / Dim screen" dropdown set to "하지 않음
#                 / Never" on the System Settings "디스플레이와 밝기 / Display &
#                 Brightness" page. DimDisplayWhenIdle=false is the toggle that
#                 gates the action; DimDisplayIdleTimeoutSec=-1 mirrors the KCM's
#                 "never" sentinel so the written state is byte-identical to the
#                 GUI's. Plasma 6 keeps power settings in powerdevilrc (the
#                 Plasma 5 powermanagementprofilesrc is migrated to it, recorded
#                 by its [Migration] MigratedProfilesToPlasma6 marker). Like
#                 krunnerrc/dolphinrc, powerdevilrc is read - not rewritten - by
#                 the powerdevil daemon, so kwriteconfig6 writes it directly with
#                 no file-exists guard; the change applies after re-login or when
#                 powerdevil reloads its config. The companion "화면 끄기 / Turn
#                 off screen" (TurnOffDisplay*) action is left untouched.
#
#  13. darkmode  - kwriteconfig6 -> ~/.config/kdeglobals
#                   [KDE]     AutomaticLookAndFeel = false
#                   [KDE]     LookAndFeelPackage   = org.kde.breezedark.desktop
#                   [General] ColorScheme          = BreezeDark
#                 Pins the desktop to the default dark Global Theme ("Breeze
#                 Dark") and turns OFF the Plasma 6.5+ automatic day/night theme
#                 switching, so the appearance stays dark instead of following
#                 the sun. Matches System Settings > Colors & Themes > Global
#                 Theme: choosing "Breeze Dark" and clearing the "Switch to Dark
#                 Mode at Night" (automatic) toggle. Keys and types are from
#                 plasma-workspace's lookandfeelsettings.kcfg [KDE] group:
#                 AutomaticLookAndFeel (Bool, default false), LookAndFeelPackage
#                 (String, default org.kde.breeze.desktop = light); BreezeDark is
#                 the dark color-scheme name under [General] ColorScheme. Applies
#                 on next login: startplasma's setupPlasmaEnvironment() reapplies
#                 the Global Theme when LookAndFeelPackage differs from the cached
#                 active package (~/.config/kdedefaults/package), and re-copies
#                 the color scheme when its .colors file hash differs from
#                 [General] ColorSchemeHash - so we write only the scheme NAME and
#                 let startplasma recompute the hash and copy the color
#                 definitions (a stale hand-written hash would suppress the
#                 re-apply). Like the kwinrc steps, kdeglobals is read - not
#                 owned - at login, so kwriteconfig6 writes it directly with no
#                 file-exists guard; the write is idempotent.
#
# Single-platform (Linux only) by design. KDE Plasma is a Linux desktop
# environment; macOS uses native font/touchpad APIs and Windows uses the
# registry, so there is nothing equivalent to configure on either. No .ps1
# counterpart per the script-parity exception in ../AGENTS.md.
#
# MUST run as the user owning the Plasma session (touchpad uses session DBus,
# fonts/panel/virtualkeyboard write to ~/.config); never invoke under sudo.
#
# Re-runnable: every write is idempotent.
#
# After running:
#   - fonts, panel, kickoff      apply after restarting plasmashell or
#                                logging out/in.
#   - touchpad                   applies live via DBus.
#   - virtualkeyboard            applies after restarting KWin
#                                (`kwin_wayland --replace`) or logging out/in.
#   - digitalclock, calendar     apply after restarting plasmashell or
#                                logging out/in (same caveat as panel/kickoff).
#   - edges                      apply after restarting KWin or logging out/in.
#   - krunner, killrunner        apply on next KRunner launch (kquitapp6
#                                krunner to reload a running instance).
#   - darkmode                   applies after re-login (startplasma reapplies
#                                the global theme + color scheme at login).

set -euo pipefail

# ---------------------------------------------------------------------------
# Common: hard-skip on non-KDE systems (no plasmashell binary anywhere).
# Used by every step as the "is this a KDE box?" probe.
# ---------------------------------------------------------------------------

if ! command -v plasmashell >/dev/null 2>&1; then
  printf 'config-kde.sh: plasmashell not found (non-KDE system), skipping.\n'
  exit 0
fi

# ===========================================================================
# Step 1: fonts
# ===========================================================================

configure_fonts() {
  printf 'config-kde.sh: [fonts] configuring KDE display fonts...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi
  if ! command -v fc-match >/dev/null 2>&1; then
    printf '  fc-match not found, cannot verify font availability.\n' >&2
    return 1
  fi

  local SANS="Pretendard"
  local MONO="JetBrainsMono Nerd Font"

  # fc-match always returns SOMETHING (closest fallback). Compare the
  # resolved family name to the requested family name to detect an actual
  # install.
  _require_font() {
    local family="$1"
    local matched
    matched="$(fc-match -f '%{family[0]}' "$family")"
    if [[ "$matched" != "$family" ]]; then
      printf '  font "%s" not installed (fc-match -> "%s"). Run scripts/bootstrap/install-fonts.sh first.\n' \
        "$family" "$matched" >&2
      return 1
    fi
  }

  _require_font "$SANS"
  _require_font "$MONO"

  # Plasma 6 / Qt 6 kdeglobals font value format (16 comma-separated fields):
  #   family,pointSize,pixelSize,styleHint,weight,italic,underline,strikeOut,
  #   fixedPitch,rawMode,styleStrategy,stretch,(unused)x3,preferTypoLineMetrics
  # Weight 400 = Regular, styleHint 5 = AnyStyle. 10pt for general fonts,
  # 8pt for smallestReadableFont to match KDE defaults.
  _font_value() { printf '%s,%d,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$1" "$2"; }

  _set_general() {
    local key="$1" value="$2"
    kwriteconfig6 --file kdeglobals --group General --key "$key" "$value"
    printf '  set [General] %-22s = %s\n' "$key" "$value"
  }

  _set_general font                 "$(_font_value "$SANS" 10)"
  _set_general menuFont             "$(_font_value "$SANS" 10)"
  _set_general toolBarFont          "$(_font_value "$SANS" 10)"
  _set_general fixed                "$(_font_value "$MONO" 10)"
  _set_general smallestReadableFont "$(_font_value "$SANS"  8)"

  # Window-title font lives under [WM].
  local wm_active
  wm_active="$(_font_value "$SANS" 10)"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "$wm_active"
  printf '  set [WM]      %-22s = %s\n' "activeFont" "$wm_active"
}

# ===========================================================================
# Step 2: touchpad (libinput natural scroll + tap-to-click + clickfinger via KWin DBus)
# ===========================================================================

# Only touchpads whose libinput `name` exactly matches an entry here are
# configured. Add more names (one per line, no trailing whitespace) to
# extend coverage to additional hosts.
TOUCHPAD_TARGET_NAMES=(
  'SynPS/2 Synaptics TouchPad'
  'ELAN06E8:00 04F3:332E Touchpad'
)

configure_touchpad() {
  printf 'config-kde.sh: [touchpad] configuring KDE touchpad(s)...\n'

  if ! command -v busctl >/dev/null 2>&1; then
    printf '  busctl not found, skipping.\n'
    return 0
  fi

  local SERVICE='org.kde.KWin'
  local MGR_PATH='/org/kde/KWin/InputDevice'
  local IFACE_MGR='org.kde.KWin.InputDeviceManager'
  local IFACE_DEV='org.kde.KWin.InputDevice'

  # busctl get-property prints "<sig> <value>", e.g. `b true` or `s "foo"`.
  # Strip the signature prefix; callers compare against `true`/`false` for
  # bools and strip the surrounding quotes themselves for strings.
  _dbus_get() {
    local path="$1" prop="$2"
    busctl --user get-property "$SERVICE" "$path" "$IFACE_DEV" "$prop" 2>/dev/null \
      | awk '{ $1=""; sub(/^ /, ""); print }'
  }

  _dbus_set_b() {
    local path="$1" prop="$2" value="$3"
    busctl --user set-property "$SERVICE" "$path" "$IFACE_DEV" "$prop" b "$value"
    printf '    set %-26s = %s\n' "$prop" "$value"
  }

  # Probe org.kde.KWin via the InputDeviceManager and grab the sysnames in
  # the same call. busctl exits non-zero if the service isn't on the session
  # bus, which is the normal case for non-Plasma / headless / chroot
  # environments - skip cleanly.
  #
  # (`busctl --user list` cannot be used as a precheck: it filters its
  # output differently when stdout is not a TTY and hides well-known names
  # in scripts.)
  local raw
  if ! raw="$(busctl --user get-property "$SERVICE" "$MGR_PATH" "$IFACE_MGR" devicesSysNames 2>/dev/null)"; then
    printf '  org.kde.KWin not reachable on session bus (no active Plasma session?), skipping.\n'
    return 0
  fi

  # busctl emits `as N "event0" "event1" ...`; just grab everything between
  # double-quotes.
  local sysnames=()
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] && sysnames+=("$name")
  done < <(printf '%s\n' "$raw" | grep -oE '"[^"]+"' | tr -d '"')

  local count=0
  local sn path is_touchpad name_quoted matched target
  for sn in "${sysnames[@]}"; do
    path="$MGR_PATH/$sn"
    is_touchpad="$(_dbus_get "$path" touchpad)"
    [[ "$is_touchpad" == "true" ]] || continue

    name_quoted="$(_dbus_get "$path" name)"
    name="${name_quoted#\"}"
    name="${name%\"}"

    # Skip touchpads not in the allow-list.
    matched=0
    for target in "${TOUCHPAD_TARGET_NAMES[@]}"; do
      if [[ "$name" == "$target" ]]; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -eq 0 ]]; then
      printf '  skip: %s (%s) — not in TOUCHPAD_TARGET_NAMES\n' "$name" "$sn"
      continue
    fi

    printf '  touchpad: %s (%s)\n' "$name" "$sn"

    # Natural scroll (two-finger drag follows content).
    if [[ "$(_dbus_get "$path" supportsNaturalScroll)" == "true" ]]; then
      _dbus_set_b "$path" naturalScroll true
    else
      printf '    skip naturalScroll: not supported by device\n'
    fi

    local tap_finger_count
    tap_finger_count="$(_dbus_get "$path" tapFingerCount)"
    if [[ -n "$tap_finger_count" && "$tap_finger_count" != "0" ]]; then
      _dbus_set_b "$path" tapToClick true
    else
      printf '    skip tapToClick: not supported by device\n'
    fi

    # Clickfinger (two-finger = right, three-finger = middle). The two
    # click methods are mutually exclusive in libinput; set both explicitly
    # so the final state is deterministic regardless of the previous value.
    if [[ "$(_dbus_get "$path" supportsClickMethodClickfinger)" == "true" ]]; then
      _dbus_set_b "$path" clickMethodClickfinger true
      if [[ "$(_dbus_get "$path" supportsClickMethodAreas)" == "true" ]]; then
        _dbus_set_b "$path" clickMethodAreas false
      fi
    else
      printf '    skip clickMethodClickfinger: not supported by device\n'
    fi

    count=$((count + 1))
  done

  if [[ "$count" -eq 0 ]]; then
    printf '  no touchpad in TOUCHPAD_TARGET_NAMES present on this session, skipping.\n'
    return 0
  fi

  printf '  configured %d touchpad(s).\n' "$count"
}

# ===========================================================================
# Step 3: panel (disable task manager grouping)
# ===========================================================================
#
# Sets `groupingStrategy = 0` (TasksModel::GroupDisabled, "Do not group") on
# every panel-level icontasks / taskmanager applet. Default is 1
# (GroupApplications, "By program name"), which collapses N windows of the
# same app into a single panel entry behind a click-through menu - we want
# one entry per window.
#
# CAVEAT: ~/.config/plasma-org.kde.plasma.desktop-appletsrc is owned by a
# running plasmashell. plasmashell holds it in memory, only re-reads on
# startup, and re-writes it whenever something changes via the UI. To make
# this take effect cleanly:
#   1. Run this script BEFORE plasmashell first starts (e.g. fresh user
#      account, chroot install); or
#   2. Run it, then restart plasmashell (kquitapp6 plasmashell ; kstart
#      plasmashell) before touching the panel via the GUI - otherwise
#      plasmashell's stale in-memory state will overwrite our edit.
# Either way the write is idempotent so re-running is safe.

configure_panel() {
  printf 'config-kde.sh: [panel] disabling task manager grouping...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1 || ! command -v kreadconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6/kreadconfig6 not found, skipping.\n'
    return 0
  fi

  local file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [[ ! -f "$file" ]]; then
    printf '  %s not found (no Plasma session has ever started?), skipping.\n' "$file"
    return 0
  fi

  # Find icontasks/taskmanager applets at the panel level. The anchored
  # regex matches `[Containments][N][Applets][M]` exactly, excluding the
  # nested `[Containments][N][Applets][M][Applets][L]` shape used by
  # systemtray subapplets - we don't want to flip grouping on a stray
  # systray task indicator (none currently exist, but be explicit).
  local count=0
  local containment applet plugin
  while IFS=':' read -r containment applet; do
    plugin="$(kreadconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --key plugin)"
    case "$plugin" in
      org.kde.plasma.icontasks|org.kde.plasma.taskmanager) ;;
      *) continue ;;
    esac
    kwriteconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --group Configuration --group General \
      --key groupingStrategy 0
    printf '  set [Containments/%s/Applets/%s] (%s) groupingStrategy = 0\n' \
      "$containment" "$applet" "$plugin"
    count=$((count + 1))
  done < <(grep -oE '^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$' "$file" \
            | sed -E 's/^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$/\1:\2/')

  if [[ "$count" -eq 0 ]]; then
    printf '  no icontasks/taskmanager applet found in panel config, skipping.\n'
    return 0
  fi

  printf '  configured %d task manager applet(s).\n' "$count"
}

# ===========================================================================
# Step 4: kickoff (show favorites + other applications as list, not grid)
# ===========================================================================
#
# Sets `favoritesDisplay = 1` and `applicationsDisplay = 1` on every
# panel-level org.kde.plasma.kickoff applet. These map to the radio
# buttons in the Application Launcher configuration dialog:
#   - "Show favorites"          -> "In a list"   (favoritesDisplay)
#   - "Show other applications" -> "In a list"   (applicationsDisplay)
# 0 = grid, 1 = list - per plasma-desktop/applets/kickoff/main.xml:
#   <entry name="favoritesDisplay" type="Int">
#       <label>How to display favorites: 0 = Grid, 1 = List</label>
#   <entry name="applicationsDisplay" type="Int">
#       <label>How to display applications: 0 = Grid, 1 = List</label>
# Upstream defaults are favoritesDisplay=0 (grid) and applicationsDisplay=1
# (list). We set both explicitly so the final state is deterministic.
#
# Same plasmashell-ownership caveat as Step 3: edits to
# plasma-org.kde.plasma.desktop-appletsrc are only safe before
# plasmashell first starts, or after restarting it - otherwise the live
# plasmashell process will overwrite our edit from its in-memory state.
# The write is idempotent so re-running is safe.

configure_kickoff() {
  printf 'config-kde.sh: [kickoff] showing favorites and applications as list...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1 || ! command -v kreadconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6/kreadconfig6 not found, skipping.\n'
    return 0
  fi

  local file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [[ ! -f "$file" ]]; then
    printf '  %s not found (no Plasma session has ever started?), skipping.\n' "$file"
    return 0
  fi

  # Same panel-level regex as Step 3: anchored on `[Containments][N][Applets][M]`
  # so nested `[Containments][N][Applets][M][Applets][L]` systemtray sub-applets
  # cannot match. Kickoff should never live inside a systemtray, but be
  # explicit anyway.
  local count=0
  local containment applet plugin
  while IFS=':' read -r containment applet; do
    plugin="$(kreadconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --key plugin)"
    [[ "$plugin" == "org.kde.plasma.kickoff" ]] || continue
    kwriteconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --group Configuration --group General \
      --key favoritesDisplay 1
    kwriteconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --group Configuration --group General \
      --key applicationsDisplay 1
    printf '  set [Containments/%s/Applets/%s] (%s) favoritesDisplay=1 applicationsDisplay=1\n' \
      "$containment" "$applet" "$plugin"
    count=$((count + 1))
  done < <(grep -oE '^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$' "$file" \
            | sed -E 's/^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$/\1:\2/')

  if [[ "$count" -eq 0 ]]; then
    printf '  no kickoff applet found in panel config, skipping.\n'
    return 0
  fi

  printf '  configured %d kickoff applet(s).\n' "$count"
}

# ===========================================================================
# Step 5: virtualkeyboard (fcitx5 wayland launcher)
# ===========================================================================
#
# Selects the KWin Wayland virtual-keyboard / input-method launcher.
# Per the KCfgXT schema at /usr/share/config.kcfg/kwin.kcfg:
#
#   <group name="Wayland">
#       <entry name="InputMethod" type="Path" />
#
# So the value is the absolute path to a desktop file flagged with
# X-KDE-Wayland-VirtualKeyboard=true. KConfig's `Path` type is serialised
# with the `[$e]` (expand) flag - `kwriteconfig6 --type path` produces
# the canonical form `InputMethod[$e]=...`, which kreadconfig6 / KWin
# / kcm_virtualkeyboard.so all consume.
#
# Target file is set in VIRTUAL_KEYBOARD_DESKTOP_FILE below. Soft-skips
# when the .desktop file isn't installed (fcitx5 may not be installed yet
# when this runs from the dotbot bootstrap; re-run after
# scripts/linux/install-packages.sh).
#
# Wayland-only setting. On X11 sessions KWin ignores it - harmless to
# write. Applies on next KWin (re)start; no live-reload via DBus.

VIRTUAL_KEYBOARD_DESKTOP_FILE='/usr/share/applications/fcitx5-wayland-launcher.desktop'

configure_virtualkeyboard() {
  printf 'config-kde.sh: [virtualkeyboard] selecting fcitx5 wayland launcher...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  if [[ ! -f "$VIRTUAL_KEYBOARD_DESKTOP_FILE" ]]; then
    printf '  %s not installed (install fcitx5 first), skipping.\n' \
      "$VIRTUAL_KEYBOARD_DESKTOP_FILE"
    return 0
  fi

  kwriteconfig6 --file kwinrc \
    --group Wayland \
    --key InputMethod \
    --type path \
    "$VIRTUAL_KEYBOARD_DESKTOP_FILE"
  printf '  set [Wayland] InputMethod = %s\n' "$VIRTUAL_KEYBOARD_DESKTOP_FILE"
}

# ===========================================================================
# Step 6: digitalclock (show date in long format)
# ===========================================================================
#
# Sets `dateFormat = longDate` on every panel-level org.kde.plasma.digitalclock
# applet. Maps to the "Date format" dropdown in the Digital Clock
# configuration dialog (Korean: "날짜 형식: 긴 날짜", e.g. preview
# "2026년 5월 21일 목요일"). The Appearance group is plain-text key/value,
# no `[$e]` flag - kwriteconfig6 writes `dateFormat=longDate` directly.
# Valid values: shortDate (default), longDate, isoDate, custom.
#
# Same plasmashell-ownership caveat as Steps 3 and 4: edits to
# plasma-org.kde.plasma.desktop-appletsrc are only safe before plasmashell
# first starts, or after restarting it - otherwise the live plasmashell
# process will overwrite our edit from its in-memory state. The write is
# idempotent so re-running is safe.

configure_digitalclock() {
  printf 'config-kde.sh: [digitalclock] setting date format to long...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1 || ! command -v kreadconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6/kreadconfig6 not found, skipping.\n'
    return 0
  fi

  local file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [[ ! -f "$file" ]]; then
    printf '  %s not found (no Plasma session has ever started?), skipping.\n' "$file"
    return 0
  fi

  local count=0
  local containment applet plugin
  while IFS=':' read -r containment applet; do
    plugin="$(kreadconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --key plugin)"
    [[ "$plugin" == "org.kde.plasma.digitalclock" ]] || continue
    kwriteconfig6 --file "$file" \
      --group Containments --group "$containment" \
      --group Applets --group "$applet" \
      --group Configuration --group Appearance \
      --key dateFormat longDate
    printf '  set [Containments/%s/Applets/%s] (%s) dateFormat = longDate\n' \
      "$containment" "$applet" "$plugin"
    count=$((count + 1))
  done < <(grep -oE '^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$' "$file" \
            | sed -E 's/^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$/\1:\2/')

  if [[ "$count" -eq 0 ]]; then
    printf '  no digitalclock applet found in panel config, skipping.\n'
    return 0
  fi

  printf '  configured %d digitalclock applet(s).\n' "$count"
}

# ===========================================================================
# Step 7: calendar (holidays + PIM events + South Korea + all calendars)
# ===========================================================================
#
# Three independent writes that together turn on the digital clock's
# calendar popup features. See the header step index for the full mapping
# to the GUI tabs.
#
# Sub-step (c) discovers Akonadi calendar collection IDs at runtime. The
# IDs are local, assigned in resource-creation order, and differ between
# machines - hardcoding the values from one host (2,8 here) would silently
# enable the wrong calendars (or no calendars) elsewhere. We query the
# local MariaDB that Akonadi runs over its UNIX socket. The socket path
# comes from akonadiserverrc (Options="UNIX_SOCKET=..."); on stock Akonadi
# it always resolves to /run/user/$UID/akonadi/mysql.socket, but we still
# parse the config so a non-standard runtime dir doesn't break us.
#
# Same plasmashell-ownership caveat as Steps 3, 4, and 6: edits to
# plasma-org.kde.plasma.desktop-appletsrc are only safe before plasmashell
# first starts, or after restarting it. The two non-applet files
# (plasma_calendar_holiday_regions, plasmashellrc [PIMEventsPlugin]) are
# read on demand by the calendar plugin and reflect on the next popup
# open after a plasmashell restart.

configure_calendar() {
  printf 'config-kde.sh: [calendar] enabling holidays + pimevents, South Korea, all PIM calendars...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1 || ! command -v kreadconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6/kreadconfig6 not found, skipping.\n'
    return 0
  fi

  # ---- (a) enabledCalendarPlugins on each panel digitalclock applet ----
  local applet_file="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  if [[ ! -f "$applet_file" ]]; then
    printf '  %s not found (no Plasma session has ever started?), skipping (a).\n' "$applet_file"
  else
    local count=0
    local containment applet plugin
    while IFS=':' read -r containment applet; do
      plugin="$(kreadconfig6 --file "$applet_file" \
        --group Containments --group "$containment" \
        --group Applets --group "$applet" \
        --key plugin)"
      [[ "$plugin" == "org.kde.plasma.digitalclock" ]] || continue
      kwriteconfig6 --file "$applet_file" \
        --group Containments --group "$containment" \
        --group Applets --group "$applet" \
        --group Configuration --group Appearance \
        --key enabledCalendarPlugins "holidaysevents,pimevents"
      printf '  set [Containments/%s/Applets/%s] (%s) enabledCalendarPlugins = holidaysevents,pimevents\n' \
        "$containment" "$applet" "$plugin"
      count=$((count + 1))
    done < <(grep -oE '^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$' "$applet_file" \
              | sed -E 's/^\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]$/\1:\2/')

    if [[ "$count" -eq 0 ]]; then
      printf '  no digitalclock applet found in panel config, skipping (a).\n'
    else
      printf '  (a) configured %d digitalclock applet(s).\n' "$count"
    fi
  fi

  # ---- (b) South Korea holiday region ----
  kwriteconfig6 --file plasma_calendar_holiday_regions \
    --group General \
    --key selectedRegions "kr_ko"
  printf '  (b) set [General] selectedRegions = kr_ko in plasma_calendar_holiday_regions\n'

  # ---- (c) enable every Akonadi calendar collection in PIMEventsPlugin ----
  if ! command -v mariadb >/dev/null 2>&1; then
    printf '  (c) mariadb client not found, skipping (PIM calendars left unchanged).\n'
    return 0
  fi

  local akonadi_rc="$HOME/.config/akonadi/akonadiserverrc"
  local socket=""
  if [[ -f "$akonadi_rc" ]]; then
    # Options="UNIX_SOCKET=/run/user/1000/akonadi/mysql.socket"
    socket="$(grep -E '^Options=' "$akonadi_rc" \
      | sed -nE 's/.*UNIX_SOCKET=([^"]+).*/\1/p' | head -n1)"
  fi
  [[ -n "$socket" ]] || socket="/run/user/$(id -u)/akonadi/mysql.socket"

  if [[ ! -S "$socket" ]]; then
    printf '  (c) akonadi socket %s not found (akonadi not running?), skipping.\n' "$socket"
    return 0
  fi

  # Calendar-bearing MIME types (per MimeTypeTable). text/calendar is the
  # iCalendar root type; the .calendar.{event,todo,journal} types are the
  # KDE-specific subtypes that live alongside it. Using a fixed list of
  # type *names* (looked up to IDs in the query) is robust across hosts -
  # MimeTypeTable IDs themselves are local, just like collection IDs.
  local ids
  if ! ids="$(mariadb --socket="$socket" -u root akonadi \
      -B --skip-column-names --silent \
      -e "SELECT DISTINCT c.id
            FROM CollectionTable c
            JOIN CollectionMimeTypeRelation cmr ON cmr.Collection_id = c.id
            JOIN MimeTypeTable m ON m.id = cmr.MimeType_id
           WHERE m.name IN ('text/calendar',
                            'application/x-vnd.akonadi.calendar.event',
                            'application/x-vnd.akonadi.calendar.todo',
                            'application/x-vnd.akonadi.calendar.journal')
           ORDER BY c.id;" 2>/dev/null)"; then
    printf '  (c) failed to query akonadi MariaDB on %s, skipping.\n' "$socket"
    return 0
  fi

  # Join newline-separated IDs into a comma list, dropping blanks.
  local csv
  csv="$(printf '%s\n' "$ids" | awk 'NF' | paste -sd, -)"

  if [[ -z "$csv" ]]; then
    printf '  (c) akonadi returned 0 calendar collections (no PIM resources configured?), skipping.\n'
    return 0
  fi

  kwriteconfig6 --file plasmashellrc \
    --group PIMEventsPlugin \
    --key calendars "$csv"
  printf '  (c) set [PIMEventsPlugin] calendars = %s in plasmashellrc\n' "$csv"
}

# ===========================================================================
# Step 8: edges (disable screen-corner actions + monitor-edge pointer barrier)
# ===========================================================================
#
# KWin stores the screen edge/corner assignments in kwinrc [ElectricBorders].
# The kcfg schema defaults every key below to `None`, but a user/session can
# persist actions such as PresentWindows or ShowDesktop; write all eight
# explicitly so the final state is deterministic.
#
# Plasma 6's multi-monitor pointer barrier lives under [EdgeBarrier]. The GUI
# label is "Mouse pointer: Prevent pointer from crossing edges"; setting the
# barrier width to 0 and the corner barrier to false removes the cursor
# resistance/snapping at monitor boundaries. Applies on next KWin restart.

configure_edges() {
  printf 'config-kde.sh: [edges] disabling screen edge actions and monitor-edge pointer barrier...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  local edge
  for edge in Top TopRight Right BottomRight Bottom BottomLeft Left TopLeft; do
    kwriteconfig6 --file kwinrc \
      --group ElectricBorders \
      --key "$edge" None
    printf '  set [ElectricBorders] %-11s = None\n' "$edge"
  done

  kwriteconfig6 --file kwinrc \
    --group EdgeBarrier \
    --key CornerBarrier \
    --type bool \
    false
  printf '  set [EdgeBarrier] CornerBarrier = false\n'

  kwriteconfig6 --file kwinrc \
    --group EdgeBarrier \
    --key EdgeBarrier \
    --type int \
    0
  printf '  set [EdgeBarrier] EdgeBarrier = 0\n'
}

# ===========================================================================
# Step 9: krunner (center free-floating box + history autocompletion)
# ===========================================================================
#
# Sets two keys in krunnerrc [General]:
#   FreeFloating    = true                 -> centered floating box (default
#                                             false docks it at the screen top)
#   historyBehavior = ImmediateCompletion  -> inline auto-completion of the
#                                             prior search as you type
# Together these give a macOS-Spotlight-style launcher. Enum values come from
# /usr/share/config.kcfg/krunnersettingsbase.kcfg (Disabled /
# ImmediateCompletion / CompletionSuggestion). Unlike the appletsrc steps,
# krunnerrc is not owned by a long-lived plasmashell process: KRunner reads it
# at launch, so kwriteconfig6 can create/edit it directly with no file-exists
# guard. The write is idempotent.

configure_krunner() {
  printf 'config-kde.sh: [krunner] centering search box + enabling history autocompletion...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  kwriteconfig6 --file krunnerrc --group General --key FreeFloating --type bool true
  printf '  set [General] FreeFloating    = true\n'

  kwriteconfig6 --file krunnerrc --group General --key historyBehavior ImmediateCompletion
  printf '  set [General] historyBehavior = ImmediateCompletion\n'
}

# ===========================================================================
# Step 10: killrunner (kill trigger word + CPU-usage sorting)
# ===========================================================================
#
# Configures the "Terminate Applications" runner. Storage group and keys come
# from plasma-workspace runners/kill: the runner reads config()'s group
# [Runners][krunner_kill] (KRUNNER_PLUGIN_NAME="krunner_kill"), with sorting
# values NONE=0 / CPU=1 / CPUI=2 per config_keys.h. We pin the trigger word to
# the literal "kill" (the default is localized via i18n("kill")) and sort by
# CPU usage (1). Same direct-write / next-launch-reload behavior as step 9.

configure_killrunner() {
  printf 'config-kde.sh: [killrunner] setting kill trigger word + CPU-usage sorting...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  kwriteconfig6 --file krunnerrc --group Runners --group krunner_kill \
    --key useTriggerWord --type bool true
  printf '  set [Runners][krunner_kill] useTriggerWord = true\n'

  kwriteconfig6 --file krunnerrc --group Runners --group krunner_kill \
    --key triggerWord kill
  printf '  set [Runners][krunner_kill] triggerWord    = kill\n'

  kwriteconfig6 --file krunnerrc --group Runners --group krunner_kill \
    --key sorting 1
  printf '  set [Runners][krunner_kill] sorting        = 1 (CPU usage)\n'
}

# ===========================================================================
# Step 11: dolphin (open home folder on startup)
# ===========================================================================
#
# Clears RememberOpenedTabs (default true) so Dolphin opens HomeUrl on launch
# instead of restoring the previous session, and pins HomeUrl to $HOME. Keys
# and types are from Dolphin's dolphin_generalsettings.kcfg (RememberOpenedTabs
# = Bool, HomeUrl = String). Same direct-write / next-launch behavior as the
# krunnerrc steps: dolphinrc is read by Dolphin at launch, so kwriteconfig6
# creates/edits it directly with no file-exists guard. The write is idempotent.

configure_dolphin() {
  printf 'config-kde.sh: [dolphin] opening home folder on startup...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  kwriteconfig6 --file dolphinrc --group General \
    --key RememberOpenedTabs --type bool false
  printf '  set [General] RememberOpenedTabs = false\n'

  kwriteconfig6 --file dolphinrc --group General \
    --key HomeUrl "$HOME"
  printf '  set [General] HomeUrl            = %s\n' "$HOME"
}

# ===========================================================================
# Step 12: dimscreen (disable automatic screen dimming on inactivity)
# ===========================================================================
#
# Turns off PowerDevil's idle screen-dimming action for every power profile by
# setting DimDisplayWhenIdle=false (the gating toggle) plus
# DimDisplayIdleTimeoutSec=-1 (the KCM's "never" sentinel, so the written state
# matches the GUI byte-for-byte) under [<profile>][Display] in
# ~/.config/powerdevilrc, for profiles AC, Battery, and LowBattery. This is the
# "자동으로 어둡게 하기 / Dim screen" dropdown on the "디스플레이와 밝기 /
# Display & Brightness" page; disabling it across all profiles stops the
# display dimming on idle whether on mains or battery. The companion
# "화면 끄기 / Turn off screen" action (TurnOffDisplay*) is intentionally left
# alone.
#
# Plasma 6 stores power settings in powerdevilrc (the Plasma 5
# powermanagementprofilesrc is migrated to it, recorded by its [Migration]
# MigratedProfilesToPlasma6 marker). powerdevilrc is read - not rewritten - by
# the powerdevil daemon, so like krunnerrc/dolphinrc kwriteconfig6 can
# create/edit it directly with no file-exists guard. The write is idempotent
# and applies after re-login or when powerdevil reloads its config. The -1
# value is passed after `--` so kwriteconfig6 does not parse it as a flag.

configure_dimscreen() {
  printf 'config-kde.sh: [dimscreen] disabling automatic screen dimming on inactivity...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  local profile
  for profile in AC Battery LowBattery; do
    kwriteconfig6 --file powerdevilrc \
      --group "$profile" --group Display \
      --key DimDisplayWhenIdle --type bool false
    kwriteconfig6 --file powerdevilrc \
      --group "$profile" --group Display \
      --key DimDisplayIdleTimeoutSec --type int -- -1
    printf '  set [%s][Display] DimDisplayWhenIdle = false, DimDisplayIdleTimeoutSec = -1\n' \
      "$profile"
  done
}

# ===========================================================================
# Step 13: darkmode (pin default dark Global Theme, disable auto day/night)
# ===========================================================================
#
# Sets the desktop to the default dark Global Theme ("Breeze Dark") and turns
# off the Plasma 6.5+ automatic day/night theme switching, so the appearance
# stays dark rather than following the sun. Three writes to kdeglobals:
#   [KDE]     AutomaticLookAndFeel = false                       (disable auto)
#   [KDE]     LookAndFeelPackage   = org.kde.breezedark.desktop  (dark theme)
#   [General] ColorScheme          = BreezeDark                  (dark colors)
#
# Keys/types are from plasma-workspace's lookandfeelsettings.kcfg [KDE] group:
# AutomaticLookAndFeel is Bool (schema default false; the "Switch to Dark Mode
# at Night" toggle) and LookAndFeelPackage is String (schema default
# org.kde.breeze.desktop, the light theme). BreezeDark is the dark color-scheme
# name (its .colors file ships in /usr/share/color-schemes).
#
# Application: on the next login startplasma's setupPlasmaEnvironment() reads
# [KDE] LookAndFeelPackage and, when it differs from the cached active package
# in ~/.config/kdedefaults/package, loads and applies the whole dark Global
# Theme (KLookAndFeelManager, AllSettings). Independently it re-reads [General]
# ColorScheme and, when that scheme's .colors file hash no longer matches
# [General] ColorSchemeHash, copies the color definitions into kdeglobals and
# rewrites the hash. We therefore write only the scheme NAME and let startplasma
# recompute ColorSchemeHash and copy the colors - writing a stale hash here
# would suppress the re-apply. Like krunnerrc/dolphinrc/kwinrc, kdeglobals is
# read (not owned) at login, so kwriteconfig6 writes it directly with no
# file-exists guard; the write is idempotent and applies after re-login.

configure_darkmode() {
  printf 'config-kde.sh: [darkmode] pinning default dark global theme + disabling auto day/night switching...\n'

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    printf '  kwriteconfig6 not found, skipping.\n'
    return 0
  fi

  kwriteconfig6 --file kdeglobals --group KDE \
    --key AutomaticLookAndFeel --type bool false
  printf '  set [KDE]     AutomaticLookAndFeel = false\n'

  kwriteconfig6 --file kdeglobals --group KDE \
    --key LookAndFeelPackage org.kde.breezedark.desktop
  printf '  set [KDE]     LookAndFeelPackage   = org.kde.breezedark.desktop\n'

  kwriteconfig6 --file kdeglobals --group General \
    --key ColorScheme BreezeDark
  printf '  set [General] ColorScheme          = BreezeDark\n'
}

# ===========================================================================
# Run all steps. Each is independent; set -e propagates any real failure.
# ===========================================================================

configure_fonts
configure_touchpad
configure_panel
configure_kickoff
configure_virtualkeyboard
configure_digitalclock
configure_calendar
configure_edges
configure_krunner
configure_killrunner
configure_dolphin
configure_dimscreen
configure_darkmode

printf 'config-kde.sh: done. Restart plasmashell or re-login to fully apply font, panel, digital clock, and calendar changes; restart KWin (kwin_wayland --replace) or re-login to apply the virtual keyboard and edge changes; KRunner and Dolphin pick up their changes on next launch; the screen-dimming change and the dark-theme/auto-switch change apply after re-login (or when powerdevil reloads its config, for dimming).\n'
