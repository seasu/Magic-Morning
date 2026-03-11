# AGENTS.md

## Cursor Cloud specific instructions

### Overview

MagicMorning (Magic Sticker) is a Flutter mobile app (Android-first, iOS Phase 2) with Firebase Cloud Functions backend. Two components need dev tooling:

| Component | Path | Language | Dev commands |
|---|---|---|---|
| Flutter App | `/workspace` | Dart | See `README.md` "快速開始" section |
| Cloud Functions | `/workspace/functions/` | TypeScript (Node 22) | `npm run build` / `npm run lint` |

### Environment

- **Flutter SDK**: installed at `/opt/flutter` (v3.29.1), already on `PATH` via `~/.bashrc`
- **Android SDK**: installed at `$HOME/android-sdk`, configured via `flutter config --android-sdk`
- **Node.js 22** + npm: pre-installed on the VM
- **Java 21**: pre-installed on the VM

### Key commands

- **Lint (Flutter)**: `dart analyze --fatal-infos` — must pass before every commit (see `CLAUDE.md` checklist and `.claude/skills/flutter-ci-guard/SKILL.md`)
- **Test (Flutter)**: `flutter test`
- **Build APK**: `flutter build apk --debug`
- **Cloud Functions build**: `cd functions && npm run build`
- **Cloud Functions lint**: `cd functions && npm run lint` — note: `.eslintrc` config is not committed; ESLint will fail until the config file is added

### Gotchas

- The first `flutter build apk` on a clean VM takes ~12 minutes because Gradle downloads dependencies and Android SDK auto-installs NDK/CMake/platform packages. Subsequent builds are much faster.
- `google-services.json` is present in the repo at `android/app/google-services.json` (placeholder project). For real Firebase features, replace with your own.
- `CLAUDE.md` mandates bumping `pubspec.yaml` version and updating `PRD.md` before every commit. Follow this rule.
- Linux desktop toolchain is not set up (ninja, GTK3 missing) — this is fine; the app targets Android/iOS only.
- The `functions/` ESLint config (`.eslintrc.js` or similar) is not committed to the repo; `npm run lint` will fail. TypeScript compilation (`npm run build` / `tsc`) works fine.
