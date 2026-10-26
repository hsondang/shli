# shli: describe what you want in plain English, get one shell command, ⏎ to run it, esc to cancel.
# Source this file from ~/.zshrc or ~/.bashrc. Works in zsh and bash, on macOS and Linux.
# Needs: claude (logged in) and jq.

_shli_schema='{"type":"object","properties":{"cmd":{"type":"string"},"explain":{"type":"string"},"risk":{"type":"string","enum":["safe","caution","danger"]}},"required":["cmd","explain","risk"]}'
_shli_parts_schema='{"type":"object","properties":{"parts":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"kind":{"type":"string","enum":["program","subcommand","option","argument","operator"]},"explain":{"type":"string"}},"required":["text","kind","explain"]}}},"required":["parts"]}'

# Waits for a line on stdin. Meanwhile, if label $1 isn't empty, draws a Claude Code-style spinner on
# stderr: a pulsing sparkle, a lighter band sweeping across "$1…", and the seconds waited so far.
_shli_spin() {
  local label=$1 line i=0 start=$SECONDS glyph p a b tick=0.1
  local orange=$'\033[38;5;173m' light=$'\033[38;5;216m' dim=$'\033[2m' reset=$'\033[0m'
  [ -n "$BASH_VERSION" ] && [ "${BASH_VERSINFO[0]}" -lt 4 ] && tick=1  # bash 3.2 can't wait less than a second
  # In zsh, read can't tell "nothing yet" from "pipe closed", so give up after about 5 minutes either way.
  while [ $i -lt 3000 ]; do
    IFS= read -r -t $tick line && break
    i=$((i + 1))
    [ -z "$label" ] && continue
    case $((i % 10)) in
      0) glyph='·' ;; 1|9) glyph='✢' ;; 2|8) glyph='✳' ;; 3|7) glyph='✶' ;; 4|6) glyph='✻' ;; 5) glyph='✽' ;;
    esac
    # The band is 3 letters wide and spends a few frames off either end, so the sweep pauses between passes.
    p=$((i % (${#label} + 8) - 4))
    a=$p
    [ $a -lt 0 ] && a=0
    b=$((p + 3))
    [ $b -gt ${#label} ] && b=${#label}
    [ $b -lt $a ] && b=$a
    printf '\r%s%s %s%s%s%s%s…%s %s(%ds · ctrl+c to cancel)%s\033[K' \
      "$orange" "$glyph" "${label:0:$a}" "$light" "${label:$a:$((b - a))}" "$orange" "${label:$b}" "$reset" \
      "$dim" $((SECONDS - start)) "$reset" >&2
  done
  [ -n "$label" ] && printf '\r\033[K' >&2
}

# Prints a model alias the way the spinner shows it: haiku -> Haiku. Full model ids are printed as they are.
_shli_model_name() {
  case $1 in
    haiku) echo Haiku ;;
    sonnet) echo Sonnet ;;
    opus) echo Opus ;;
    *) echo "$1" ;;
  esac
}

# One Claude call: $1 model, $2 spinner label, $3 system prompt, $4 JSON schema, $5 prompt.
# Sets the caller's $answer to the structured answer as JSON, or prints the reason in red and returns 1.
_shli_ask() {
  local model=$1 label=$2 outfile errfile out reason
  [ -t 2 ] || label=""
  outfile="$(mktemp)"
  errfile="$(mktemp)"
  # claude writes to files; the pipe only carries the echo that tells the spinner claude is done.
  # Both sides of the pipe run in the foreground, so ctrl+c stops claude and the spinner together,
  # leaves nothing running, and the shell prints no job messages.
  # The prompt goes in on stdin so a request starting with "-" can't be read as a claude flag.
  {
    claude -p --model "$model" --no-session-persistence --safe-mode --tools "" \
      --system-prompt "$3" --output-format json --json-schema "$4" <<< "$5" >"$outfile" 2>"$errfile"
    echo
  } | _shli_spin "$label"
  # Nothing on stdout or stderr means ctrl+c stopped claude. zsh and bash 5 never get here then; bash 3.2 does.
  if [ ! -s "$outfile" ] && [ ! -s "$errfile" ]; then
    printf '\r\033[K\033[2mcancelled\033[0m\n' >&2
    rm -f "$outfile" "$errfile"
    return 1
  fi
  out="$(cat "$outfile")"
  if jq -e '.is_error == false and .structured_output != null' <<< "$out" >/dev/null 2>&1; then
    answer="$(jq -c '.structured_output' <<< "$out")"
    rm -f "$outfile" "$errfile"
    return 0
  fi
  reason="$(jq -r '.result // empty' <<< "$out" 2>/dev/null)"
  [ -z "$reason" ] && reason="$(cat "$errfile")"
  printf '\033[31mshli: no answer (%s)\033[0m\n' "${reason:-claude gave no output}" >&2
  rm -f "$outfile" "$errfile"
  return 1
}

# Sets $color to the escape code for a kind of command part. The box and the explanation list share these.
_shli_kind_color() {
  case $1 in
    program) color=$'\033[1;32m' ;;
    subcommand) color=$'\033[32m' ;;
    option) color=$'\033[36m' ;;
    argument) color=$'\033[33m' ;;
    operator) color=$'\033[35m' ;;
    missing) color=$'\033[1;31m' ;;
    *) color="" ;;
  esac
}

