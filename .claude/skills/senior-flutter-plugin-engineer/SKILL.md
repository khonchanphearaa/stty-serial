---
name: senior-flutter-plugin-engineer
description: Implement, debug, refactor, test, or review the tty_serial Flutter plugin (Android /dev/tty* serial without the NDK, plus the TCN vending driver-board library) pinned to Flutter 3.13.9 / Dart 3.1.5 and Android API 19, with attention to public API design, hardware safety, security, clean reusable code, data structures, and slow-device performance. Use for any Dart or Java change in this package.
---

# Senior Flutter plugin engineer

This is a public package: other people's machines will run it and turn motors
with it. Deliver the requested behavior as a small, reviewable change with a
stable API, safe defaults, and tests. Keep the solution proportional.

Use the project rules in `CLAUDE.md`. If it is missing, ask before assuming
the toolchain or scope.

## 1. Establish the contract

1. Confirm the toolchain: `F313` (`~/Development/flutter_sdks/flutter-3.13.9/bin/flutter`)
   for development, `F335` (plain `flutter`) only for compatibility checks.
2. Read the code, tests, `pubspec.yaml`, and `CHANGELOG.md` you will touch.
3. When porting from `../eroxii/vending_app`, read the original and its tests
   first. Port behavior that was verified on the board; do not "improve"
   protocol timing or byte handling from memory.
4. For protocol facts (bytes, timings, reply codes), cite the source: the
   supplier PDF, `docs/` here, or the vending app's verified code. If sources
   disagree, report it instead of choosing one silently.
5. State what will change, what will not, and any assumption.

## 2. Version safety

- Dart 3.1.5 only: records, patterns, sealed and class modifiers are fine.
  Not available: extension types, digit separators, `_` wildcards,
  null-aware elements, dot shorthands. Check the 3.13.9 SDK source when unsure.
- Java at source level 8, Android APIs at or below 19. Check each new
  framework call against its `Added in API level`.
- Native code in Java, not Kotlin. No NDK.
- The plugin must build with AGP 7.3 (Flutter 3.13.9) **and** AGP 8 (new
  Flutter); keep the conditional `namespace` block.
- A new dependency needs a written reason and must support Dart 3.1.5 and
  minSdk 19. Prefer none.

## 3. Public API design

- Design from the caller's side first: write the README example, then the API.
- Minimal surface. Export deliberately from `lib/tty_serial.dart` and
  `lib/tcn.dart`; everything else in `lib/src/`.
- Make wrong use hard: typed commands instead of raw bytes, enums instead of
  magic numbers, immutable config objects validated in the constructor.
- Results that can fail in expected ways are sealed result types
  (`DispenseOutcome`); misuse and I/O failures are sealed exceptions
  (`SerialException`). Never return `null` to mean "error".
- Name by domain meaning (`dispense`, `readTemperature`), not by protocol
  byte (`sendDC`).
- Every public member gets `///` docs: what it does, units, limits, and which
  errors it throws.
- Breaking changes: avoid them; if needed, deprecate first with
  `@Deprecated('Use X; removed in 0.N')`, bump the minor version before 1.0,
  and record it in `CHANGELOG.md`.

## 4. Native layer rules (Java)

- The native layer is generic serial. It must not learn TCN or any other
  device protocol.
- Validate every MethodChannel argument: presence, type, range, size. Reject
  with a stable error code (`notFound`, `permissionDenied`, `busy`,
  `configFailed`, `closed`, `timeout`, `invalidArgument`), never a raw stack trace.
- Blocking I/O runs on a single-thread executor per port, so commands on one
  port stay ordered and one slow port never blocks another. Reply to Flutter
  on the main thread.
- Every loop and wait is bounded: deadlines with `SystemClock.uptimeMillis()`,
  sleeps between polls, caps on discarded bytes.
- Clean up on `onDetachedFromEngine`: close every port, shut down every executor,
  clear the open-path registry.
- Shell: `stty` only, built from validated values. Root (`su`) is a fallback
  for `stty` and for the opt-in `stopProcess`, nothing else.

## 5. Hardware safety

- No valid reply means **unknown**, not failure: never retry motor commands
  automatically, and keep `unknown` distinct in every result type.
- One command on the wire per port. Discard stale input before each write.
- All TCN packets go through one private check (complements, group, allowed
  commands). Adding a command means changing that check and its tests in the
  same change.
- Test mode, reset-all, and factory commands are not exposed.
- Defaults are the safe choice (drop check off is the documented exception,
  matching the vending app; say so in the docs).

## 6. Clean, reusable code

- Small classes with one job: transport, protocol, board. Pure functions for
  packet building and parsing.
- Depend on small interfaces at real boundaries (serial transport, clock) so
  tests use fakes. No generic layers "for later".
- Extract shared code only for shared behavior. Three similar lines beat a
  premature abstraction.
- Strict null safety; no `!` without a proven invariant; no `dynamic` in
  public APIs; `final` fields; `const` constructors where possible.
- `dart format`; `analyze` clean on F313 and F335. Comments explain why.

## 7. Data structures and algorithms

- Bytes: `Uint8List`, built once per packet; no per-byte list growth in hot
  paths. Checksums and complements are O(n) over at most a few bytes.
- Lookups: `Map<int, Port>` for handles (O(1)); `Set<String>` for open paths.
- Command queue: a `Future` chain (FIFO, O(1) enqueue), as `_exclusive` in the
  vending app; no unbounded queues without a limit.
- `SlotLayout`: `Set<int>` of pair starts, validated once in the constructor;
  `motorFor` is O(1).
- State complexity in docs when it matters to callers.

## 8. Testing

- Dart unit tests (`F313 test`) with fake transports: every packet against the
  PDF examples, the vending app's `tcn_script_packets.json` byte for byte,
  every reply status to its outcome, queue ordering, the command check,
  config validation.
- Java JUnit (`./gradlew :tty_serial:testDebugUnitTest` in `example/android`):
  path patterns, config to `stty` arguments, argument limits.
- Example app builds on both SDKs. Board tests on the dg3188 are manual: say
  exactly what was run on hardware and what was not.
- A bug fix starts with a failing test when the behavior can be tested off-device.

## 9. Completion report

Report: what changed, public API changes (and whether breaking), checks run
with results and on which SDK, what was **not** tested on a real board, and
remaining limitations. Update `CHANGELOG.md` for user-visible changes. Report
unrelated findings separately instead of fixing them silently.
