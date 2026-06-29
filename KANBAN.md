# i18n-cli Kanban

Task board for subagent execution. Each card is self-contained.

---

## Strategy

**One-line pitch:** Your app has 500 hardcoded English strings across 80 Swift files. One command finds them all via AST, rewrites your source, generates `.xcstrings`, and translates to 10 languages.

**Why this wins:** Every other tool in the landscape (Localization-CLI, xcstrings-translator, GPT-Localize-iOS, AITranslate) starts AFTER your code is already localized. They're translate-only. We're the only Swift-native tool that does **extract → migrate → translate** in one pass. The SwiftSyntax AST extractor is the moat.

**Three commands:**

```bash
# THE WEDGE — nobody else does this
i18n-cli migrate ./MyApp --langs fr,de,es

# TABLE STAKES — for ongoing updates
i18n-cli translate Localizable.xcstrings --langs fr,de,es

# SAFETY NET — CI gate for regressions
i18n-cli audit ./MyApp
```

**`migrate` does five things in one pass:**
1. AST walk finds all string literals in SwiftUI/UIKit contexts
2. Generates stable localization keys
3. Rewrites source in-place: `Text("Hello")` → `Text("app.hello_a1b2c3d4")`
4. Generates `Localizable.xcstrings` (modern format, NOT .strings)
5. Translates to all target languages via LLM, writes into same .xcstrings

**`translate` does the ongoing work:**
1. Reads existing .xcstrings, finds untranslated/stale keys via diff cache
2. Batch translates via LLM, validates placeholders
3. Writes back with `state: "translated"`

**`audit` catches regressions:**
1. Same AST walk as migrate, but read-only
2. Reports hardcoded strings that aren't localized
3. Exit code 1 if any found → use as CI gate in GitHub Actions

---

## Done

*No completed cards yet.*

---

## Review

*No tasks under review.*

---

## In Progress

*Nothing in progress.*

---

## Ready (Next Up)

### Batch 1: xcstrings output (makes migrate produce modern format)

- [ ] **IL-001**: XCStrings model + reader — new file `Sources/i18n-cli/XCStringsIO.swift`. Codable model for `.xcstrings` JSON: `XCStringsFile` with `sourceLanguage: String`, `version: String`, `strings: [String: XCStringEntry]`. `XCStringEntry` has optional `extractionState`, `comment`, `localizations: [String: XCLocalization]`. `XCLocalization` has either `stringUnit: XCStringUnit` (with `state` + `value`) or `variations: XCVariations` (with `plural` dict of `XCStringUnit` keyed by CLDR category). Reader: `func loadXCStrings(at url: URL) throws -> XCStringsFile` using `JSONDecoder`. Must handle: missing localizations = untranslated, state values (`new`, `translated`, `needs_review`, `stale`), plural variations. Tests in `Tests/i18n-cliTests/XCStringsIOTests.swift`: read minimal file, read with plurals, read with missing localizations. | Est: 90min | Skills: swift, json, codable

- [ ] **IL-002**: XCStrings writer — extend `XCStringsIO.swift`. `func saveXCStrings(_ file: XCStringsFile, to url: URL) throws`. Must: sort keys (matches Xcode output for clean git diffs), preserve `extractionState` and `comment`, set `state: "translated"` on newly written translations, pretty-print JSON with sorted keys. Tests: round-trip read→write→read preserves all fields, state update works, output matches Xcode formatting. | Est: 60min | Skills: swift, json

- [ ] **IL-003**: Migrate command outputs .xcstrings — modify `SwiftUIExtractorEngine.swift`. Add a new output path: after extraction, instead of (or in addition to) writing `Localizable.strings`, generate a `Localizable.xcstrings` file using the IL-001/IL-002 model. Each extracted key gets `sourceLanguage` value with `state: "translated"`, `extractionState: "manual"`. Controlled by flag: `--output-format xcstrings` (default) or `--output-format strings` (legacy). Wire flag through `ExtractCommand.swift` → engine. Tests: migrate produces valid .xcstrings, keys match extracted strings, round-trip is valid JSON. | Est: 75min | Skills: swift

