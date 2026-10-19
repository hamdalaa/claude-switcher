# Design

## Brief
1. **What:** a menu bar utility that picks which Claude Code account new sessions use, and shows how much of each account's limit is left.
2. **Who:** developers who already live in a terminal; expert; chose it.
3. **How often:** glanced at many times a day; switched a few times a day.
4. **Where:** at a desk, mid-task, as a popover — must be read in under a second, light and dark.
5. **One job:** "which account am I on, how much is left, switch."
6. **Stakes:** low–medium (running out mid-task). Color is reserved for warnings.
7. **Content:** two accounts (+ optional Codex), long emails, two percentages and reset times each.
8. **References:** macOS Control Center Wi‑Fi / Bluetooth menus (selected row expands with detail), Focus menu (header toggle), iStat Menus (dense numbers). Category cliché to avoid: stacked rounded cards with full-width bars and duplicated buttons.
9. **Existing:** account identity colors (A clay, B sage); system font is the platform contract for a menu.
10. **Feel:** "a native macOS menu Apple could have shipped."

## Direction (axis coordinates)
| Ground | Chroma | Structure | Density | Edge | Depth | Type | Texture | Motion | Voice |
|---|---|---|---|---|---|---|---|---|---|
| system popover material | system + identity avatars + semantic orange/red only | menu list, selected row expands | normal-dense (menu) | 6pt hover highlight, circles for avatars | flat, hairline separators, no inner cards | SF at menu sizes 13 / 11, tabular digits | none | none except hover | plain |

## Moves
1. **Rows, not cards.** Accounts are menu rows. A leading ✓ marks the account new sessions start on; clicking a row switches to it.
2. **Detail only where it matters.** The active account's row expands to show its 5-hour and weekly meters; the other row shows a one-line summary.
3. **Color means something.** Meters and numbers are neutral; orange at 70%, red at 90%. Account colors appear only on avatars.
4. **Actions act on the active account** ("New Claude Code session", "Open claude.ai") instead of being duplicated per account; per-account actions live in each row's context menu.
5. **Native chrome:** header with an Auto switch, hairline separators, menu-style rows with hover highlight, "Quit ⌘Q" footer.
