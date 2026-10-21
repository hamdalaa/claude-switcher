# Changelog

## 1.2.2

- **Usage no longer freezes when an account sits idle.** Once an account's sign-in expired (about 8
  hours without a session), the app asked Claude Code to renew it with `claude auth status`, which no
  longer refreshes tokens, so that account's usage stayed stuck. It now renews with the local
  `/usage` command in print mode: no model request, no tokens, no transcript, no hooks, no MCP
  servers. A token revoked early (HTTP 401) is renewed too.
- **"Account X is available again" works.** It compared against an already-reset reading, so it
  could never fire.
- **Idle sessions can't undo a newer reading.** The status line now records a session's numbers only
  when they change, and skips the write when nothing changed.
- The status line no longer leaves `.a.XXXXXX` temp files in `~/.claude-accounts/usage` when Claude
  Code stops it mid-redraw (and sweeps up old ones).
- An account with no usage yet shows why (signed out, expired, offline) instead of "loading usage…"
  forever.
- Codex errors are readable ("Signed out — run codex login") instead of a raw HTTP dump.
  A Codex CLI that hangs can no longer stall every usage refresh.
- A failed update check (e.g. no network at login) is retried at the next poll, not a day later.
- Updating the app re-links shared folders into every account right away.

## 1.2.1

- **Usage numbers fixed.** An idle Claude Code session keeps redrawing its status line with the usage
  from its last request, and the newest file used to win, so menu bar, meters and Auto could show an
  old, lower number. Readings are now merged per window: a later reset is a newer window, and within
  one window the higher percent wins (usage never goes down inside a window). Same rule in the app
  and the status line.
- The status line only records accounts it recognises (`~/.claude`, `~/.claude-b`…`-d`). An unknown
  `CLAUDE_CONFIG_DIR` used to be recorded as account A, mixing another login's usage into A.
- The status line writes through a unique temp file, so two sessions can't clobber each other's write.

- Share task lists (`tasks/`), persistent subagent memory (`agent-memory/`) and saved workflows
  (`workflows/`) across accounts, creating the shared directories before the first launch.
- Route **Continue a Conversation** through `ccx resume <account> <session-id>`: validate shared
  state and the persisted transcript, return to the original folder, and refuse known live sessions.
- Report conflicting real files and dangling/wrong symlinks without replacing them; `ccx sync`
  now exits nonzero on conflicts. Checked handoff validates all configured accounts.
- Handoff performs no model calls, generates no summaries and injects no prompt. Explicit launch
  configuration can be re-supplied after `--`; raw `ccx run` remains a transparent passthrough.
- Document normal resume usage, cache and compaction limits, and a real-account validation checklist.

## 1.2.0

- **Continue a Conversation:** pick up a recent conversation on the active account, e.g. carry on with B after A hits its limit (`claude --resume`, history is shared)
- **Up to four accounts** (A–D): Add Account…, Remove Account…; Auto picks across all of them; `ccx` and the status line support c and d
- **Name your accounts** ("Work", "Personal"): right-click → Rename…
- **Welcome window** on first launch: confirms account A, adds account B, offers the `claude` hook and open at login (Settings → Show Welcome)
- **Update check:** once a day against GitHub releases, with one-click update (Homebrew or release page); can be turned off

## 1.1.1

- Menu bar shows both limits for the active account: `D:56% W:87%` (D = 5-hour window, W = weekly)

## 1.1.0

- New design: the panel is now a native macOS menu. Click an account to switch (✓ marks it), the active account expands with its meters, an Auto switch sits in the header, and color is used only for identity and warnings
- Actions ("New Claude Code Session", "Open in Recent Folder", "Open claude.ai") act on the active account; right-click a row for the other one
- Refresh Usage and Re-sync Account B moved into Settings
- One-line install: `brew install --cask hamdalaa/tap/claude-switcher`
- Copy-paste prompt so an AI agent can install and set it up; AGENTS.md and llms.txt for AI tools

## 1.0.1

- Usage held from an earlier read now drops to 0% once its window resets (Auto no longer misled by a failing refresh)
- "Account is full" alerts no longer missed while a session is running; no false "available again" when a window is missing
- First alert no longer lost to the permission prompt (permission is asked at launch)
- Signed-out accounts can't be switched to; old usage/plan cleared when an account signs out or changes
- Panel refreshes every time it opens; failed-refresh reason shown on its own line
- Uninstalled terminal choice falls back to automatic; VoiceOver labels for pictures

## 1.0.0

First public release.

- Menu bar switcher for two Claude Code accounts (A = `~/.claude`, B = `~/.claude-b`) with shared config
- Auto mode picks the account with more headroom
- Live 5-hour / weekly usage, plan tag, reset countdowns, usage-coloured bars, alerts
- Per-account claude.ai windows (isolated Chromium profiles)
- Codex CLI usage card
- `ccx` CLI, optional `claude` shell hook (zsh, bash, fish)
- Terminal choice: Terminal, iTerm2, Ghostty, kitty, WezTerm
- Universal app (Apple silicon + Intel), macOS 15+
