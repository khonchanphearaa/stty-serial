---
name: pub-release
description: Prepare and check a tty_serial release for pub.dev - version bump, CHANGELOG, README, license, example, dual-SDK checks, pub publish dry run. Use when the user asks to release, publish, tag, or check if the package is ready for pub.dev. Never publishes without explicit go-ahead.
---

# pub.dev release checklist

Publishing is public and permanent: a version on pub.dev can be retracted but
not deleted. Prepare everything, run every check, then **stop and ask** before
`pub publish`, `git tag`, or `git push`.

## 1. Preconditions (stop if any fails)

- The user confirmed the release and the version number.
- License chosen and the owner (eRoxii) approved publishing. `LICENSE` holds
  the real text, not the template's `TODO`.
- No protocol material that may be confidential (supplier PDF text, copied
  scripts) is in the package. Facts and code written from them are fine only
  if the user confirmed the rights.
- Working tree clean except for release files.

## 2. Package metadata

- `pubspec.yaml`: `version`, a `description` of 60-180 characters,
  `repository` (or `homepage`), `issue_tracker`, `topics` (up to 5, e.g.
  `serial`, `android`, `kiosk`, `vending`, `hardware`). Constraints remain
  `sdk: '>=3.1.5 <4.0.0'` and `flutter: '>=3.13.0'`.
- Version follows semver. Before 1.0: breaking change → minor bump, otherwise
  patch.
- `CHANGELOG.md`: a section for this version, user-facing language, breaking
  changes first.
- `README.md`: what it is, supported devices (rooted Android, `/dev/tty*`
  readable and writable, busybox or root `stty`), the Flutter/Android
  compatibility table (Flutter 3.13.x for Android 4.4; newer Flutter for
  newer Android), installation, a short example, the safety rules (unknown
  outcome is never retried; typed commands only; root is opt-in), known
  limitations, and what was tested on real hardware.
- `example/` runs and shows the main flow.

## 3. Checks (run all, report each result)

```bash
F313=~/Development/flutter_sdks/flutter-3.13.9/bin/flutter
export GRADLE_USER_HOME=~/.gradle-kitkat-java11-v2
dart format --output=none --set-exit-if-changed lib test example/lib
$F313 analyze
$F313 test
(cd example/android && ./gradlew :tty_serial:testDebugUnitTest)
(cd example && $F313 build apk --debug --target-platform android-arm)
flutter analyze            # 3.35.4: what pub.dev users and the score see
(cd example && flutter build apk --debug)   # AGP 8 build path
(cd example && $F313 pub get)               # restore the 3.13.9 lockfile
$F313 pub publish --dry-run
```

Optional: `dart pub global run pana .` for the pub.dev score preview.

The dry run must show 0 warnings. Check its file list: no `build/`, `.dart_tool/`,
`local.properties`, keystores, or `.env` files. Add a `.pubignore` if needed.

## 4. Hardware sign-off

Ask the user to confirm the release was run on a real board (the dg3188 at
minimum): open port, read temperature, LED on/off, one lane with drop check
off. Record in the report what was and was not run.

## 5. Publish (only after explicit go-ahead)

1. Commit release files: `release: vX.Y.Z`.
2. `$F313 pub publish` (the user completes the browser sign-in).
3. Tag `vX.Y.Z` and push the tag, only if the user asked.

## Report

Version, changes, every check with its result and SDK, hardware tests done and
not done, dry-run warnings, and the next step waiting on the user.
