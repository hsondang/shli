# shli

A sourced shell function, not a script. It turns a plain-English request into one shell command using `claude -p --model haiku`. ⏎ then runs that command with `eval` in the user's current shell. See README.md for the full flow.

## Rules
- `shli.sh` must work in zsh 5.9, bash 5 and bash 3.2 (macOS `/bin/bash`), on macOS and Linux.
  - Avoid arrays: zsh indexes from 1, bash from 0.
  - Branch on `$ZSH_VERSION` where the shells differ: key reading, history, the `noglob` alias.
  - Put braces around a variable that sits right before a non-ASCII character (`${border}│`). bash 3.2 reads the first byte of `│` as part of the variable name.
  - No comments inside `$(...)`. zsh re-reads the block at run time, and an interactive zsh without `interactive_comments` treats `#` as a word. An apostrophe in such a comment also breaks bash's parse.
  - The bash-only `shli` function uses `function shli {`, not `shli() {`. zsh parses that branch too, and once the alias exists, re-sourcing the file would alias-expand it into a parse error.
- Everything shli itself prints goes to stderr. stdout belongs to the command it runs.
- The box must show exactly the text that `eval` runs. It is highlighted locally by `_shli_box`, not from model output. Per-part explanations come only from the `?` key's second call, because asking for them in the first call added about 2 s to every lookup.
- `_shli`'s local variables are visible to the eval'd command, so keep their names unlikely to collide. Never use zsh's special names as locals: `prompt` is PS1, and `status` is read-only.
- The first ask and `?` use `haiku`; retries use `${SHLI_RETRY_MODEL:-sonnet}`. Don't "fix" retries by raising Haiku's `--effort`. Measured on a failing retry: high, xhigh and max only thought longer (7 s, 11 s, 69 s) and returned the same command. Sonnet changed approach in about 7 s.
- A retry never re-runs a command unless its risk is `safe`. Anything else would repeat its changes. Commands run straight to the terminal, so they keep colors, live output and full-screen apps; output is only read when a retry re-runs one (`_shli_capture`).
- Keep these claude flags:
  - `--no-session-persistence`: no transcripts.
  - `--safe-mode`: the user's Claude hooks don't fire.
  - `--tools ""`
  - `--json-schema`

  Don't use `--bare`; it disables subscription login.
- The spinner works like this: `{ claude … >file; echo; } | _shli_spin`, with both sides in the foreground. Keep it that way.
  - Don't put claude in the background, and don't rely on `trap … INT`. Tested in zsh, bash 5 and bash 3.2: a background job ignores ctrl+c, traps inside `$(...)` never fire, and the shell can redraw its prompt before cleanup runs.
  - The echo is the "done" signal. zsh's and bash 3.2's `read -t` return 1 both on timeout and at end of input.
- Never edit `~/.mylib/shli.sh`. `.githooks/post-commit` overwrites it with the committed `shli.sh` on every commit.

## Test
- `zsh -n shli.sh && bash -n shli.sh`
- `zsh test/render.sh`, `bash test/render.sh`, `/bin/bash test/render.sh`. These check the box and colors, with no Claude calls and no time cost.
- `test/followup.exp zsh`, `test/followup.exp /usr/local/bin/bash`, `test/followup.exp /bin/bash`. These test the retry flow offline with a fake claude, including which model each call uses, in about 25 s each.
- `test/smoke.exp zsh`, `test/smoke.exp /usr/local/bin/bash`, `test/smoke.exp /bin/bash`. These make real Claude calls and take about 1 min each. Run them one at a time.
