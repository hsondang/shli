# shli: describe what you want in plain English, get one shell command, ⏎ to run it, esc to cancel.
# Source this file from ~/.zshrc or ~/.bashrc. Works in zsh and bash, on macOS and Linux.
# Needs: claude (logged in) and jq.

_shli_schema='{"type":"object","properties":{"candidates":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"object","properties":{"cmd":{"type":"string"},"explain":{"type":"string"},"risk":{"type":"string","enum":["safe","caution","danger"]}},"required":["cmd","explain","risk"]}}},"required":["candidates"]}'

# Prints the program a command line starts with, skipping sudo/env/VAR=value prefixes.
_shli_prog() {
  local word rest=$1
  while [ -n "$rest" ]; do
    read -r word rest <<< "$rest"
    case $word in
      sudo|env|nohup|time|command|exec|-*|*=*) continue ;;
    esac
    printf '%s' "$word"
    return
  done
}

# Reads one keypress into $key.
_shli_readkey() {
  if [ -n "$ZSH_VERSION" ]; then
    read -sk1 key
  else
    IFS= read -rsn1 key
  fi
}

# Swallows the rest of a multi-byte key (arrow keys send ESC [ A) so it doesn't leak into the prompt.
_shli_drain() {
  local junk
  if [ -n "$ZSH_VERSION" ]; then
    while read -t 0.05 -sk1 junk; do :; done
  elif [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    while IFS= read -rsn1 -t 0.05 junk; do :; done
  else
    while IFS= read -rsn1 -t 1 junk; do :; done  # bash 3.2 (macOS /bin/bash) has no fractional timeout
  fi
}

_shli() {
  local prompt="$*"
  if [ -z "$prompt" ]; then
    echo "usage: shli <what you want to do>    e.g. shli check my kernel and os version" >&2
    return 2
  fi

  local dep
  for dep in claude jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      printf '\033[31mshli: %s not found\033[0m\n' "$dep" >&2
      return 1
    fi
  done

  local os sh
  case "$(uname -s)" in
    Darwin) os="macOS $(sw_vers -productVersion)" ;;
    Linux) os="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")" ;;
    *) os="$(uname -s)" ;;
  esac
  os="$os ($(uname -srm))"
  if [ -n "$ZSH_VERSION" ]; then sh="zsh $ZSH_VERSION"; else sh="bash $BASH_VERSION"; fi

  local sys="You turn a request into a shell command for this machine: $os, shell $sh. \
Return 1-3 candidates, best first, each using a different tool where possible. \
cmd: a single line that runs as-is in this shell on this OS (BSD flags on macOS, GNU flags on Linux), \
no markdown, no comments; prefer tools that ship with the OS; when no path is given, use the current directory. \
explain: 12 words max. \
risk: safe = read-only; caution = changes files or settings but is recoverable; \
danger = deletes data, needs sudo, kills processes, or is irreversible."

  # The prompt goes in on stdin so a request starting with "-" can't be read as a claude flag.
  local out errfile rc
  errfile="$(mktemp)"
  printf '\033[2masking haiku…\033[0m' >&2
  out="$(printf '%s' "$prompt" | claude -p --model haiku --no-session-persistence --safe-mode --tools "" \
    --system-prompt "$sys" --output-format json --json-schema "$_shli_schema" 2>"$errfile")"
  rc=$?
  printf '\r\033[K' >&2

  local candidates
  candidates="$(jq -r 'select(.is_error == false) | .structured_output.candidates[]?
    | "\(.risk)\u001f\(.cmd | gsub("\n"; " "))\u001f\(.explain)"' <<< "$out" 2>/dev/null)"
  if [ $rc -ne 0 ] || [ -z "$candidates" ]; then
    local reason
    reason="$(jq -r '.result // empty' <<< "$out" 2>/dev/null)"
    [ -z "$reason" ] && reason="$(cat "$errfile")"
    printf '\033[31mshli: no command (%s)\033[0m\n' "${reason:-claude exited with $rc}" >&2
    rm -f "$errfile"
    return 1
  fi
  rm -f "$errfile"

  # Take the first candidate whose program exists on this machine; fall back to the first one.
  local risk cmd explain first_risk="" first_cmd="" first_explain="" missing=""
  while IFS=$'\x1f' read -r risk cmd explain; do
    [ -z "$cmd" ] && continue
    if [ -z "$first_cmd" ]; then
      first_risk=$risk first_cmd=$cmd first_explain=$explain
    fi
    command -v "$(_shli_prog "$cmd")" >/dev/null 2>&1 && break
    cmd=""
  done <<< "$candidates"
  if [ -z "$cmd" ]; then
    risk=$first_risk cmd=$first_cmd explain=$first_explain
    missing="$(_shli_prog "$cmd")"
  fi

  local reset=$'\033[0m' dim=$'\033[2m' red=$'\033[31m'
  local color=$'\033[1m' hint="⏎ run · esc cancel"
  case $risk in
    caution) color=$'\033[1;33m' ;;
    danger) color=$'\033[1;31m' hint="y run · esc cancel" ;;
  esac
  printf '%s%s%s\n' "$color" "$cmd" "$reset" >&2
  printf '%s%s%s\n' "$dim" "$explain" "$reset" >&2
  [ "$risk" = danger ] && printf '%s⚠ destructive%s\n' "$red" "$reset" >&2
  [ -n "$missing" ] && printf '%snot found: %s%s\n' "$red" "$missing" "$reset" >&2
  printf '%s%s%s' "$dim" "$hint" "$reset" >&2

  local key
  while :; do
    _shli_readkey
    case $key in
      $'\e')
        _shli_drain
        printf '\r\033[K%scancelled%s\n' "$dim" "$reset" >&2
        return 1
        ;;
      ""|$'\n'|$'\r')
        [ "$risk" != danger ] && break
        ;;
      y|Y)
        break
        ;;
    esac
  done
  printf '\r\033[K' >&2

  # Put the real command in shell history so ↑ brings it back, then run it in this shell.
  if [ -n "$ZSH_VERSION" ]; then
    print -s -- "$cmd"
  else
    history -s -- "$cmd"
  fi
  eval "$cmd"
}

if [ -n "$ZSH_VERSION" ]; then
  alias shli='noglob _shli'  # so "?" and "*" in a request aren't treated as file globs
else
  shli() { _shli "$@"; }
fi