- [ ] **IL-004**: XCStrings diff engine — new file `Sources/i18n-cli/XCStringsDiff.swift`. Given an `XCStringsFile` and a target language code, return `[String: String]` of keys needing translation. Key needs translation when: (a) target lang has no localization entry, (b) state is `"new"` or absent, (c) source value changed since last cached translation. Cache: `.i18n-cache/<lang>.xcstrings-cache.json` storing `[key: sourceValue]` at time of last translation. Tests: new keys detected, stale detected, already-translated skipped, empty cache = translate all. | Est: 60min | Skills: swift

### Batch 2: unified translate command + migrate end-to-end

- [ ] **IL-005**: Unified `translate` command for .xcstrings — new file `Sources/i18n-cli/TranslateXCStringsCommand.swift`. Replaces the old translate-only-strings path as the primary translate command. Signature: `i18n-cli translate <path.xcstrings> --langs <csv> [--provider openai|anthropic] [--model <model>] [--dry-run] [--context <app-description>]`. Flow: load xcstrings → diff per lang → batch translate → validate placeholders → write back → update cache → print summary. The `--context` flag appends app description to the LLM system prompt for domain-aware translations (e.g. "fitness tracking app"). Wire into CLI.swift. | Est: 90min | Skills: swift, cli

- [ ] **IL-006**: Wire migrate end-to-end — update `CLI.swift` with new `migrate` subcommand that chains: extract (AST walk + source rewrite + xcstrings generation from IL-003) → translate (IL-005). Signature: `i18n-cli migrate <project-root> [--langs <csv>] [--key-prefix <prefix>] [--dry-run] [--provider openai|anthropic] [--context <app-description>]`. If `--langs` omitted, extract-only (no translation). If provided, extract then immediately translate the generated .xcstrings. Single command, full pipeline. This is the hero command. | Est: 60min | Skills: swift, cli

- [ ] **IL-007**: `audit` command — new file `Sources/i18n-cli/AuditCommand.swift`. Same AST walk as extract engine but read-only (no file writes). Counts hardcoded string literals that are not using localization keys. Output to stdout: one line per finding (`⚠ File.swift:42 Text("Hello") — not localized`). Summary line: `Found 12 hardcoded strings in 4 files`. Exit code: 0 if clean, 1 if findings. Signature: `i18n-cli audit <project-root> [--include <csv>] [--exclude <csv>]`. Use in CI: `i18n-cli audit ./MyApp || exit 1`. | Est: 60min | Skills: swift, cli

---

## Backlog

### Phase 2: Expand AST extraction coverage

- [ ] **IL-008**: More SwiftUI views — extend `callContext()` in `SwiftUIExtractorEngine.swift` to detect: `Section("...")`, `Toggle("...")`, `Picker("...")`, `Menu("...")`, `TextField("placeholder", ...)` (first arg), `Link("...", destination:)`, `NavigationLink("...", destination:)`, `ProgressView("...")`, `GroupBox("...")`, `DisclosureGroup("...")`, `ShareLink("...", item:)`, `TabItem` content strings. Add each to the context matcher. Tests: one test case per new view type confirming extraction and skip-on-interpolation. | Est: 75min | Skills: swift, swiftsyntax

- [ ] **IL-009**: UIKit/AppKit detection — extend AST walker to detect: `NSLocalizedString("...", comment: "...")` calls, `String(localized: "...")` calls (already localized — skip or re-key), `.title = "..."` property assignments on UILabel/UIButton/UIBarButtonItem (heuristic: check if assignment target name contains known UIKit types). This makes `migrate` useful for mixed SwiftUI/UIKit codebases. Tests: NSLocalizedString detected, String(localized:) skipped, UILabel.title assignment caught. | Est: 90min | Skills: swift, swiftsyntax

- [ ] **IL-010**: `i18n-ignore` scope expansion — currently `// i18n-ignore` only works as trivia on the call expression. Support: `// i18n-ignore-file` at top of file (skip entire file), `// i18n-ignore-next` on the line before a call, `// i18n-ignore-block` / `// i18n-end-ignore` for ranges. Tests for each scope. | Est: 45min | Skills: swift, swiftsyntax

