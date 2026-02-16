# Swift app localize CLI

A SwiftPM-based CLI that extracts base English localizations from SwiftUI code and translates them to other languages using the OpenAI API. It supports diff-based translation, batch processing, and optional `.stringsdict` auto-generation for strict plural patterns.

## Features
- Extract SwiftUI literals to `en.lproj/Localizable.strings`
- Optional in-place rewrite of SwiftUI literals to localization keys
- Translate base strings to multiple languages via OpenAI
- Diff-based translation (only new/changed keys)
- `.stringsdict` auto-generation for strict plural formats
- JSON report output for auditing

## Install
```bash
swift build -c release
```

Binary:
- `./.build/release/i18n-cli`

## Quick Start
```bash
# Extract base English and rewrite SwiftUI literals
./.build/release/i18n-cli extract /path/to/App en --apply

# Translate into multiple languages
export OPENAI_API_KEY="sk-..."
./.build/release/i18n-cli translate /path/to/App en "fr,de,es"
```

## Commands

### extract
```
i18n-cli extract <projectRoot> <baseLang> [--apply] [--dry-run] [--key-prefix <prefix>] [--report <path>] [--include <csv>] [--exclude <csv>] [--overwrite-existing] [--no-skip-keys] [--stringsdict <auto|report>]
```

- `--apply`: rewrite SwiftUI literals to keys
- `--dry-run`: generate strings + report only (no code rewrite)
- `--key-prefix <prefix>`: key namespace (default `app`)
- `--report <path>`: report output path (default `.i18n-cache/extract-report.json`)
- `--include <csv>`: limit scan to specific paths
- `--exclude <csv>`: exclude paths
- `--overwrite-existing`: overwrite existing values in `Localizable.strings` and `.stringsdict`
- `--no-skip-keys`: treat key-looking literals as translatable
- `--stringsdict <auto|report>`: auto-generate `.stringsdict` (default `auto`) or report-only

### translate
```
i18n-cli translate <projectRoot> <baseLang> <targetLangs>
```
- `targetLangs` is comma-separated, e.g. `fr,de,es`
- Requires `OPENAI_API_KEY`

## Example Workflows

### First Time Setup
```bash
./.build/release/i18n-cli extract /path/to/App en --apply
./.build/release/i18n-cli translate /path/to/App en "fr,de,es"
```

### Day-to-Day Updates
```bash
./.build/release/i18n-cli extract /path/to/App en --apply
./.build/release/i18n-cli translate /path/to/App en "fr,de,es"
```

## .stringsdict Behavior
Auto-generation is **strict** and only triggers for obvious plural formats like:
- `"%d moves"`
- `"%d move(s)"`
- `"%d tries"`

If your app uses interpolation like `"\(count) moves"`, it will be skipped and reported.
Use `--stringsdict report` to disable auto-generation.

## Outputs
- Base English: `<projectRoot>/en.lproj/Localizable.strings`
- Base plurals: `<projectRoot>/en.lproj/Localizable.stringsdict` (when generated)
- Cache + report: `<projectRoot>/.i18n-cache/*`

## Limitations
- SwiftUI-only extraction (no UIKit/AppKit yet)
- Interpolated strings are skipped and reported
- `.stringsdict` generation is strict and conservative

## Security
Do not commit API keys. Use `OPENAI_API_KEY` in your shell environment.

## Roadmap
- UIKit/AppKit extraction
- Interpolation handling for pluralization
- Advanced `.stringsdict` rules
- Homebrew/Mint install options

## License
MIT