# Adds $1 in color $2 to the box _shli_box is drawing, starting a new box line when it doesn't fit.
_shli_put() {
  local text=$1 color=$2 room
  while [ -n "$text" ]; do
    if [ $col -eq 0 ]; then
      text=${text#"${text%%[![:space:]]*}"}  # a wrapped line doesn't start with spaces
      [ -z "$text" ] && return
    fi
    room=$((width - col))
    if [ ${#text} -le $room ]; then
      line+="$color$text${color:+$reset}"
      col=$((col + ${#text}))
      return
    fi
    if [ $col -gt 0 ] && [ ${#text} -le $width ]; then
      _shli_endline  # move the whole word to the next line
      continue
    fi
    line+="$color${text:0:$room}$reset"  # longer than a full line: split it
    col=$width
    text=${text:$room}
    _shli_endline
  done
}

# Variables next to box characters need braces: bash 3.2 reads the first byte of "│" as part of the name.
_shli_endline() {
  out+="${border}│${reset} ${line}$(printf '%*s' $((width - col)) '') ${border}│${reset}"$'\n'
  line=""
  col=0
}

# Draws command $1 in a box on stderr, syntax-highlighted; the border gets color $2.
# Programs that don't exist on this machine are drawn red and added to the caller's $missing.
_shli_box() {
  local cmd=$1 border=$2 reset=$'\033[0m'
  local width=$((${COLUMNS:-80} - 4))
  [ ${#cmd} -lt $width ] && width=${#cmd}
  [ $width -lt 1 ] && width=1
  local bar out line="" col=0
  bar="$(printf '%*s' $((width + 2)) '')"
  bar=${bar// /─}
  out="${border}╭${bar}╮${reset}"$'\n'

  # Split the command into spaces, operators and words, roughly the way the shell does.
  # cmdpos: the next word is in command position. target: the next word is a redirection's file.
  local i=0 j n=${#cmd} c tok kind color depth cmdpos=1 target=0
  while [ $i -lt $n ]; do
    c=${cmd:$i:1}

    case $c in
      [[:space:]])
        j=$i
        while [ $j -lt $n ]; do
          case ${cmd:$j:1} in [[:space:]]) j=$((j + 1)) ;; *) break ;; esac
        done
        _shli_put "${cmd:$i:$((j - i))}" ""
        i=$j
        continue
        ;;
    esac

    # Redirections: >file, 2>/dev/null, >>log, 2>&1, &>file
    j=$i
    while [ $j -lt $n ]; do
      case ${cmd:$j:1} in [0-9]) j=$((j + 1)) ;; *) break ;; esac
    done
    if [ "${cmd:$j:1}" = '<' ] || [ "${cmd:$j:1}" = '>' ] || { [ $j -eq $i ] && [ "${cmd:$i:2}" = '&>' ]; }; then
      [ "${cmd:$j:1}" = '&' ] && j=$((j + 1))
      j=$((j + 1))
      case ${cmd:$j:1} in '<'|'>') j=$((j + 1)) ;; esac
      if [ "${cmd:$j:1}" = '&' ]; then
        j=$((j + 1))
        while [ $j -lt $n ]; do
          case ${cmd:$j:1} in [0-9]|-) j=$((j + 1)) ;; *) break ;; esac
        done
      else
        target=1
      fi
      _shli_kind_color operator
      _shli_put "${cmd:$i:$((j - i))}" "$color"
      i=$j
      continue
    fi

    case $c in
      '|'|'&'|';'|'('|')')
        tok=$c
        case ${cmd:$i:2} in '||'|'&&'|';;'|'|&') tok=${cmd:$i:2} ;; esac
        _shli_kind_color operator
        _shli_put "$tok" "$color"
        i=$((i + ${#tok}))
        cmdpos=1
        continue
        ;;
    esac

    # A word runs to the next unquoted space or operator; $(...) can contain both.
    j=$i
    depth=0
    while [ $j -lt $n ]; do
      case ${cmd:$j:1} in
        \\) j=$((j + 1)) ;;
        \')
          j=$((j + 1))
          while [ $j -lt $n ] && [ "${cmd:$j:1}" != "'" ]; do j=$((j + 1)); done
          ;;
        \")
          j=$((j + 1))
          while [ $j -lt $n ] && [ "${cmd:$j:1}" != '"' ]; do
            [ "${cmd:$j:1}" = \\ ] && j=$((j + 1))
            j=$((j + 1))
          done
          ;;
        \`)
          j=$((j + 1))
          while [ $j -lt $n ] && [ "${cmd:$j:1}" != '`' ]; do j=$((j + 1)); done
          ;;
        '$') [ "${cmd:$((j + 1)):1}" = '(' ] && { depth=$((depth + 1)); j=$((j + 1)); } ;;
        '(') [ $depth -gt 0 ] || break; depth=$((depth + 1)) ;;
        ')') [ $depth -gt 0 ] || break; depth=$((depth - 1)) ;;
        [[:space:]]|'|'|'&'|';'|'<'|'>') [ $depth -gt 0 ] || break ;;
      esac
      j=$((j + 1))
    done
    tok=${cmd:$i:$((j - i))}
    i=$j

    if [ $target -eq 1 ]; then
      kind=argument
      target=0
    elif [ $cmdpos -eq 1 ]; then
      case $tok in
        [A-Za-z_]*=*) kind=argument ;;  # VAR=value before the command
        -?*) kind=option ;;             # option of sudo, env, xargs...
        *)
          kind=program
          cmdpos=0
          case $tok in
            *\'*|*\"*|*\$*|*\`*|*\\*|*/*|'~'*) ;;  # quoted, computed or a path: can't look it up
            *) command -v "$tok" >/dev/null 2>&1 || { kind=missing; missing="$missing $tok"; } ;;
          esac
          case $tok in  # these run the command that follows them
            sudo|env|nohup|time|nice|exec|command|xargs|watch|if|then|else|elif|while|until|do|'!'|'{') cmdpos=1 ;;
          esac
          ;;
      esac
    else
      case $tok in -?*) kind=option ;; *) kind=argument ;; esac
    fi
    _shli_kind_color $kind
    _shli_put "$tok" "$color"
  done
  [ $col -gt 0 ] && _shli_endline
  out+="${border}╰${bar}╯${reset}"
  printf '%s\n' "$out" >&2
}

