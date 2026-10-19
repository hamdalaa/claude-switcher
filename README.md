<h1 align="center">Claude Switcher</h1>

<p align="center">
  <b>Two Claude Code accounts. One click to switch. Live usage in your menu bar.</b>
</p>

<p align="center">
  <a href="https://github.com/hamdalaa/claude-switcher/releases/latest"><img src="https://img.shields.io/github/v/release/hamdalaa/claude-switcher?label=download&color=444" alt="Latest release"></a>
  <a href="https://github.com/hamdalaa/claude-switcher/releases"><img src="https://img.shields.io/github/downloads/hamdalaa/claude-switcher/total?color=444" alt="Downloads"></a>
  <a href="https://github.com/hamdalaa/claude-switcher/actions/workflows/ci.yml"><img src="https://github.com/hamdalaa/claude-switcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-444" alt="macOS 15+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/hamdalaa/claude-switcher?color=444" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/switching.gif" width="380" alt="Switching between two Claude Code accounts in the menu bar">
</p>

Hit your Claude limit in the middle of a task? If you have a second Claude subscription (say, work
and personal), Claude Switcher puts both in your menu bar. You see how much each has left and
switch with one click, and your settings, skills, agents and memory come along.

> **Unofficial.** A community project, not made by or affiliated with Anthropic or OpenAI.

## Install

```sh
brew install --cask hamdalaa/tap/claude-switcher
```

