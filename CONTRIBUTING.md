# Contributing

Thanks for contributing!

## Development

### Build
```bash
swift build -c release
```

### Test
```bash
swift test
```

## Adding Extraction Rules
- Extraction logic lives in `Sources/i18n-cli/SwiftUIExtractorEngine.swift`.
- Keep new rules strict and deterministic.
- Add tests in `Tests/i18n-cliTests/ExtractorTests.swift`.

## Reporting Issues
Please include:
- The command you ran
- The input Swift snippet (minimal reproducible)
- The relevant section of `.i18n-cache/extract-report.json`
- Expected vs actual output

## Code Style
- Keep changes small and focused.
- Avoid unnecessary dependencies.
