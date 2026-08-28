# Changelog

_Generated from release tags with `bash bin/generate-changelog`._

## v1.8.0 … v1.7.17 (2026-08-28)

### Features
- feat(stories): add slower speech rates and remember the choice (#81)

### Fixes
- fix(ci): cut the release tag on the pubspec bump commit (#77)

### Other Changes
- release: v1.7.16
- release: v1.7.17
- release: v1.8.0

## v1.7.16 (2026-08-29)

### Other Changes
- release: v1.7.15
- ci: dispatch the Android release build after tagging (#75)

## v1.7.15 … v1.7.0 (2026-08-28)

### Features
- feat(practice): one Read/Listen/Speak switcher over one story (#45)

### Fixes
- fix(subscription): collapse dead IAP branches, await purchase acknowledgement, gate purchasing flag on stream (#48)
- fix(auth): reject requests when token retrieval fails (#52)
- fix(auth): log out and return to login on a 401 (#57)
- fix(auth): stop token refresh from re-entering AuthInterceptor (#62)
- fix(auth): stop getToken from returning a stale token after refresh failure (#64)
- fix(api): wire connectTimeout to Dio Options.connectTimeout (#65)
- fix(vocabulary): bound the add-word retry loop (#69)
- fix(ui): guard setState/context use after async gaps (#70)
- fix(config): fail loudly when API_BASE_URL is unset (#71)

### Refactors
- refactor(constants): collapse duplicate AppConstants, drop dead constants (#54)
- refactor(utils): delete dead timezone utilities (#55)
- refactor(foundation): extract shared InputValidator mixin (#56)
- refactor: share a single JWT decode path in TokenUtils (#73)

### Other Changes
- release: v1.6.0
- release: v1.7.0
- release: v1.7.1
- release: v1.7.2
- release: v1.7.3
- release: v1.7.4
- release: v1.7.5
- release: v1.7.6
- release: v1.7.7
- release: v1.7.8
- release: v1.7.9
- release: v1.7.10
- release: v1.7.11
- release: v1.7.12
- chore: remove duplicate dead DialogService files (#72)
- release: v1.7.13
- release: v1.7.14
- test: add unit tests for InputValidator mixin (#74)

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

