# Changelog

_Generated from release tags with `bash bin/generate-changelog`._

## v1.7.3 … v1.7.0 (2026-08-28)

### Features
- feat(practice): one Read/Listen/Speak switcher over one story (#45)

### Fixes
- fix(subscription): collapse dead IAP branches, await purchase acknowledgement, gate purchasing flag on stream (#48)
- fix(auth): reject requests when token retrieval fails (#52)

### Refactors
- refactor(constants): collapse duplicate AppConstants, drop dead constants (#54)

### Other Changes
- release: v1.6.0
- release: v1.7.0
- release: v1.7.1
- release: v1.7.2

## v1.6.0 … v1.4.0 (2026-08-27)

### Features
- feat(stories): read story aloud sentence by sentence (#39)
- feat(practice): listening mode with dictation and vocab cloze (#43)
- feat(practice): speaking mode — say the sentence back, scored locally (#44)

### Other Changes
- release: v1.3.0
- release: v1.4.0
- release: v1.5.0

## v1.3.0 (2026-08-22)

### Features
- feat(settings): show current version (#33)

### Other Changes
- release: v1.2.1

## v1.2.1 (2026-08-18)

### Fixes
- fix: wait for ready explanation before add navigation (#31)

### Other Changes
- release: v1.2.0

## v1.2.0 (2026-08-02)

### Features
- feat: retry pending explanation adds automatically (#29)

### Other Changes
- release: v1.1.0

## v1.1.0 … v1.0.5 (2026-07-14)

### Features
- feat: surface Pending explanation status with Generate-now recovery (#26)

### Other Changes
- release: v1.0.4
- ci: fast-feedback Android CI (debug smoke + tests), fix runner abort (#25)
- release: v1.0.5

## v1.0.4 … v1.0.1 (2026-07-07)

### Fixes
- fix: gate LogInterceptor request/response body logging behind kDebugMode (#17)
- fix: correct update version check direction (#20)
- fix: replace raw print() in AuthInterceptor with app logger (#21)

### Docs
- docs: sync CHANGELOG and cross-cutting services with shipped code (#10) (#13)

### Other Changes
- Update changelog
- Split Android workflow into CI and Release workflows
- Update changelog
-  Improve translation removal for Latin-based languages
-  Add in-app update functionality from GitHub releases
-  Increase API request timeout limits for better reliability
- Add comprehensive README with architecture, features, and setup guide
- chore: automated versioning and changelog workflow (#12)
- release: v1.0.1
- release: v1.0.2
- release: v1.0.3
- feat/issue 18 redact dio log bodies (#22)

## v0.9.9 (2026-01-10)

### Other Changes
-  Add Android release workflow for automated APK builds

