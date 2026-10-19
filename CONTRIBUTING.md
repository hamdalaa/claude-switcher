# Contributing

Thanks for helping! Issues and pull requests are welcome.

- **Setup:** Xcode Command Line Tools are enough (`xcode-select --install`).
- **Before a PR:** run `scripts/test.sh` and `tests/ccx_test.sh` — both must pass.
- **UI changes:** attach before/after screenshots. `.build/debug/ClaudeSwitcher --demo --snapshot out.png [--dark]`
  renders the panel with sample data, so no personal info ends up in screenshots.
- **Keep it safe:** never write, refresh or log OAuth tokens; never overwrite user files we
  didn't create (see `Installer`). New network requests need a clear reason in the PR.
- **Layout:** `Sources/ClaudeSwitcherCore` is pure, tested logic; `Sources/ClaudeSwitcher` is
  the SwiftUI app; `cli/ccx` is the bash CLI the app bundles.
