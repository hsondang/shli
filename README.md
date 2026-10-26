# shli

*Pronounced "shee-el-ai", like CLI.*

Describe what you want in plain English. shli asks Claude Haiku for one shell command that fits your OS and shell, shows it, and runs it when you press ⏎.

```
$ shli check if any homebrew packages need updating
╭─────────────────────────╮
│ brew outdated --verbose │
╰─────────────────────────╯
Lists outdated Homebrew formulae and casks with installed and latest versions.
⏎ run · ? explain · esc cancel
```

Press `?` to see what each part does:

```
  brew       Homebrew package manager
  outdated   Lists packages with newer versions available
  --verbose  Shows installed and latest version numbers
⏎ run · esc cancel
```

It runs on your existing Claude subscription through the `claude` CLI. You don't need an API key, and nothing is saved to Claude's session history.

## Requirements

- `claude` CLI, logged in
- `jq`: ships with macOS 15+; on Linux, `apt install jq` / `dnf install jq`
- zsh or bash (3.2 and up), on macOS or Linux

## Install

Clone or copy this repo, then run:

```bash
./install.sh
```

Open a new terminal tab and it's ready. `install.sh` is safe to re-run. It:

1. Turns on deploy-on-commit (`git config core.hooksPath .githooks`).
2. Copies the committed `shli.sh` to `~/.mylib/shli.sh`.
3. Adds this line to `~/.zshrc`, or to `~/.bashrc` if your shell is bash:
   `[ -f ~/.mylib/shli.sh ] && source ~/.mylib/shli.sh  # shli`

## Usage

```
shli <what you want to do>
```

Quotes are optional, and `?` / `*` are fine even in zsh: `shli what is using port 3000?`

While Haiku works, a Claude Code-style spinner shows a pulsing ✻ and a shimmer across the label, plus the seconds so far, like `✻ Asking Haiku… (3s · ctrl+c to cancel)`. ctrl+c stops it and the `claude` call together. On macOS's built-in bash 3.2, which can't wait less than a second, the spinner ticks once per second.

| Key | Does |
|---|---|
| ⏎ | Run the command |
| y | Run it. A destructive command needs `y`; ⏎ is ignored. |
| ? | Explain each part of the command (one more Claude call, only when you press it) |
| esc | Cancel |

The command is syntax-highlighted:

| Color | Part |
|---|---|
| bold green | program (`brew`, `find`, `grep` after a `\|`) |
| bold red | program that isn't installed here, also listed under `not found:` |
| cyan | option (`-l`, `--verbose`) |
| yellow | argument (files, patterns, values, quoted strings) |
| magenta | operator or redirection (`\|`, `&&`, `;`, `2>/dev/null`) |
| green | subcommand (only in the `?` explanation, like `outdated` in `brew outdated`) |

The box's border tells you the risk:
- **gray**: read-only.
- **yellow**: changes something you can undo.
- **red, plus ⚠ destructive**: deletes data, uses sudo, kills processes, or can't be undone.

The command runs in **your current shell**, so `cd`, `export` and your aliases work. It's also added to your shell history, so ↑ brings it back next time.

### When the result is wrong

After the command runs, shli waits 30 seconds for a retry:

```
SSID: You are not associated with an AirPort network.
↻ Not right? ⏎ to retry, or type what's wrong · esc (27s)
```

| You | shli |
|---|---|
| type what's wrong, then ⏎ | asks Haiku again, with your note |
| ⏎ | asks Haiku again, without a note |
| esc, any other key, or wait 30 s | finishes |

A retry goes to **Sonnet** instead of Haiku. The spinner says `Asking Sonnet…`. Sonnet gets your original request plus every attempt so far: the command, its exit code, its output and your note. It's asked for a different command, which shows in the usual box, so nothing runs until you press ⏎.

Why Sonnet instead of letting Haiku think harder? Haiku already thinks on its own; at its default effort it used about 550 thinking tokens on a retry. On a wifi lookup that kept failing, raising its effort made it think 1.5× to 28× longer, taking up to 69 s, and it still returned the same broken command. Sonnet tried a new approach in the same ~7 s. Set `SHLI_RETRY_MODEL` to use another model for retries, for example `opus` or `haiku`.

Your terminal shows output directly, so shli doesn't see it while the command runs. When you ask for a retry, a read-only (gray-border) command is quietly run once more to read its output. A command that changes things (yellow or red border) is never run again, so Haiku only gets its exit code and your note.

Set `SHLI_FOLLOWUP_SECONDS` to change the 30 s wait.

Some things can't be fixed by a better command. On macOS 15, for example, `networksetup`, `system_profiler` and `ipconfig getsummary` all hide the Wi-Fi name from terminal commands, so tell the retry what you see (such as "it says redacted").

## How it works

