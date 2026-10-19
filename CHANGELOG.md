# Changelog

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
