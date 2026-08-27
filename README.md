# new words [![Android CI](https://github.com/shukebeta/new_words/actions/workflows/android_ci.yml/badge.svg)](https://github.com/shukebeta/new_words/actions/workflows/android_ci.yml)

**A vocabulary learning app that actually helps you remember.** new words lets you capture words as you encounter them, review them through spaced repetition, and reinforce them with AI-generated stories — all from a single cross-platform app.

It targets three problems that generic flashcard apps ignore:

- **Context loss** — words are saved with AI-generated explanations and example sentences, not bare definitions
- **Passive review** — spaced repetition surfaces words when you're about to forget them, not on a fixed schedule
- **Isolated drilling** — story generation embeds your recent words into a short narrative for immersive reinforcement

Aimed at language learners who read and listen in their target language and want to close the loop from "encountered this word" to "actually know this word."

## Features

```
Vocabulary
 ├─ add word ──────────→ wait for AI explanation + examples, then show the word
 ├─ word list ─────────→ paginated list, delete, mark for review
 └─ word detail ───────→ full explanation, TTS pronunciation

Memory (spaced repetition)
 ├─ daily practice ────→ due words surfaced automatically
 └─ review session ────→ mark known/unknown, reschedule accordingly

Stories
 ├─ generate ──────────→ AI writes a short story using your recent words
 ├─ library ───────────→ browse and re-read generated stories
 └─ reading progress ──→ track position across sessions

Practice (one switcher on the story: Read | Listen | Speak)
 ├─ read ──────────────→ sentence-by-sentence playback, tap any sentence
 ├─ listen ────────────→ dictation and vocab cloze, typed answers scored locally
 ├─ speak ─────────────→ say the sentence back, get a word-accuracy score
 └─ playback options ──→ speed, repeat each sentence twice, continue to the next
                         sentence (repeat applies in all three modes)

Practice is also one tap from a word: word detail → Practise this word opens a
story that uses it, or offers to generate one.

Settings
 ├─ language ──────────→ English / Chinese UI
 ├─ account ───────────→ register, login, token auto-refresh
 └─ in-app purchase ───→ subscription via Google Play billing
```

> Speaking ships on Android and iOS. It needs microphone access —
> `RECORD_AUDIO` on Android, microphone and speech-recognition permission on
> iOS — and uses the platform speech recognizer, which may send audio to the
> platform vendor. It scores the words you said, not how well you pronounced
> them.

## Prerequisites

- **Flutter 3.32.x** (stable channel)
- **Dart SDK ^3.7.2**
- A running backend that speaks the new_words API (configure `API_BASE_URL` in `.env`)
- For Android release builds: a signing keystore and Google Play credentials

## Setup

```bash
git clone https://github.com/shukebeta/new_words.git
cd new_words
cp .env.development .env      # or .env.staging / .env.production
flutter pub get
flutter run
```

The app loads `.env` at startup via `flutter_dotenv`. The file must be present at the project root — it is declared as a Flutter asset and bundled into the build.

## Environments

| File | `API_BASE_URL` | `DEBUGGING` |
|---|---|---|
| `.env.development` | `http://localhost:5116` | `1` |
| `.env.staging` | staging URL | — |
| `.env.production` | production URL | — |

Copy the relevant file to `.env` before running or building. CI copies `.env.production` automatically.

## Commands

```bash
flutter run                   # debug mode (hot reload enabled)
flutter run --release         # release mode on connected device
flutter build apk --release   # Android APK
flutter build ios             # iOS (requires macOS + Xcode)
flutter build web             # web app
flutter analyze               # static analysis
flutter test                  # unit and widget tests
dart format .                 # format all Dart files
flutter clean                 # clear build cache
```

## Architecture

Five layers, each with a single responsibility:

```
UI (Screens / Widgets)
        │
Provider  ← state management, loading/error states, auth lifecycle
        │
Service   ← business logic, validation, data transformation
        │
API       ← HTTP (Dio), request/response processing, typed exceptions
        │
Foundation ← BaseApi, BaseService, AuthAwareProvider, exception hierarchy
```

**State management**: Provider package. Auth-aware providers extend `AuthAwareProvider` and clear their state automatically on logout.

**Dependency injection**: GetIt service locator. All services and APIs are lazy singletons registered in `dependency_injection.dart`.

**Error handling**: typed exception hierarchy (`NetworkException`, `ApiBusinessException`, `ValidationException`) propagated from API → Service → Provider → UI without raw `dynamic` catches.

**Navigation**: named routes in `MaterialApp`. Main scaffold uses `LazyLoadIndexedStack` with a responsive bottom nav (mobile) / rail nav (desktop).

## CI / CD

| Workflow | Trigger | Output |
|---|---|---|
| `android_ci.yml` | PR + push to `master` | fast CI: `flutter analyze` (non-blocking), `flutter test`, debug-compile smoke — no artifact |
| `android_release.yml` | `v*.*.*` tag or manual | signed release APK attached to GitHub release |
| `web_release.yml` | release tags | web build deployed |
| `changelog.yml` | release | `CHANGELOG.md` auto-updated |

Release builds are tagged `v<major>.<minor>.<patch>`. The in-app update feature checks GitHub Releases for a newer APK and prompts the user to install it.

## Project structure

```
lib/
├── apis/              # HTTP layer (Dio, typed request/response)
├── common/            # shared widgets, models, services
├── entities/          # data models and DTOs
├── features/
│   ├── auth/          # login, register
│   ├── add_word/      # add word flow
│   ├── new_words_list/# word list screen
│   ├── word_detail/   # word detail and editing
│   ├── memories/      # spaced repetition review
│   ├── stories/       # story generation, library and the practice host
│   ├── practice/      # listening and speaking modes, scoring, exercise sets
│   ├── settings/      # app settings
│   ├── main_menu/     # root scaffold and navigation
│   ├── home/          # home screen
│   ├── app_update/    # in-app update from GitHub
│   └── legal/         # terms / privacy
├── providers/         # Provider state classes
├── services/          # business logic
└── utils/             # helpers and constants
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full layer breakdown and V2 migration guide.
