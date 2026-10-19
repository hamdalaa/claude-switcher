<h1 align="center">Claude Switcher</h1>

<p align="center">
  Switch between two Claude Code accounts from your menu bar —<br>
  with live usage, shared settings, and one click to open a session.
</p>

<p align="center">
  <img src="docs/screenshot-light.png" width="360" alt="Claude Switcher panel, light mode">
  <img src="docs/screenshot-dark.png" width="360" alt="Claude Switcher panel, dark mode">
</p>

> **Unofficial.** Claude Switcher is a community project. It is not made by, affiliated with, or
> endorsed by Anthropic or OpenAI. "Claude" and "Codex" are trademarks of their owners.

## What it does

- **Two Claude Code accounts, one setup.** Account **A** is your normal `~/.claude`. Account **B**
  lives in `~/.claude-b` and *shares* A's settings, skills, agents, commands, hooks, memory and
  history — only the login is separate.
- **Switch in one click.** Pick **A**, **B**, or **Auto** (whichever account has more headroom).
  New sessions — from the app, from `ccx`, and (optionally) from plain `claude` — start there.
- **Live usage.** 5-hour and weekly usage for both accounts, straight from Anthropic, with reset
  countdowns and bars that go green → yellow → orange → red. Plan tag (Pro, Max 5x, Max 20x).
- **claude.ai per account.** Opens claude.ai in a separate browser window for each account, so
  both stay signed in without touching your everyday browser profile.
- **Codex too.** If the Codex CLI is installed, its usage and "% left" show up as well.
- **Alerts** when an account reaches 90% or becomes available again.
- **Little things:** open a session in a recent project folder, custom profile pictures, your
  choice of terminal (Terminal, iTerm2, Ghostty, kitty, WezTerm), open at login.

## Requirements

- macOS 15 Sequoia or later (Apple silicon or Intel)
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) installed and signed in
  (that becomes account A)