### Phase 3: Translation engine improvements

- [ ] **IL-011**: Anthropic API client — new file `Sources/i18n-cli/AnthropicClient.swift`. Same interface as `OpenAIClient.translate(pairs:targetLanguageCode:)`. Use `ANTHROPIC_API_KEY` env var. Endpoint: `https://api.anthropic.com/v1/messages`. Model default: `claude-sonnet-4-6`. Extract shared JSON response parsing from `OpenAIClient` into `Sources/i18n-cli/ResponseParser.swift` — both clients use it. Tests: mock response parsing. | Est: 75min | Skills: swift, api

- [ ] **IL-012**: Provider protocol + factory — `protocol TranslationProvider`. `OpenAIClient` and `AnthropicClient` conform. Factory picks provider from `--provider` flag. Wire into translate + migrate commands. Remove direct client instantiation from command files. | Est: 45min | Skills: swift, protocols

- [ ] **IL-013**: Placeholder validation — new file `Sources/i18n-cli/PlaceholderValidator.swift`. Post-translation check: verify `%d`, `%@`, `%ld`, `%.2f`, `%1$@`, `%2$d`, `%%`, `\n` from source appear in translation. Warn on mismatch (stderr), don't block. For plural variations, validate per-variant. Tests: match passes, missing `%d` caught, reordered positional accepted, `%%` literal not false-flagged. | Est: 60min | Skills: swift, regex

- [ ] **IL-014**: Plural-aware translation — when a key has `variations.plural` in source, send all variant values with explicit CLDR plural category instructions for target language. Write back as `variations.plural`, not flat `stringUnit`. Tests: English one/other → French, German, Arabic plural categories. | Est: 90min | Skills: swift, i18n, cldr

- [ ] **IL-015**: Translation memory — `.i18n-cache/tm.json` stores every `(sourceText, targetLang) → translatedText` pair. Check TM before LLM call. On exact match, use cached (zero API cost). `--no-tm` to skip, `--clear-tm` to reset. Report hit rate in summary. | Est: 60min | Skills: swift, json

### Phase 4: CLI polish + distribution

- [ ] **IL-016**: Migrate CLI to swift-argument-parser — replace hand-rolled argparse with Apple's `swift-argument-parser`. `@main struct I18NCLI: AsyncParsableCommand` with subcommands: `Migrate`, `Translate`, `Audit`. Free `--help`, typed flags, validation. | Est: 90min | Skills: swift, swift-argument-parser

- [ ] **IL-017**: README rewrite — three-command hero section. Quick start showing `migrate` one-liner. "How it works" diagram. Comparison table vs Lokalise/Crowdin/other CLIs. Collapsible `<details>` for legacy .strings workflow. Badges: Swift version, license, CI. | Est: 45min | Skills: docs

- [ ] **IL-018**: CI workflow — `.github/workflows/ci.yml`. Push/PR: `swift test` on macOS-latest. Tag push: build universal binary (arm64 + x86_64), attach to GitHub Release. | Est: 45min | Skills: github-actions

- [ ] **IL-019**: Homebrew tap — `homebrew-tap` repo with formula pointing at GitHub Release binary. `brew tap thisisprabha/tap && brew install i18n-cli`. | Est: 30min | Skills: homebrew

- [ ] **IL-020**: Blog post — "I built a CLI that localizes your entire Swift app in one command." Cover: the problem (500 hardcoded strings), the approach (AST extraction), the result (before/after). Include real terminal output. Publish on vadapayasam.github.io via agent-publish. Cross-post to Dev.to, Swift forums, r/iOSProgramming. | Est: 90min | Skills: writing

### Phase 5: Advanced

- [ ] **IL-021**: Glossary — `--glossary <path>` JSON mapping terms to preferred translations per language. Inject into LLM system prompt. | Est: 60min | Skills: swift

- [ ] **IL-022**: `.xcloc` export — generate Xcode Localization Catalog bundles for human translator handoff. | Est: 120min | Skills: swift, xliff

