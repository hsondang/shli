# shli

*Pronounced "shee-el-ai", like CLI.*

Describe what you want in plain English. shli asks Claude Haiku for one shell command that fits your OS and shell, shows it, and runs it when you press ⏎.

```
$ shli check my kernel and os version
uname -srm && sw_vers
Shows kernel name, release, arch, and macOS product version
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

| Key | Does |
|---|---|
| ⏎ | Run the command |
| y | Run it. A destructive command needs `y`; ⏎ is ignored. |
| esc | Cancel |

The command's color tells you its risk:
- **bold**: read-only.
- **yellow**: changes something you can undo.
- **red with ⚠ destructive**: deletes data, uses sudo, kills processes, or can't be undone.

The command runs in **your current shell**, so `cd`, `export` and your aliases work. It's also added to your shell history, so ↑ brings it back next time.

## How it works

1. **Context.** shli reads your OS and version (`sw_vers` on macOS, `/etc/os-release` on Linux), `uname -srm`, and your shell and its version. This takes about 25 ms per call, so nothing is cached.
2. **One call to Haiku.** The request goes in on stdin, so a request starting with `-` can't be mistaken for a flag:

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

   The answer contains 1–3 candidates, best first. shli reads only `structured_output`:

   ```json
   {"candidates": [
     {"cmd": "uname -srm && sw_vers", "explain": "Shows kernel name, release, arch, and macOS product version", "risk": "safe"},
     {"cmd": "uname -a", "explain": "Prints full kernel info including hostname and build details", "risk": "safe"}
   ]}
   ```

   Don't swap in `--bare`. It's faster to start, but it turns off subscription login.

3. **Pick one that exists here.** shli picks the first candidate whose program exists on this machine. It checks the first word, skipping `sudo`, with `command -v`, which also sees your aliases and functions. If none of them exist, it shows the first one with `not found: <name>`.
4. **Confirm, then run.** Press ⏎ (or `y`), and the command goes into shell history and then `eval` in your shell.

Each request takes about **4–6 s**: 2–4 s for the model and about 2 s for `claude` to start.

## Development

- Edit `shli.sh` here, never `~/.mylib/shli.sh`. Every commit overwrites that copy.
- Every commit deploys the **committed** `shli.sh` to `~/.mylib/shli.sh`, through `.githooks/post-commit`. The first line of the deployed file names the commit. New tabs get the new version; in an open tab, run `source ~/.mylib/shli.sh`.
- To try uncommitted changes, run `source ./shli.sh` in a tab.
- Checks:
  - `zsh -n shli.sh && bash -n shli.sh`
  - `test/smoke.exp zsh`, `test/smoke.exp /bin/bash`, `test/smoke.exp /usr/local/bin/bash`

  The smoke test drives shli in a real terminal: ⏎, esc, arrow keys, the destructive-command guard and `cd`. It makes 5 real Claude calls inside an empty temp folder.

## Uninstall

```bash
./uninstall.sh
```

It removes the source line from `~/.zshrc` / `~/.bashrc` and saves a backup as `*.shli-bak`. It also deletes `~/.mylib/shli.sh` and turns off deploy-on-commit. It doesn't touch this repo or anything else in `~/.mylib`. Tabs that are already open keep shli until you close them; the script prints how to unload it there.

## Roadmap

- History database of proposed and run commands
- tab to cycle through candidates, `e` to edit before running
- Send the list of installed tools up front
- A small TUI
