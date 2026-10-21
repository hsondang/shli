#!/bin/sh
# One-time setup: deploy shli to ~/.mylib and load it from your shell's rc file. Safe to re-run.
cd "$(dirname "$0")" || exit 1
line='[ -f ~/.mylib/shli.sh ] && source ~/.mylib/shli.sh  # shli'

git config core.hooksPath .githooks
echo "shli: deploy-on-commit turned on"
if git rev-parse -q --verify HEAD >/dev/null; then
  .githooks/post-commit
else
  echo "shli: no commits yet, the first commit will deploy"
fi

case "$SHELL" in
  */bash) rc="$HOME/.bashrc" ;;
  *) rc="$HOME/.zshrc" ;;
esac
if grep -qxF "$line" "$rc" 2>/dev/null; then
  echo "shli: $rc already loads shli"
else
  # Start on a fresh line if the file doesn't end with a newline.
  [ -s "$rc" ] && [ -n "$(tail -c1 "$rc")" ] && echo >> "$rc"
  echo "$line" >> "$rc"
  echo "shli: added the source line to $rc"
fi
echo "shli: open a new tab, or run: source ~/.mylib/shli.sh"
