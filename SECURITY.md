# Security

Claude Switcher reads Claude Code's OAuth access tokens (read-only) to show usage, and edits
shell config files when you ask it to. Please report anything that could expose a token, run
unintended commands, or modify files outside what the README describes.

**Report privately** through GitHub's
[private vulnerability reporting](https://github.com/hamdalaa/claude-switcher/security/advisories/new).
Please don't open a public issue for security problems.

## What the app touches

| What | How | Why |
|---|---|---|
| Login Keychain items `Claude Code-credentials*` | read via `/usr/bin/security find-generic-password -w` | access token for the usage request |
| `https://api.anthropic.com/api/oauth/usage` | HTTPS GET, ephemeral session, no cookies/cache | live usage |
| `claude auth status` | run when a token has expired | lets Claude Code renew its own login |
| `codex app-server` | local stdio JSON-RPC, read-only methods | Codex usage |
| `~/.claude-accounts/`, `~/.claude-b/` | read/write | switch state, usage cache, account B config |
| `~/.local/bin/ccx`, shell rc file | write, only when enabled in Settings (rc file backed up once first) | `ccx` command, `claude` hook |
| Your login shell (`$SHELL -lic`) | run once at launch, prints PATH / ZDOTDIR / XDG_CONFIG_HOME | find `claude`, `codex`, and where your rc files live |
| `$TMPDIR/claude-switcher-<uuid>.command` | written 0700, deleted after ~60 s | how Terminal / iTerm2 sessions are started |
| iTerm2 (Apple Events) | only if you pick iTerm2 | open a window running the session |
| Chromium-family browser with `--user-data-dir=~/.claude-accounts/web/<a\|b>` | launched on click | isolated claude.ai window per account |
| `~/.claude/history.jsonl` | read | "recent folders" menu |

Folder names and commands are passed to shells as arguments, never spliced into shell code.
The usage request refuses HTTP redirects and caps the response size.

Tokens are never written to disk, logged, sent anywhere but Anthropic, or refreshed by the app.
