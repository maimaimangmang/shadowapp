# Contributing

Use Apple Command Line Tools / Xcode with Swift 5.9 or newer.

```bash
bash scripts/test.sh
bash scripts/build.sh
```

Keep changes small and describe the behavior being fixed. Profile isolation, preserving existing data, and targeted process management are the critical invariants. Add focused checks when changing those paths. Do not add credential scraping, global environment changes, global process termination, or patches to Codex binaries.

Use `CODEX_MULTI_DATA_DIR` pointing at a temporary absolute directory for development. Do not reuse a real account’s data in automated tests. Test authentication manually with your own accounts, and report only the version and pass/fail result.

UI wording is bilingual through `Texts.t(Chinese, English)`. Avoid adding implementation details to the account flow unless they help users decide what to do.

Before release, update `docs/COMPATIBILITY.md` with actual observations. A successful build or two running processes does not prove two-account authentication isolation.
