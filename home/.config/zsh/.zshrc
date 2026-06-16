#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...

# MX Master 4 haptic: buzz JINGLE when a foreground command took a while AND
# you have looked away from this terminal. preexec stamps the start time;
# precmd measures elapsed and, past the threshold, fires the fast daemon client
# (mxm4-haptic) in the background (`&!` = spawn + disown) so the prompt is never
# delayed. Guarded on the binary so hosts without it (macOS without the daemon,
# fresh checkouts) stay silent. `local exit_status=$?` MUST be precmd's first
# statement — any other command clobbers $? — so Ctrl+C (SIGINT -> 130) can be
# detected and skipped: an interrupted job is not a completion worth celebrating.
if (( $+commands[mxm4-haptic] )); then
  autoload -Uz add-zsh-hook
  _MXM4_LONG_CMD_THRESHOLD=30  # seconds; tune to taste

  # True when THIS terminal is the focused window — you are watching, so a
  # finished command needs no buzz. kdotool reads KWin's active window over
  # KWin scripting: the only reliable focus probe on Wayland (DECSET ?1004
  # focus escapes are consumed by the foreground command, not the shell, and
  # KWin exposes no non-interactive active-window D-Bus getter). KWin reports
  # Konsole's window class as `org.kde.konsole` (verified via
  # `kdotool getactivewindow getwindowclassname`). Without kdotool this returns
  # false so the buzz still fires — bias toward a stray pulse over a missed one.
  _mxm4-terminal-focused() {
    (( $+commands[kdotool] )) || return 1
    local cls=${(L)"$(kdotool getactivewindow getwindowclassname 2>/dev/null)"}
    [[ $cls == *konsole* ]]
  }

  _mxm4-haptic-preexec() { _mxm4_cmd_start=$SECONDS }
  _mxm4-haptic-precmd() {
    local exit_status=$?
    [[ -n $_mxm4_cmd_start ]] || return
    local elapsed=$(( SECONDS - _mxm4_cmd_start ))
    unset _mxm4_cmd_start
    (( exit_status == 130 )) && return                # Ctrl+C (SIGINT): silent
    (( elapsed >= _MXM4_LONG_CMD_THRESHOLD )) || return
    _mxm4-terminal-focused && return                  # watching it: no buzz
    mxm4-haptic JINGLE &>/dev/null &!                 # looked away: buzz
  }
  add-zsh-hook preexec _mxm4-haptic-preexec
  add-zsh-hook precmd _mxm4-haptic-precmd
fi

#compdef opencode
###-begin-opencode-completions-###
#
# yargs command completion script
#
# Installation: opencode completion >> ~/.zshrc
#    or opencode completion >> ~/.zprofile on OSX.
#
_opencode_yargs_completions()
{
  local reply
  local si=$IFS
  IFS=$'
' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" opencode --get-yargs-completions "${words[@]}"))
  IFS=$si
  if [[ ${#reply} -gt 0 ]]; then
    _describe 'values' reply
  else
    _default
  fi
}
if [[ "'${zsh_eval_context[-1]}" == "loadautofunc" ]]; then
  _opencode_yargs_completions "$@"
else
  compdef _opencode_yargs_completions opencode
fi
###-end-opencode-completions-###

# Guard with `if` (not `[[ ... ]] && ...`): as the LAST command in .zshrc this
# determines $? at the first prompt. The `&&` form leaks exit 1 when the file is
# absent (sorin then paints the prompt as a failure); an `if` with a false test
# and no else returns 0.
if [[ -f /opt/adguard-cli/bash-completion.sh ]]; then
  source /opt/adguard-cli/bash-completion.sh
fi
