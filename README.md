# i18n-cli — Swift App Localization CLI

**One command finds every hardcoded string in your SwiftUI app, rewrites it to a localization key, generates `Localizable.xcstrings`, and translates to 10 languages.** Uses SwiftSyntax AST parsing — nobody else does the extract step.

## Three Commands

```bash
# THE WEDGE — extract, rewrite, xcstrings, translate in one pass
i18n-cli migrate ./MyApp --langs fr,de,es

# TABLE STAKES — translate new strings in an existing .xcstrings
i18n-cli translate Localizable.xcstrings --langs fr,de,es

# SAFETY NET — CI gate for regressions
i18n-cli audit ./MyApp
```

## Quick Start

```bash
# Build
swift build -c release

# Export your OpenAI API key
export OPENAI_API_KEY="sk-..."

# 🚀 Full pipeline: extract → rewrite → translate
./.build/release/i18n-cli migrate ./MyApp --langs fr,de,es --context "fitness tracking app"
```

## Features

- **AST extraction** — SwiftSyntax walks your code, finds `Text("Hello")` / `Button("OK")` / `.navigationTitle("Home")` and 15+ other SwiftUI views
- **In-place rewrite** — `Text("Hello")` → `Text("app.hello_a1b2c3d4")` with stable SHA256-based keys
- **XCStrings output** — modern Xcode 15+ `.xcstrings` format (default, sorted keys, proper field ordering)
- **Diff-based translation** — only new/changed keys are sent to the LLM, cached per language
- **Translation memory** — `(sourceText, lang) → translation` cache for zero-API-cost repeats
- **Placeholder validation** — detects mismatched `%d`, `%@`, `\n` in translations
- **Glossary support** — `--glossary terms.json` for consistent domain terminology
- **Context screenshots** — `--context-screenshots <dir>` includes UI screenshots in LLM prompts
- **Legacy compatibility** — `.strings` / `.stringsdict` output via `--output-format strings`
- **Plural detection** — auto-generates `.stringsdict` for `"%d moves"` / `"%d move(s)"` patterns
- **Audit mode** — read-only scan, exit code 1 in CI when unlocalized strings found

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools)
- OpenAI API key for `translate` / `migrate`

## Commands

### `migrate` (hero command)
```
i18n-cli migrate <projectRoot> [--langs <csv>] [--key-prefix <prefix>] [--dry-run] [--context <desc>]
```
Chains: AST walk → source rewrite → .xcstrings generation → LLM translation. If `--langs` is omitted, extract-only.

### `translate` (xcstrings)
```
i18n-cli translate <path.xcstrings> --langs <csv> [--dry-run] [--context <desc>] [--model <model>] [--glossary <path>] [--context-screenshots <dir>] [--no-tm] [--clear-tm]
```
Loads an existing `.xcstrings`, diffs against cache, batch-translates untranslated keys, writes back. Auto-detected when path ends in `.xcstrings`.

### `translate` (legacy .strings)
```
i18n-cli translate <projectRoot> <baseLang> <targetLangs>
```
Original `.strings`-based translate path. Preserved for backward compatibility.

### `extract`
```
i18n-cli extract <projectRoot> <baseLang> [--apply] [--dry-run] [--key-prefix <prefix>] [--report <path>] [--include <csv>] [--exclude <csv>] [--overwrite-existing] [--no-skip-keys] [--stringsdict <auto|report>] [--output-format <xcstrings|strings>]
```

### `audit`
```
i18n-cli audit <projectRoot> [--include <csv>] [--exclude <csv>]
```
Read-only AST scan. Reports unlocalized strings to stdout. Exit code 1 if findings found — use as a CI gate.

## Supported SwiftUI Views

`Text`, `Button`, `Label`, `.navigationTitle`, `.alert`, `.confirmationDialog`, `Section`, `Toggle`, `Picker`, `Menu`, `TextField`, `Link`, `NavigationLink`, `ProgressView`, `GroupBox`, `DisclosureGroup`, `ShareLink`

## Supported UIKit Patterns

- `NSLocalizedString("...", comment:)` — skipped (already localized)
- `String(localized: "...")` — skipped (already localized)
- `.title = "..."` — detected as assignment

## Ignore Directives

```swift
// i18n-ignore        — skip the next expression
// i18n-ignore-file   — skip the entire file
// i18n-ignore-next   — skip the next call
// i18n-ignore-block
// ... calls in block are skipped
// i18n-end-ignore
```

## Example Workflow

```bash
# First time setup
export OPENAI_API_KEY="sk-..."
i18n-cli migrate ./MyApp --langs fr,de,es,zh-Hans --context "fitness tracking app"

# Day-to-day: just re-extract and translate new strings
i18n-cli migrate ./MyApp --langs fr,de,es,zh-Hans

# Or manually translate a xcstrings file
i18n-cli translate Localizable.xcstrings --langs fr,de

# CI gate
i18n-cli audit ./MyApp || exit 1
```

## Outputs

- `<projectRoot>/Localizable.xcstrings` — Xcode 15+ string catalog (primary format)
- `<projectRoot>/en.lproj/Localizable.strings` — legacy `.strings` (when `--output-format strings`)
- `<projectRoot>/en.lproj/Localizable.stringsdict` — plural rules (auto-generated)
- `<projectRoot>/.i18n-cache/*` — diff cache, translation memory, reports

## Security

Do not commit API keys. Use `OPENAI_API_KEY` in your shell environment.

## License

MIT
