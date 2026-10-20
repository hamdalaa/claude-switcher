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
| `https://api.github.com/repos/hamdalaa/claude-switcher/releases/latest` | HTTPS GET, at most daily, no credentials; off via Settings | update check |
| `~/.claude/projects/*/*.jsonl` | reads the first 256 KB of recent transcripts | "Continue a Conversation" menu (folder + first prompt) |
| Selected `~/.claude/projects/*/<session-id>.jsonl` | locally validates JSONL in a streaming pass; does not rewrite or send it | checked handoff verifies saved state and original working folder |
| `~/.claude{,-b,-c,-d}/sessions/*.json` | reads session ID/PID; `kill -0` checks process existence without sending a signal | refuse a handoff when a known instance of the session is still running |
| `~/.claude/{projects,file-history,todos,plans,tasks,agent-memory,workflows}/` | creates missing directories; links B–D to A | shared durable state, including first task/memory writes |
| `ccx resume <account> <session-id> -- <options>` | forwards explicit configuration as argv to `claude --resume`; does not save the options | preserve user-supplied launch configuration without a second credential/config store |
| `ccx remove <b\|c\|d>` | signs the account out and deletes only `~/.claude-<b\|c\|d>` (path is validated) | "Remove Account…" |
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

The checked handoff itself makes no network or model request and generates no prompt or summary.
Claude Code authenticates normally and sends resumed context to its provider when used. Runtime
registries, daemon/job state and credentials are not shared. The registry check is best-effort and
does not acquire a process lock or terminate a session.

Conflicting real files, dangling links and links to a different path are reported and left intact.
Handoff stops on a sharing conflict rather than silently resuming with a private task/memory store.
An existing file is never automatically moved, merged or replaced.
