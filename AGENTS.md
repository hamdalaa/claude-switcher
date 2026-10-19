# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, …) working on this repository.

## What this is
A macOS menu bar app plus a bash CLI (`ccx`) that switch new Claude Code sessions between two accounts:
A = `~/.claude`, B = `~/.claude-b` (via `CLAUDE_CONFIG_DIR`, sharing A's config through symlinks).

## Layout
| Path | What |
|---|---|
| `Sources/ClaudeSwitcherCore/` | Pure, tested logic: account state, Auto pick, usage parsing, shell hook, installer, terminal launch plans |
| `Sources/ClaudeSwitcher/` | SwiftUI app: `SwitcherModel` (state), `PanelView`/`AccountRow`/`CodexRow` (UI), `Launcher`, `System`, readers |
| `cli/ccx` | The bash CLI the app bundles (`Contents/Resources/ccx`) |
| `cli/statusline.sh` | Optional Claude Code status line |
| `Tests/` | Swift Testing suites |
| `tests/ccx_test.sh` | End-to-end tests for `ccx` against a stub `claude` in a temp `$HOME` |
| `DESIGN.md` | UI direction; `Theme.swift` holds every design token |

## Commands
```sh
scripts/test.sh                 # Swift tests (Command Line Tools only, no Xcode)
tests/ccx_test.sh               # ccx end-to-end tests
swift build                     # debug build
scripts/bundle.sh [--install]   # universal release app + zip
.build/debug/ClaudeSwitcher --demo [--demo-mode a|b] --snapshot out.png [--dark]   # render the panel
```
Both test suites must pass before any commit. CI (`.github/workflows/ci.yml`) runs them on GitHub's
macOS runner, whose Swift is older than local toolchains, so concurrency rules are stricter there.

## Invariants — do not break
- **Tokens:** never write, refresh, log, or print OAuth tokens. Reading via `/usr/bin/security` for the
  usage request is the only allowed access. Never add network requests beyond the usage endpoint
  without a clear reason in the PR.
- **User files:** never overwrite files we didn't create (`Installer` decides; foreign `~/.local/bin/ccx`
  is untouched; rc files are backed up once and must be valid UTF-8 or we refuse).
- **Shell safety:** pass paths/commands to shells as argv (`TerminalLaunch`), never splice them into code.
  `shellQuote` is POSIX-only; fish needs argv.
- **Env hygiene:** strip `CLAUDE*` variables before launching anything (`System.cleanEnvironment`), or
  child sessions lose transcripts.
- **`ccx run`** (the `claude` hook) must stay transparent: no login prompts, all args passed through.
- **Honour `$HOME`** (`Paths.defaultHome`) so tests can isolate everything.
- **UI:** values come from `Theme.swift` only; follow `DESIGN.md` (native menu rows, color only for
  identity and warnings). Use `--demo` for screenshots, never real accounts.

## Style
Swift 6 strict concurrency, small focused files, comments explain *why*. Conventional commits
(`feat:`, `fix:`, `docs:`, …). Keep `README.md`, `SECURITY.md` and `CHANGELOG.md` in sync with behaviour.
