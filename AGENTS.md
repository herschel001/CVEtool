# Repository Guidelines

## Project Structure & Module Organization

CVEtool is a local macOS menu-bar screenshot and clipboard-history app with Chinese UI text.

- `Sources/CVEtoolApp/`: AppKit controllers, capture workflows, clipboard integration, settings, permissions, and global shortcuts.
- `Sources/CVEtoolCore/`: history models and persistence, capacity policies, clipboard classification, screen geometry, and annotation rendering. Keep reusable logic here.
- `Tests/CVEtoolCoreTests/CoreTests.swift`: XCTest suites for core behavior.
- `Tests/CVEtoolAppTests/`: screenshot interaction, toolbar, and icon regression tests. Icon tests require the approved PNG fixtures in `docs/icon-concepts/`.
- `Support/Info.plist`: application identity and bundle settings.
- `scripts/package-app.sh`: app-bundle packaging script.
- `scripts/generate-icons.swift` and `Sources/CVEtoolApp/AppIcon.swift`: generate the application icon; the menu-bar glyph shares the same drawing code.
- `docs/`: PRD registry, `prd/PRD-001.md`, implementation checklist (`任务计划.md`), and HTML design reference (`主界面-设计稿.html`). Consult these before changing user-visible behavior.

## Build, Test, and Development Commands

Use macOS with a Swift 6.0+ toolchain. Targets use Swift 5 language mode; the package declares macOS 15, while the bundle requires 15.2.

- `swift build`: compile the library and executable; use as the first compilation check.
- `swift test`: run all XCTest suites.
- `swift test --filter HistoryStoreTests`: run a focused suite during iteration.
- `swift run CVEtool`: run the executable during development.
- `bash scripts/package-app.sh`: build a debug executable, assemble `build/CVEtool.app`, and ad-hoc sign it.
- `open build/CVEtool.app`: launch the packaged app for permissions and UI checks.

## Coding Style & Naming Conventions

Use four-space indentation, same-line braces, `UpperCamelCase` types, and `lowerCamelCase` members and enum cases. Name files after their main type. Keep AppKit lifecycle in the app target. Handle failures explicitly. No formatter or linter is configured.

## Testing Guidelines

Add regression tests for behavior changes, using `XCTestCase` classes named `<Subject>Tests` and methods named `test<ExpectedBehavior>`. Use temporary directories for persistence tests. No coverage threshold is configured. For UI changes, manually check relevant scenarios in `docs/任务计划.md`, including permission denial, save cancellation, and multiple displays when applicable. Report automated and manual results separately.

## Commit & Pull Request Guidelines

Use `type: summary` subjects, following the initial `init: ...` commit; no strict convention is established. Keep commits focused. PRs should explain changes, link issues or PRD stories, list validation, and include UI screenshots. Exclude `.build/` and `build/`; packaging regenerates them.

## Privacy & Local Configuration

Never commit clipboard contents or screenshots. Use `CVETOOL_SUPPORT_DIR` to isolate history from `~/Library/Application Support/CVEtool`; UserDefaults settings remain shared. Do not add telemetry, uploads, or sync without authorization.
