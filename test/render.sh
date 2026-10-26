# Checks the command box without calling Claude: it must show exactly the command that will run,
# every line must line up, and each part must get the right color.
# Usage: zsh test/render.sh    bash test/render.sh    /bin/bash test/render.sh    (SHOW=1 also prints the boxes)

export LC_ALL=en_US.UTF-8
src="$(cd "$(dirname "$0")" && pwd)/../shli.sh"
. "$src"
# Sourcing it again is what an open tab does after an update; the shli alias already exists by then.
. "$src" || { echo "FAIL: shli.sh can't be sourced a second time"; exit 1; }
esc=$(printf '\033')
tmp="$(mktemp)"
fails=0

# check <command> [kind:text ...]: draws the box for <command> and checks it; each text must be drawn in its kind's color.
check() {
  local cmd=$1 missing="" color want got line w=""
  shift
  _shli_box "$cmd" "" 2>"$tmp"
  [ -n "$SHOW" ] && cat "$tmp"

  # Spaces are ignored: a wrapped line drops the space it wrapped at.
  got="$(sed "s/$esc\[[0-9;]*m//g; s/[│╭╮╰╯─]//g" "$tmp" | tr -d ' \t\n')"
  want="$(printf '%s' "$cmd" | tr -d ' \t\n')"
  [ "$got" = "$want" ] || { echo "FAIL [$cmd] box shows: $got"; fails=$((fails + 1)); }

  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed "s/$esc\[[0-9;]*m//g")"
    [ -z "$w" ] && w=${#line}
    [ ${#line} -eq $w ] || { echo "FAIL [$cmd] line is ${#line} wide, not $w: $line"; fails=$((fails + 1)); }
  done < "$tmp"

  for want in "$@"; do
    _shli_kind_color "${want%%:*}"
    grep -qF "${color}${want#*:}${esc}[0m" "$tmp" || { echo "FAIL [$cmd] '${want#*:}' is not drawn as ${want%%:*}"; fails=$((fails + 1)); }
  done
}

COLUMNS=80
check 'brew outdated --verbose' program:brew argument:outdated option:--verbose
check 'find ~ -type f -size +1G -exec ls -lh {} \; 2>/dev/null' program:find argument:~ option:-type 'argument:{}' 'argument:\;' 'operator:2>' argument:/dev/null
check 'lsof -nP -iTCP:3000 -sTCP:LISTEN | grep -v COMMAND' program:lsof option:-nP 'operator:|' program:grep argument:COMMAND
check 'echo "Kernel: $(uname -r)" && sw_vers -productVersion' program:echo 'argument:"Kernel: $(uname -r)"' 'operator:&&' program:sw_vers
check 'sudo rm -rf ./build; cd ~/Downloads&&ls' program:sudo program:rm option:-rf 'operator:;' program:cd 'operator:&&' program:ls
check 'ls nope 2>&1 >/dev/null | wc -l' 'operator:2>&1' 'operator:>' argument:/dev/null program:wc
check 'for f in *.log; do echo "$f"; done' program:for program:do program:echo program:done
check 'FOO=1 env -i bash -c "echo hi"' argument:FOO=1 program:env option:-i program:bash 'argument:"echo hi"'
check 'notarealprogram --flag' missing:notarealprogram option:--flag

# Narrow terminal: long commands wrap inside the box.
COLUMNS=30
check 'find . -name "*.tmp" -mtime +30 -print -exec rm {} \; 2>/dev/null' program:find
check 'echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' program:echo

# Spinner: draws frames until a line arrives on its stdin, then clears its line and stops.
{ sleep 2.3; echo; } | _shli_spin "Testing" 2>"$tmp"
frames=$(tr -cd '\r' < "$tmp" | wc -c | tr -d ' ')
[ "$frames" -ge 3 ] || { echo "FAIL spinner drew $frames frames"; fails=$((fails + 1)); }
grep -qF 'Testing…' "$tmp" || { echo "FAIL spinner did not show its label"; fails=$((fails + 1)); }
tail -c 4 "$tmp" | grep -qF "${esc}[K" || { echo "FAIL spinner did not clear its line at the end"; fails=$((fails + 1)); }
{ sleep 0.3; echo; } | _shli_spin "" 2>"$tmp"
[ -s "$tmp" ] && { echo "FAIL spinner drew without a label"; fails=$((fails + 1)); }

rm -f "$tmp"
shell="${ZSH_VERSION:+zsh $ZSH_VERSION}${BASH_VERSION:+bash $BASH_VERSION}"
if [ $fails -eq 0 ]; then
  echo "render: all passed ($shell)"
else
  echo "render: $fails failed ($shell)"
  exit 1
fi
