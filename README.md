# Yazhal

A music player maintained by **Kausthuban R S**.

**Repository:** [github.com/Kausthuban/Yazhal](https://github.com/Kausthuban/Yazhal)

## Original project

Yazhal was **cloned and updated from [Musify](https://github.com/gokadzev/Musify)**,
originally created by **Valeri Gokadze**. It builds on the custom implementation
based on upstream commit `52bd36828763b2d2be6e404b1ad3e867b22fcea7`.
Original copyright notices and the GPL v3-or-later license are retained.
See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

## Features

- Online playback, downloaded music and imported local audio.
- Generic audio and M3U/M3U8 playlist import; multiple selected music folders.
- User-selected download destination and optional foreground folder scanning.
- Offline metadata/artwork lookup through MusicBrainz and Cover Art Archive,
  with embedded-art extraction during Android scans.
- Suggestions informed by offline library and playback history.
- Optional FLAC catalogs/extensions, including Live Music Archive recordings.
- Bulk playlist/queue operations, recommendation refresh and draggable scrolling.
- Lyrics, equalizer, listening recaps and optional local-network synchronization.

Online metadata, FLAC sources and automatic scanning are configurable. Imported
originals are not rewritten. FLAC downloads preserve actual FLAC data; compressed
files are not relabeled as lossless.

## Setup and validation

Use Flutter **3.47.9**, Dart **3.13.7** and a full JDK **21**. Android configuration
uses SDK 36, minimum SDK 24, NDK 28.2.13676358 and CMake 3.22.1. Linux and Windows
sources are included; iOS is not supported.

```bash
flutter pub get
flutter analyze
flutter test --no-pub --concurrency=1 $(find test -name '*test.dart' ! -path 'test/fetch_audio_stream_live_test.dart' ! -path 'test/linux/media_controls_test.dart')
flutter build apk --debug --flavor github --target-platform android-arm64 --no-pub
```

`flutter pub get` regenerates localization and plugin registration files before
analysis/builds. The two excluded tests require live YouTube responses or a Linux
D-Bus session. Native-backend opt-in tests retain their documented skip conditions.
Physical-device playback, permission and external-service checks remain necessary.

[DEVELOPMENT.md](DEVELOPMENT.md) describes the feature settings and migration.
[EXTENSIONS.md](EXTENSIONS.md) documents the FLAC catalog contract.

## Source layout and Git

This distribution contains source, assets, platform projects, vendored dependencies,
tests and maintained documentation. APKs, caches, generated localization/plugin
files, previous delivery reports, screenshots and Git history are omitted.
`pubspec.lock` is intentionally retained for reproducible dependency resolution.
The `.gitignore` excludes generated output, local IDE/environment settings and
private signing files. No signing keys are supplied.

CI checks source changes on `main`. A separate manually triggered workflow builds
an ARM64 debug APK as an artifact; neither workflow publishes releases.
No code has been pushed to GitHub by this delivery.

## Application identity

Flutter package: `yazhal`. Android application ID: `com.kausthuban.yazhal`
(debug: `com.kausthuban.yazhal.debug`). Desktop identities, native channels,
sharing and local sync use Yazhal too. New playlist links use `yazhal://`.

Yazhal installs independently from previous app identities. Export a backup from
the previous app, restore it in Yazhal and select folders again. Private downloads
and Android folder grants do not transfer automatically. Pair local-sync devices
again with Yazhal on both sides. Automatic APK updates remain disabled until
Yazhal release distribution/signing is configured.
