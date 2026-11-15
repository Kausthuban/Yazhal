# Android test build 10.7.1 (191)

## Changes in this build

- Settings now opens a dedicated local listening-statistics backup page.
- Export saves a readable JSON file; Share opens the system share sheet; Restore
  validates the file and asks before replacing current statistics.
- Includes listening totals, per-song counts and offline listening history.
- Excludes audio, playlists, file paths, provider credentials and pairing secrets.
- Restore replaces rather than merges counts. Importing twice is idempotent.
- No Yazhal account, login, or cloud backup is required. Android automatic app
  backup is disabled. Optional extension-provider credentials remain separate.
- Android explicitly applies the Kotlin plugin required by the project's current
  `android.builtInKotlin=false` compatibility configuration.

## Rebuild

Use Flutter and the Android SDK, then run:

```sh
flutter pub get
flutter build apk --debug --flavor github --split-per-abi --target-platform android-arm64,android-x64
```

The supplied phone APK targets **ARM64**. A separate x86_64 build is used for emulator checks. This is an installable **debug/test APK**, signed with the Android debug key.
Package: `com.kausthuban.yazhal.debug`; minimum Android API 24 (Android 7.0).
The ARM64 split APK uses version code 2191 (Flutter architecture prefix + base code 191).
Use your own private release signing key before distributing a production build.
Signing keys, SDKs, caches and build outputs are excluded from the source ZIP.

## Automated verification

- Static analysis: no issues.
- Regression suite: 312 passed, 9 conditional skips.
- Seven new backup tests cover round-trip data, exclusion of private fields,
  repeated restore, unchanged settings/favourites, invalid versions/JSON and
  oversized files, plus JSON MIME compatibility; UI tests open backup with
  offline mode both enabled and disabled.
- Live-stream and Linux desktop media-control tests are not part of this
  environment's Android verification run.

Physical-device Bluetooth/AirPods, real streaming providers, downloads and Android
file-picker/share-sheet behaviour still require device checks. Automated queue
and playback tests do not substitute for physical Bluetooth testing. Extension
compatibility limitations remain documented in `EXTENSIONS.md`.

## Package verification

- APK assembled successfully with Flutter 3.47.9 / Dart 3.13.7.
- ARM64 APK: 82,912,451 bytes; signature scheme v2 verified.
- ZIP CRC and Android zip alignment checks passed. ARM64 ELF load segments are
  aligned for 16 KiB pages. The package contains only ARM64 native libraries.
- SHA-256: `9cf69966df34e80edfbc75514b29da1d86c786039ea1a2b2eaaba27e062c28b0`.
- Corresponding x86_64 app installed on an Android 9 (API 28) software emulator
  and reached the home screen and Settings without login. The final ARM64 and
  x86_64 packages contain byte-identical Dart code/assets.
  The final JSON MIME parameter is covered by a file-picker contract test; it
  was added after the emulator launch checks.
- Android 16 software emulation could not boot within the test limit without
  hardware acceleration. ARM64 phone/Android 16 runtime checks remain pending.

The emulator was not used to benchmark performance. Two time-sensitive Local
Sync tests timed out during a run concurrent with APK compilation and software
emulation. A parallel-only run also failed a relative responsiveness threshold.
The complete suite then passed with `--concurrency=1`: 312 passed, 9 conditional
skips, in 1 minute 47 seconds. Timing checks should run without competing test
processes; no assertions were weakened to get the passing result.