Or [download the app](https://github.com/hamdalaa/claude-switcher/releases/latest), unzip it, and move
it to Applications. It's free and open source, but not notarized, so the first time macOS will
block it: open **System Settings → Privacy & Security → Open Anyway**.

Then click the account icon in your menu bar, choose **Sign In to Account B…**, and log in with your
second account.

**Requirements:** macOS 15 or later (Apple silicon or Intel) and [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
signed in. Optional: Chrome, Brave, Edge, Chromium or Vivaldi for per-account claude.ai windows, and
the [Codex CLI](https://github.com/openai/codex) for Codex usage.

### Let your AI set it up

Paste this into Claude Code (or any AI coding agent with terminal access):

```text
Install Claude Switcher (https://github.com/hamdalaa/claude-switcher) on this Mac and set it up
for my two Claude accounts. Follow its README and llms.txt. Specifically:
1. Check macOS 15+ (`sw_vers`), that Claude Code works (`claude --version`), and that account A is
   signed in (`claude auth status`). If something is missing, stop and tell me.
2. Install with `brew install --cask hamdalaa/tap/claude-switcher`; if Homebrew isn't available,
   download the latest release zip, verify its .sha256, and move the app to /Applications.
3. Open it: `open -a "Claude Switcher"`.
4. Sign in account B: run
   `"/Applications/Claude Switcher.app/Contents/Resources/ccx" login b`
   and tell me to finish the browser login with my SECOND account (not account A).
5. Ask me whether plain `claude` should follow the switch. Only if I say yes, run
   `"/Applications/Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" --install-hook`.
6. Show me the result of `ccx status` (or the bundled ccx above).
Rules: never read, print or copy tokens or Keychain items; never edit my shell files yourself.
```

## What you get

- **One-click switching.** Click an account and new sessions start on it. Or turn on **Auto**, which
  picks whichever account has more room left. Sessions that are already running keep their account.
- **Live usage.** 5-hour and weekly limits for both accounts straight from Anthropic, with time to
  reset. Numbers turn orange at 70% and red at 90%, and you get an alert when an account fills up or
  frees up again.
- **One setup, two logins.** Account B shares account A's settings, `CLAUDE.md`, skills, agents,
  commands, hooks, plugins, MCP servers, memory and history. Only the login is separate.
- **claude.ai per account.** Each account gets its own browser window, so both stay signed in
  without touching your everyday browser profile.
- **Plain `claude` follows the switch** (optional shell hook for zsh, bash and fish), plus the
  `ccx` command for scripts.
- **Codex usage** too, if you use the Codex CLI.
- Your terminal of choice: Terminal, iTerm2, Ghostty, kitty or WezTerm.

<p align="center">
  <img src="docs/screenshot-light.png" width="300" alt="Light mode">
  <img src="docs/screenshot-dark.png" width="300" alt="Dark mode">
</p>

## Using it

| You want to… | Do this |
|---|---|
| Switch accounts | Click the account. ✓ marks where new sessions start |
| Let it choose | Turn on **Auto** (picks the account with more room left) |
| Start Claude Code | **New Claude Code Session**, or **Open in Recent Folder** |
| Use claude.ai | **Open claude.ai**: a separate window per account |
| Act on the other account | Right-click its row |
| Change a picture | Right-click a row → **Change Picture…**, or drop an image on it |
| Settings | Terminal, `claude` hook, `ccx` command, open at login, alerts |

### The `ccx` command

```text
ccx              start on the switched-to account
ccx a|b [...]    start on a specific account (extra args go to claude)
ccx run [...]    like ccx, but passes ALL args to claude
ccx use a|b|auto set the switch
ccx which        print which account the next session uses
ccx login a|b    sign an account in
ccx logout a|b   sign an account out
ccx status       accounts, usage, current switch
ccx sync         re-link shared config into account B
```

## How it works

- **Separate logins, shared everything else.** Claude Code reads its config from
  `CLAUDE_CONFIG_DIR`. Account B runs with `CLAUDE_CONFIG_DIR=~/.claude-b`, where `ccx` keeps
  symlinks to A's `settings.json`, `CLAUDE.md`, `skills/`, `agents/`, `commands/`, `hooks/`,
  `plugins/`, `projects/` and `history.jsonl`. A few account-independent keys from `~/.claude.json`
  (such as `mcpServers`) are copied over. The login is never copied.
- **Each login stays in its own Keychain item.** Claude Code stores A as `Claude Code-credentials`
  and B as `Claude Code-credentials-<hash of ~/.claude-b>`. Signing in, refreshing and signing out
  are all done by Claude Code itself.
- **The switch** is one file, `~/.claude-accounts/default` (`a`, `b`, or absent for Auto). `ccx`,
  the shell hook and the app all read it.
- **Live usage** comes from the same endpoint Claude Code's `/usage` uses.

## Privacy & security

- **No telemetry, no servers of ours.** The only network request is
  `GET https://api.anthropic.com/api/oauth/usage` for each signed-in account.
- **Tokens are read, never written.** The app reads each account's access token from the Keychain
  (via `/usr/bin/security`) only to ask for usage. It never stores, logs, refreshes or modifies a
  token. Expired tokens are renewed by Claude Code itself (`claude auth status`).
- **Your files:** it writes under `~/.claude-accounts/` and `~/.claude-b/`, short-lived launch
  scripts in `$TMPDIR`, and only if you turn them on, `~/.local/bin/ccx` and one marked block in
  your shell config (backed up first). A `~/.local/bin/ccx` it didn't install is never overwritten.
- The usage endpoint isn't a documented public API. If it changes, usage may stop showing until an
  update. Switching keeps working regardless.

Full list in [SECURITY.md](SECURITY.md).

## FAQ

**Is this allowed?** It automates what you can already do by hand with `CLAUDE_CONFIG_DIR` and two
subscriptions you own. You're responsible for following Anthropic's
[terms](https://www.anthropic.com/legal/consumer-terms) and [Usage Policy](https://www.anthropic.com/legal/aup).

**Does it work with API keys, Bedrock or Vertex?** Switching does. Live usage needs a claude.ai
login (Pro / Max).

**Why not just log out and back in?** That throws away your session state, and you can't run both
accounts side by side. Here both stay signed in, and sessions on A and B can run at the same time.

**Plain `claude` still uses A.** Turn on **Plain `claude` follows the switch** in Settings, then open
a new terminal tab. Check with `ccx which`.

**Usage says "Sign-in expired".** Start one session on that account. Claude Code renews its login
and usage comes back.

**iTerm2 doesn't open.** Allow Claude Switcher under System Settings → Privacy & Security → Automation.

**How do I uninstall?** In Settings, turn off the `claude` hook and the `ccx` command. Then quit and
delete the app. Optionally remove `~/.claude-accounts/`. To drop account B entirely, run
`CLAUDE_CONFIG_DIR=~/.claude-b claude auth logout` and delete `~/.claude-b`.

## Optional: status line

`statusline.sh` (in the app at `Contents/Resources/`) shows the current account and both accounts'
usage in Claude Code's status line. Add to `~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "/Applications/Claude Switcher.app/Contents/Resources/statusline.sh" }
```

## Build from source

Only the Xcode Command Line Tools are needed (`xcode-select --install`).

```sh
git clone https://github.com/hamdalaa/claude-switcher.git && cd claude-switcher
scripts/test.sh            # Swift tests
tests/ccx_test.sh          # end-to-end tests for ccx
scripts/bundle.sh --install
```

Setup without the UI: `ClaudeSwitcher --install-hook | --remove-hook | --install-cli | --remove-cli`.
Screenshots with sample data: `ClaudeSwitcher --demo [--demo-mode a|b] --snapshot out.png [--dark]`.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). AI coding agents should
read [AGENTS.md](AGENTS.md) first.

If Claude Switcher saves you from a limit, a ⭐ helps other people find it.

## License

[MIT](LICENSE)
