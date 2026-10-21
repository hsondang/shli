# shli

A sourced shell function, not a script. It turns a plain-English request into one shell command using `claude -p --model haiku`. ⏎ then runs that command with `eval` in the user's current shell. See README.md for the full flow.

## Rules
- `shli.sh` must work in zsh 5.9, bash 5 and bash 3.2 (macOS `/bin/bash`), on macOS and Linux.
  - Avoid arrays: zsh indexes from 1, bash from 0.
  - Branch on `$ZSH_VERSION` where the shells differ: key reading, history, the `noglob` alias.
- Everything shli itself prints goes to stderr. stdout belongs to the command it runs.
- `_shli`'s local variables are visible to the eval'd command, so keep their names unlikely to collide.
- Keep these claude flags:
  - `--no-session-persistence`: no transcripts.
  - `--safe-mode`: the user's Claude hooks don't fire.
  - `--tools ""`
  - `--json-schema`

  Don't use `--bare`; it disables subscription login.
- Never edit `~/.mylib/shli.sh`. `.githooks/post-commit` overwrites it with the committed `shli.sh` on every commit.

## Test
- `zsh -n shli.sh && bash -n shli.sh`
- `test/smoke.exp zsh`, `test/smoke.exp /usr/local/bin/bash`, `test/smoke.exp /bin/bash`. These make real Claude calls and take about 1 min each.
