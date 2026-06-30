# i18n-cli

**One command finds every hardcoded string in your Swift app, rewrites it to a localization key, generates `Localizable.xcstrings`, and translates to 10 languages.** Uses SwiftSyntax AST parsing — no other tool does the extract step.

## Three Commands

```bash
# extract → rewrite → xcstrings → translate, one pass
i18n-cli migrate ./MyApp --langs fr,de,es

# translate new strings in an existing .xcstrings
i18n-cli translate Localizable.xcstrings --langs fr,de,es

# CI gate for unlocalized strings
i18n-cli audit ./MyApp
```

## Quick Start

```bash
swift build -c release
export OPENAI_API_KEY="sk-..."

# Full pipeline
./.build/release/i18n-cli migrate ./MyApp --langs fr,de,es
```

## Features

- **AST extraction** — SwiftSyntax walks your code, detects `Text("Hello")`, `Button("OK")`, `.navigationTitle("Home")`, and 15+ other SwiftUI views
- **In-place rewrite** — `Text("Hello")` → `Text("app.hello_a1b2c3d4")` with stable SHA256 keys
- **XCStrings output** — Xcode 15+ `.xcstrings` format (default), sorted keys, proper field ordering
- **Diff-based translation** — only new/changed keys sent to the LLM, cached per language
- **Translation memory** — `(source, lang) → translation` cache for zero-cost repeats (`--no-tm`, `--clear-tm`)
- **Placeholder validation** — catches mismatched `%d`, `%@`, `\n` in translations
- **Glossary** — `--glossary terms.json` for consistent domain terminology
- **UI context** — `--context-screenshots <dir>` includes screenshots in LLM prompts
- **Legacy format** — `.strings` / `.stringsdict` via `--output-format strings`
- **Plural detection** — auto-generates `.stringsdict` for `"%d moves"` patterns
- **Audit mode** — read-only scan, exit code 1 in CI

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode Command Line Tools)
- `OPENAI_API_KEY` for `translate` / `migrate`

## Commands

### `migrate`
```
i18n-cli migrate <projectRoot> [--langs <csv>] [--key-prefix <prefix>] [--dry-run] [--context <desc>]
```
Chains: AST walk → source rewrite → .xcstrings generation → LLM translation. Extract-only when `--langs` omitted.

### `translate`
```
i18n-cli translate <path.xcstrings> --langs <csv> [--dry-run] [--context <desc>] [--model <model>] [--glossary <path>] [--context-screenshots <dir>] [--no-tm] [--clear-tm]
```
Loads `.xcstrings`, diffs against cache, batch-translates untranslated keys, writes back. Also accepts `translate <projectRoot> <baseLang> <targetLangs>` for legacy `.strings` mode.

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

`Text` `Button` `Label` `Section` `Toggle` `Picker` `Menu` `TextField` `Link` `NavigationLink` `ProgressView` `GroupBox` `DisclosureGroup` `ShareLink` `.navigationTitle` `.alert` `.confirmationDialog`

## UIKit Detection

- `NSLocalizedString("...", comment:)` — skipped (already localized)
- `String(localized: "...")` — skipped (already localized)
- `.title = "..."` — detected as unlocalized

## Ignore Directives

```swift
// i18n-ignore           skip this call
// i18n-ignore-file      skip entire file
// i18n-ignore-next      skip next call
// i18n-ignore-block
// ... all calls in range skipped
// i18n-end-ignore
```

## Example

```bash
export OPENAI_API_KEY="sk-..."
# First run: full migration
i18n-cli migrate ./MyApp --langs fr,de,es,zh-Hans --context "fitness tracking app"
# Daily: just translate new/changed strings
i18n-cli migrate ./MyApp --langs fr,de,es,zh-Hans
# CI: fail on unlocalized strings
i18n-cli audit ./MyApp || exit 1
```

## Outputs

- `<projectRoot>/Localizable.xcstrings` — Xcode 15+ string catalog (primary)
- `<projectRoot>/en.lproj/Localizable.strings` — legacy (when `--output-format strings`)
- `<projectRoot>/en.lproj/Localizable.stringsdict` — auto-generated plurals
- `<projectRoot>/.i18n-cache/` — diff cache, translation memory, reports

## Security

Use `OPENAI_API_KEY` in your shell environment — never commit API keys.

## License

MIT