1. **Context.** shli reads your OS and version (`sw_vers` on macOS, `/etc/os-release` on Linux), `uname -srm`, and your shell and its version. This takes about 25 ms per call, so nothing is cached.
2. **One call to Haiku.** The request goes in on stdin, so a request starting with `-` can't be mistaken for a flag. `claude` writes its answer to a temp file and is piped into the spinner, which stops when `claude` finishes. Both sides of the pipe run in the foreground, so ctrl+c cleanly stops both.

   ```
   claude -p --model haiku --no-session-persistence --safe-mode --tools "" \
     --system-prompt "$sys" --output-format json --json-schema "$schema"
   ```

   | Flag | What it does | Why |
   |---|---|---|
   | `-p` | Answers one prompt and exits | No chat interface |
   | `--model haiku` | Uses the latest Haiku | Fast and cheap |
   | `--no-session-persistence` | Saves no transcript | Keeps one-off lookups out of your Claude history |
   | `--safe-mode` | Skips your hooks, plugins, MCP servers and CLAUDE.md; login still works | Your Claude hooks don't fire on every lookup |
   | `--tools ""` | Claude gets no tools | It can only answer; it can't run or read anything |
   | `--system-prompt` | Replaces Claude Code's long default instructions | Short and on-task: your OS, shell and the rules |
   | `--json-schema` | Forces the answer into a fixed shape | Parsed reliably with `jq`, no stray markdown |

   It asks for the single best command. shli reads only `structured_output`:

   ```json
   {"cmd": "brew outdated --verbose", "explain": "Lists outdated Homebrew formulae and casks with installed and latest versions.", "risk": "safe"}
   ```

   Don't swap in `--bare`. It's faster to start, but it turns off subscription login.

3. **Draw it.** The box and colors come from a small tokenizer in `shli.sh`, so they cost no model time.
   - It understands quotes, `$(...)`, operators and redirections.
   - Each program is checked with `command -v`, which also sees your aliases and functions.
   - The box shows exactly the text that will run. It wraps at the terminal width.
4. **Explain on demand.** `?` sends the command back to Haiku and asks for one line per part. That call takes about 4–6 s and happens only when you ask. Asking for the parts in the first call made every lookup about 2 s slower on average (6.8 s vs 4.7 s over 5 requests), which is why it's a separate key.
5. **Confirm, then run.** Press ⏎ (or `y`), and the command goes into shell history and then `eval` in your shell.
6. **Retry.** If you ask for one, shli adds the attempt to a running log and sends the request and that log to `$SHLI_RETRY_MODEL` (default `sonnet`). The same system prompt tells the model to work out from the attempts why they failed, and not to repeat a command that already failed. A new `shli` request starts with Haiku again. `?` explanations always use Haiku.

Each request takes about **4–5 s**: 2–3 s for the model and about 2 s for `claude` to start.

## Development

- Edit `shli.sh` here, never `~/.mylib/shli.sh`. Every commit overwrites that copy.
- Every commit deploys the **committed** `shli.sh` to `~/.mylib/shli.sh`, through `.githooks/post-commit`. The first line of the deployed file names the commit. New tabs get the new version; in an open tab, run `source ~/.mylib/shli.sh`.
- To try uncommitted changes, run `source ./shli.sh` in a tab.
- Checks:
  - `zsh -n shli.sh && bash -n shli.sh`
  - `zsh test/render.sh`, `bash test/render.sh`, `/bin/bash test/render.sh`. This checks the box, colors and spinner without calling Claude: the box must show exactly the command, its lines must line up, each part must get the right color, and the spinner must animate and then clear its line. `SHOW=1` also prints the boxes.
  - `test/followup.exp zsh`, `test/followup.exp /bin/bash`, `test/followup.exp /usr/local/bin/bash`. This tests the retry flow offline with a fake `claude` that hands out canned answers and saves what shli sent it. It checks that a retry carries the command, output, exit code and your note; that only read-only commands are re-run; and that the countdown ends by itself. It also checks that the first ask uses Haiku and retries use Sonnet, or `$SHLI_RETRY_MODEL`. It takes about 25 s and makes no Claude calls.
  - `test/smoke.exp zsh`, `test/smoke.exp /bin/bash`, `test/smoke.exp /usr/local/bin/bash`. This drives shli in a real terminal: ⏎, esc, arrow keys, `?`, the destructive-command guard and `cd`. It makes 8 real Claude calls inside an empty temp folder, and checks that ctrl+c leaves nothing running. Run the shells one at a time.

## Uninstall

```bash
./uninstall.sh
```

It removes the source line from `~/.zshrc` / `~/.bashrc` and saves a backup as `*.shli-bak`. It also deletes `~/.mylib/shli.sh` and turns off deploy-on-commit. It doesn't touch this repo or anything else in `~/.mylib`. Tabs that are already open keep shli until you close them; the script prints how to unload it there.

## Roadmap

- History database of proposed and run commands
- `e` to edit the command before running
- Send the list of installed tools up front
- A small TUI