- Optional: Chrome, Brave, Edge, Chromium or Vivaldi for the per-account claude.ai windows
- Optional: the [Codex CLI](https://github.com/openai/codex) for Codex usage

## Install

1. Download `Claude-Switcher-<version>.zip` from
   [Releases](https://github.com/hamdalaa/claude-switcher/releases) and unzip it.
2. Move **Claude Switcher.app** to **Applications**.
3. Open it. The app is ad-hoc signed, not notarized, so macOS blocks the first launch:
   open **System Settings → Privacy & Security** and click **Open Anyway**
   (or run `xattr -dr com.apple.quarantine "/Applications/Claude Switcher.app"`).
4. Click the **Ⓐ** in your menu bar, then **Sign in to Claude Code** on account B and log in
   with your second account in the browser.

That's it. Optional, from the panel or **Settings**:

- **Plain `claude` follows the switch** — adds a small, clearly marked hook to your shell
  config (zsh: `.zshrc`, respecting `ZDOTDIR`; bash: whichever of `.bash_profile`,
  `.bash_login`, `.profile` you already use; fish: its own `conf.d` file). Without it, plain
  `claude` always uses account A; `ccx` and the app's buttons always follow the switch. The hook
  never prompts for a login and falls back to the real `claude` if `ccx` is removed.
- **Install `ccx` command** — puts the `ccx` CLI in `~/.local/bin`.

## Using it

| You want to… | Do this |
|---|---|
| Switch accounts | Click an account card, or the **Auto / A / B** control |
| Start Claude Code | **Claude Code** on a card (▾ = open in a recent folder) |
| Use claude.ai | **claude.ai** on a card — each account gets its own window |
| See usage | It's live: refreshes every 3 minutes and whenever you open the panel |
| Re-share settings into B | The ↻ button in the footer (also happens on every B launch) |

New sessions use the switched account. Sessions that are already running keep theirs.

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
  `plugins/`, `projects/` (memory + transcripts), `history.jsonl` and more. A few
  account-independent keys of `~/.claude.json` (such as `mcpServers` and `theme`) are copied
  into B's on each launch; the login (`oauthAccount`) never is.
- **Each login stays in its own Keychain item.** Claude Code stores account A's token as
  `Claude Code-credentials` and B's as `Claude Code-credentials-<hash of ~/.claude-b>`. Signing
  in, refreshing and signing out are all done by Claude Code itself.
- **The switch** is one file: `~/.claude-accounts/default` (`a`, `b`, or absent for Auto).
  `ccx`, the shell hook and the app all read it.
- **Live usage** comes from the same endpoint Claude Code's `/usage` uses, called with each
  account's existing access token.

## Privacy & security

- **No telemetry, no servers of ours.** The only network request the app makes is
  `GET https://api.anthropic.com/api/oauth/usage` for each signed-in account.
- **Tokens are read, never written.** To ask for usage, the app reads each account's access token
  from the login Keychain through `/usr/bin/security`. It never stores, logs, refreshes or
  modifies tokens. If a token has expired it runs `claude auth status`, which lets Claude Code
  renew its own login.
- **Codex** usage is read locally through `codex app-server` (no model requests).
- **Your files:** the app writes under `~/.claude-accounts/` and `~/.claude-b/`, short-lived
  launch scripts in `$TMPDIR`, and — only if you turn those options on — `~/.local/bin/ccx` and
  one marked block in your shell config (backed up once to `<file>.before-claude-switcher`).
  A `~/.local/bin/ccx` it didn't install is never overwritten. Full list in [SECURITY.md](SECURITY.md).
- The usage endpoint is not a documented public API; if Anthropic changes it, usage may stop
  showing until the app is updated. Switching keeps working regardless.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Is this allowed?

Claude Switcher only automates what you can already do by hand with `CLAUDE_CONFIG_DIR` and
two subscriptions you own. You are responsible for using your accounts in line with
[Anthropic's terms](https://www.anthropic.com/legal/consumer-terms) and
[Usage Policy](https://www.anthropic.com/legal/aup).

## Optional: status line

`statusline.sh` (inside the app at `Contents/Resources/`, or `cli/` in this repo) shows which
account a session runs on plus both accounts' usage in Claude Code's status line. Add to
`~/.claude/settings.json`:

```json
"statusLine": { "type": "command", "command": "/Applications/Claude Switcher.app/Contents/Resources/statusline.sh" }
```

## Uninstall

1. In **Settings**, turn off **Plain `claude` follows the switch** and **Install `ccx` command**.
2. Quit the app and delete it from Applications.
3. Optional: remove `~/.claude-accounts/`. To drop account B entirely, run
   `CLAUDE_CONFIG_DIR=~/.claude-b claude auth logout`, then delete `~/.claude-b`
   (it only contains links to A's files plus B's own config).

## Troubleshooting

- **"Claude Code isn't installed"** — install it, and make sure `claude` works in a new
  terminal window. The app uses the PATH your login shell sets up.
- **Plain `claude` still uses A** — open a *new* terminal tab after turning the hook on, and
  check with `ccx which`.
- **Usage says "Sign-in expired"** — start one session on that account; Claude Code renews its
  login and usage comes back.
- **iTerm2 doesn't open** — allow Claude Switcher under System Settings → Privacy & Security →
  Automation.
- Logs: `log stream --predicate 'subsystem == "io.github.hamdalaa.ClaudeSwitcher"'`

## Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`), no Xcode.

```sh
git clone https://github.com/hamdalaa/claude-switcher.git
cd claude-switcher
scripts/test.sh            # Swift tests (Swift Testing)
tests/ccx_test.sh          # end-to-end tests for the ccx script
scripts/bundle.sh          # → dist/Claude Switcher.app + release zip
scripts/bundle.sh --install
```

`ClaudeSwitcher --demo --snapshot out.png [--dark]` renders the panel with sample data.
`ClaudeSwitcher --install-hook | --remove-hook | --install-cli | --remove-cli` does setup
without the UI (e.g. `"/Applications/Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" --install-hook`).

## License

[MIT](LICENSE)
