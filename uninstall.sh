#!/bin/sh
# Undoes install.sh: stops loading shli, removes the deployed copy, turns off deploy-on-commit. Safe to re-run.
cd "$(dirname "$0")" || exit 1
line='[ -f ~/.mylib/shli.sh ] && source ~/.mylib/shli.sh  # shli'

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  grep -qxF "$line" "$rc" 2>/dev/null || continue
  cp "$rc" "$rc.shli-bak"
  tmp=$(mktemp)
  grep -vxF "$line" "$rc" > "$tmp"
  cat "$tmp" > "$rc"  # cat, not mv, keeps the file's permissions and any symlink
  rm -f "$tmp"
  echo "shli: removed the source line from $rc (backup: $rc.shli-bak)"
done

if [ -f "$HOME/.mylib/shli.sh" ]; then
  rm "$HOME/.mylib/shli.sh"
  echo "shli: removed ~/.mylib/shli.sh"
fi

if [ "$(git config core.hooksPath)" = .githooks ]; then
  git config --unset core.hooksPath
  echo "shli: deploy-on-commit turned off"
fi

echo "shli: tabs that are already open still have it loaded; to unload there:"
echo "  zsh:  unalias shli; unfunction _shli _shli_prog _shli_readkey _shli_drain"
echo "  bash: unset -f shli _shli _shli_prog _shli_readkey _shli_drain"