# Asks Haiku what each part of command $1 does ($2 shell, $3 OS) and prints one line per part.
_shli_explain() {
  local answer rows kind text explain color w=0
  _shli_ask haiku "Explaining" "Explain a $2 command on $3, part by part. \
parts: the command split into its shell words and operators, in order, each text exactly as written in the command. \
kind: program (a command being run), subcommand (like outdated in brew outdated), option (a flag, with its value if attached), \
argument (file, pattern or value), operator (pipe, &&, ;, redirection). \
explain: 8 words max, what this part does here." "$_shli_parts_schema" "$1" || return 1
  rows="$(jq -r '.parts[] | "\(.kind)\u001f\(.text | gsub("\n"; " "))\u001f\(.explain)"' <<< "$answer")"
  while IFS=$'\x1f' read -r kind text explain; do
    [ ${#text} -gt $w ] && w=${#text}
  done <<< "$rows"
  [ $w -gt 20 ] && w=20
  while IFS=$'\x1f' read -r kind text explain; do
    [ -z "$text" ] && continue
    _shli_kind_color "$kind"
    printf '  %s%-*s\033[0m  %s\n' "$color" "$w" "$text" "$explain" >&2
  done <<< "$rows"
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

# Shows the caller's $cmd in its box with $explain and the risk warning, then waits for ⏎ / y / ? / esc.
# Returns 0 to run it, 1 if cancelled. Also reads the caller's $risk, $sh and $os.
_shli_confirm() {
  local reset=$'\033[0m' red=$'\033[31m' border=$'\033[2m' run_key="⏎" missing="" key explained=""
  case $risk in
    caution) border=$'\033[33m' ;;
    danger) border=$'\033[31m' run_key="y" ;;
  esac
  _shli_box "$cmd" "$border"
  printf '%s\n' "$explain" >&2
  [ "$risk" = danger ] && printf '%s⚠ destructive%s\n' "$red" "$reset" >&2
  [ -n "$missing" ] && printf '%snot found:%s%s\n' "$red" "$missing" "$reset" >&2
  printf '\033[2m%s run · ? explain · esc cancel\033[0m' "$run_key" >&2

  while :; do
    _shli_readkey
    case $key in
      $'\e')
        _shli_drain
        printf '\r\033[K\033[2mcancelled\033[0m\n' >&2
        return 1
        ;;
      ""|$'\n'|$'\r')
        [ "$risk" != danger ] && break
        ;;
      y|Y)
        break
        ;;
      '?')
        [ -n "$explained" ] && continue
        explained=1
        printf '\r\033[K' >&2
        _shli_explain "$cmd" "$sh" "$os"
        printf '\033[2m%s run · esc cancel\033[0m' "$run_key" >&2
        ;;
    esac
  done
  printf '\r\033[K' >&2
}