- [ ] **IL-023**: `--context-screenshots <dir>` — for vision-capable LLMs, include UI screenshots in translation prompt so the LLM sees where the string appears. | Est: 90min | Skills: swift, multimodal

---

## Architecture

### Current file map

```
Sources/i18n-cli/
├── CLI.swift                    # Entry point — needs: migrate, translate, audit subcommands
├── ExtractCommand.swift         # Arg parsing for extract — becomes migrate internals
├── ExtractReport.swift          # JSON report model — keep, extend for audit
├── KeyGenerator.swift           # English → key slug — keep as-is, solid
├── OpenAIClient.swift           # LLM client — keep, extract shared parsing later
├── StringsIO.swift              # .strings read/write — keep for legacy path
├── SwiftUIExtractorEngine.swift # AST walk — THE CORE, expand view coverage
├── TranslateCommand.swift       # .strings translate — keep for legacy
└── TranslationSupport.swift     # .stringsdict + cache — keep, extend cache for xcstrings
```

### Target file map

```
Sources/i18n-cli/
├── CLI.swift                         # Three subcommands: migrate, translate, audit
├── MigrateCommand.swift              # NEW: chains extract → xcstrings gen → translate
├── TranslateXCStringsCommand.swift   # NEW: standalone xcstrings translation
├── AuditCommand.swift                # NEW: read-only AST scan, CI gate
├── XCStringsIO.swift                 # NEW: .xcstrings Codable model + read/write
├── XCStringsDiff.swift               # NEW: untranslated key detection
├── PlaceholderValidator.swift        # NEW: format specifier QA
├── ResponseParser.swift              # NEW: shared LLM response parsing
├── TranslationProvider.swift         # NEW: protocol + factory
├── AnthropicClient.swift             # NEW: Claude API
├── SwiftUIExtractorEngine.swift      # EXPANDED: more SwiftUI views, UIKit patterns
├── KeyGenerator.swift                # Unchanged
├── ExtractReport.swift               # Extended for audit output
├── OpenAIClient.swift                # Conforms to TranslationProvider
├── TranslationSupport.swift          # Extended cache for xcstrings
├── ExtractCommand.swift              # Legacy, wired through migrate
├── StringsIO.swift                   # Legacy .strings path
└── TranslateCommand.swift            # Legacy .strings translate
```

### .xcstrings JSON schema (for agents)

```json
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "app.hello_a1b2c3d4": {
      "extractionState": "manual",
      "comment": "Greeting on home screen",
      "localizations": {
        "en": {
          "stringUnit": { "state": "translated", "value": "Hello" }
        },
        "fr": {
          "stringUnit": { "state": "translated", "value": "Bonjour" }
        }
      }
    },
    "app.items_count_e5f6g7h8": {
      "localizations": {
        "en": {
          "variations": {
            "plural": {
              "one": { "stringUnit": { "state": "translated", "value": "%d item" } },
              "other": { "stringUnit": { "state": "translated", "value": "%d items" } }
            }
          }
        }
      }
    }
  }
}
```

### SwiftUI views the extractor catches (current + planned)

**Current:** `Text`, `Button`, `Label`, `.navigationTitle`, `.alert`, `.confirmationDialog`

**IL-008 adds:** `Section`, `Toggle`, `Picker`, `Menu`, `TextField`, `Link`, `NavigationLink`, `ProgressView`, `GroupBox`, `DisclosureGroup`, `ShareLink`

**IL-009 adds:** `NSLocalizedString(...)`, UILabel/UIButton `.title` assignments

---

## Execution Rules

1. Agent picks top card(s) from **Ready**
2. Reads referenced source files for context
3. Implements → writes tests → runs `swift test`
4. Moves card: Ready → In Progress → Done (with date)
5. Commits: `feat(IL-XXX): description`

**Batch 1 (IL-001 through IL-004)** ships xcstrings I/O. These four can be built in parallel — no interdependency within the batch.

**Batch 2 (IL-005 through IL-007)** wires the three user-facing commands. IL-006 depends on IL-003 + IL-005. IL-007 depends only on the existing extractor engine.

**Promotion:** When Ready is empty, promote next batch from Backlog.
