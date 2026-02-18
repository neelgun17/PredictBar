# Contributing to Kalshi Menu Bar

## Development Setup

1. **Requirements**: macOS 13.0+, Swift 5.9+ (included with Xcode 15+)
2. Clone and build:
   ```bash
   git clone https://github.com/neelgun17/KalshiMenuBar.git
   cd KalshiMenuBar
   make run
   ```
3. See all available targets:
   ```bash
   make help
   ```
4. For a developer-signed build (needed for notifications):
   ```bash
   CODESIGN_IDENTITY="Apple Development" make run
   ```

## Making Changes

1. Create a branch: `git checkout -b my-feature`
2. Make your changes, keeping diffs small and focused.
3. Build and verify: `make build`
4. Test the app manually — there is no automated test suite yet.
5. Open a pull request against `main`.

## Code Style

- Follow existing conventions in the codebase.
- Use `@MainActor` for ViewModels that publish UI state.
- Use `[weak self]` in closures to prevent retain cycles.
- Keep credentials in the macOS Keychain only — never write secrets to disk or logs.

## Reporting Bugs

Open an issue with:
- macOS version
- Steps to reproduce
- Console output (`make debug` to capture logs)