# After a command runs, offers a retry for $SHLI_FOLLOWUP_SECONDS (default 30) with a countdown.
# Returns 0 to retry, with what the user typed in the caller's $feedback (empty if they only pressed ⏎).
# Returns 1 on esc, on timeout, or on any other key.
_shli_followup() {
  local key left=${SHLI_FOLLOWUP_SECONDS:-30}
  feedback=""
  while [ "$left" -gt 0 ]; do
    printf "\r\033[2m↻ Not right? ⏎ to retry, or type what's wrong · esc (%ds)\033[0m\033[K" "$left" >&2
    if [ -n "$ZSH_VERSION" ]; then
      read -sk1 -t 1 key || { left=$((left - 1)); continue; }
    else
      IFS= read -rsn1 -t 1 key || { left=$((left - 1)); continue; }
    fi
    case $key in
      ""|$'\n'|$'\r')
        printf '\r\033[K' >&2
        return 0
        ;;
      [[:print:]])
        printf '\r\033[K' >&2
        _shli_readline "$key"
        return 0
        ;;
      $'\e')
        _shli_drain
        break
        ;;
      *)
        break
        ;;
    esac
  done
  printf '\r\033[K' >&2
  return 1
}

# Reads a line into the caller's $feedback, starting with the key the user already typed ($1).
_shli_readline() {
  feedback=$1
  if [ -n "$ZSH_VERSION" ]; then
    vared -p '› ' feedback
  elif [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    IFS= read -re -i "$1" -p '› ' feedback
  else
    local rest
    IFS= read -re -p "› $1" rest  # bash 3.2 can't pre-fill the line, so the first key can't be deleted
    feedback=$1$rest
  fi
}

# Re-runs read-only command $1 in a subshell, with no input, and prints what it wrote (ANSI codes
# stripped, at most 40 lines of 400 characters) so it can be sent back to Haiku.
_shli_capture() {
  local log esc
  log="$(mktemp)"
  esc=$(printf '\033')
  { eval "$1" </dev/null >"$log" 2>&1; echo; } | _shli_spin "Re-running it to read the output"
  sed "s/${esc}\[[0-9;?]*[A-Za-z]//g" "$log" | tr -d '\r' | tail -n 40 | cut -c1-400
  rm -f "$log"
}

_shli() {
  local request="$*"
  if [ -z "$request" ]; then
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
Return the single best command. \
cmd: a single line that runs as-is in this shell on this OS (BSD flags on macOS, GNU flags on Linux), \
no markdown, no comments; prefer tools that ship with the OS; when no path is given, use the current directory. \
explain: 12 words max. \
risk: safe = read-only; caution = changes files or settings but is recoverable; \
danger = deletes data, needs sudo, kills processes, or is irreversible. \
If earlier attempts are listed, they gave the wrong result: use what they printed and what the user says \
to find out why, and don't propose a command that already failed."

  # Each pass: ask, confirm, run, then offer a retry that sends back every attempt so far.
  # Retries go to a stronger model: on a failed wifi lookup, Haiku at higher effort only thought longer
  # (up to 69 s) and repeated itself, while Sonnet tried a new approach in the same ~7 s.
  local model=haiku message=$request attempts="" tries=0 answer risk cmd explain exit_code feedback output
  while :; do
    _shli_ask "$model" "Asking $(_shli_model_name "$model")" "$sys" "$_shli_schema" "$message" || return 1
    IFS=$'\x1f' read -r risk cmd explain <<< "$(jq -r '"\(.risk)\u001f\(.cmd | gsub("\n"; " "))\u001f\(.explain)"' <<< "$answer")"
    if [ -z "$cmd" ]; then
      printf '\033[31mshli: no answer (empty command)\033[0m\n' >&2
      return 1
    fi
    _shli_confirm || return 1

    # Put the real command in shell history so ↑ brings it back, then run it in this shell.
    if [ -n "$ZSH_VERSION" ]; then
      print -s -- "$cmd"
    else
      history -s -- "$cmd"
    fi
    eval "$cmd"
    exit_code=$?

    { [ -t 0 ] && [ -t 2 ]; } || return $exit_code
    _shli_followup || return $exit_code

    # Read-only commands are run again to read their output; anything else would repeat its changes.
    if [ "$risk" = safe ]; then
      output="$(_shli_capture "$cmd")"
      [ -z "$output" ] && output="(no output)"
    else
      output="(not captured: this command changes things, so shli did not run it again)"
    fi
    tries=$((tries + 1))
    attempts="$attempts
Attempt $tries
Command: $cmd
Exit code: $exit_code
Output:
$output
What the user says is wrong: ${feedback:-(nothing more, just that the result is wrong)}
"
    message="Request: $request
$attempts"
    model=${SHLI_RETRY_MODEL:-sonnet}
  done
}

if [ -n "$ZSH_VERSION" ]; then
  alias shli='noglob _shli'  # so "?" and "*" in a request aren't treated as file globs
else
  # "function name" form: zsh parses this branch too, and in a shell that already has the alias,
  # "shli() {" would be alias-expanded into a parse error when the file is sourced again.
  function shli { _shli "$@"; }
fi
