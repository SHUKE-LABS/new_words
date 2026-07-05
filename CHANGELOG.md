# Changelog

_Generated from release tags with `bash bin/generate-changelog`. Unreleased entries below cover commits ahead of the latest tag._

## Unreleased

Commits since `v0.9.9` (2026-01-10), grouped by area. They will be folded into the next tag by `bin/generate-changelog`.

### Features
- Add in-app update functionality from GitHub releases — [\#11](https://github.com/shukebeta/new_words/pull/11) (`1c2352a`)
- Add comprehensive README with architecture, features, and setup guide (`8876b58`)
- Split Android workflow into CI and Release workflows (`00575a7`)

### Bug fixes
- Improve translation removal for Latin-based languages (`9a24cfc`)
- Increase API request timeout limits for better reliability (`2aca86e`)

### Chores
- Automated versioning and changelog workflow — [\#12](https://github.com/shukebeta/new_words/pull/12) (`90fd170`)
- Update changelog (`e9f4a39`, `0d1e503`)

> Note: `CHANGELOG.md` is regenerated from release tags by `bin/generate-changelog`. Until the next tag is cut (the auto-release workflow in `.github/workflows/release.yml` does this on merge to `master`), the entries above are hand-maintained under "Unreleased".

## v0.9.9 (2026-01-10)

### Other Changes
-  Add Android release workflow for automated APK builds