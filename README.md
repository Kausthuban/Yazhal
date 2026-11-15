# Yazhal

<img src="assets/icons/yazhal_icon.png" alt="Yazhal harp logo" width="128">

A music player maintained by **Kausthuban R S**.

**Repository:** [github.com/Kausthuban/Yazhal](https://github.com/Kausthuban/Yazhal)

## Latest playback and connection fix — 10.8.3

The pinned HTTPS transport now performs the TLS handshake with the original
provider hostname. Playback reads initial audio bytes while the remaining track
fills the temporary cache, without waiting for the complete file. AAC tail
metadata and unknown-length streaming startup are handled without an unnecessary
full-download wait or duplicate initial request.

See [the connection and buffering report](docs/HTTPS_AND_BUFFERING_10.8.3.md)
for verification and device-testing limits. Existing source attribution and
provider availability requirements continue to apply.

## Original project

Yazhal was **cloned and updated from [Musify](https://github.com/gokadzev/Musify)**,
originally created by **Valeri Gokadze**. It builds on the custom implementation
based on upstream commit `52bd36828763b2d2be6e404b1ad3e867b22fcea7`.
Original copyright notices and the GPL v3-or-later license are retained.
See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

## Features

- Context-aware Next/Previous, automatic continuation and shared media controls.
- Manual queue priority, Play Next, drag reordering and context continuation.
- Persistent Favourite Songs with visible row hearts, Play All and Shuffle.
- Adaptive streaming, bounded next-song preloading and data-saver controls.
- Verified JavaScript extension packages, source selection and secure provider settings.
- Per-track and per-provider playlist download quality selection.
- Explicit cross-source recording selection for metadata-only downloads.
- Native provider metadata, richer embedded Android tags and persistent lyrics cache.
- Source repositories, reviewed catalog installation and saved source selection.
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

## Mornye attribution and compatibility

Yazhal 10.7.0 adds a real QuickJS compatibility host for synchronous
[Mornye](https://github.com/mornyeapp/Mornye) / SpotiFLAC `.sflx` extensions:
reviewed install, secure settings, source selection, search, metadata, lyrics
and validated direct audio URLs. The recommended repository is the
[user-supplied registry](https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json).

Mornye is by **Zarz Eleutherius (zarzet) and contributors**, LGPL-3.0-only.
The JioSaavn fixture is by **HemanthJabalpuri**, with Mornye compatibility fixes.
Individual package authors, source URLs and license notices appear in About.
See [NOTICE.md](NOTICE.md) and [EXTENSIONS.md](EXTENSIONS.md).

Compatibility is capability-based, not universal: the current host runs on
Android/Linux and supports the synchronous APIs documented in EXTENSIONS.md.
Browser-auth callbacks, arbitrary extension file APIs, encrypted/native transfers,
async provider callbacks and the full Mornye Rust backend are not implemented.
JioSaavn's unmodified package is exercised by the native tests; other providers
may require accounts or additional adapters. Never assume every listed package
can download audio simply because it can be installed or searched.

[Implementation summary](docs/IMPLEMENTATION_SUMMARY.md) and
[security audit](docs/SECURITY_AUDIT.md) describe this update, test evidence and
remaining device-validation requirements.

## Setup and validation

Use Flutter **3.47.9**, Dart **3.13.7** and a full JDK **21**. Android configuration
uses SDK 36, minimum SDK 24, NDK 28.2.13676358 and CMake 3.22.1. Linux and Windows
sources are included; iOS is not supported.

```bash
flutter pub get
flutter analyze
python3 tool/build_extension_test_runtime.py
export FLUTTER_QJS_NEXT_LIBRARY="$PWD/build/native_extensions/libflutter_qjs_next_plugin.so"
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
files, temporary test logs, screenshots and Git history are omitted. Maintained implementation and security reports are included under `docs/`.
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

### Local listening statistics backup (10.7.1)

Yazhal does not require an app account or login. In **Settings → Local statistics
backup**, export a readable JSON file, open the Android share sheet, or restore a
previous file. The file contains listening totals, per-song play counts and the
offline listening history used for local suggestions. It excludes downloaded
audio, playlists, device file paths, settings, provider credentials and pairing
secrets. Restoring replaces statistics rather than adding counts, so importing
the same file repeatedly does not duplicate plays. Keep the file private if you
do not want to share your listening history. Optional extension providers may
have their own authentication requirements; these are separate from Yazhal's
local statistics and are never included in this backup.


### Playback and discovery update (10.8.0)

The app paints a branded splash before plugin initialization and uses an optimized
AOT preview APK. Local sync initializes in the background. Discovery uses the
selected extension; YouTube search is off by default. A pinned, attributed
JioSaavn adapter offers AAC up to 320 kbps, preserving language metadata for
recent-listening recommendations. Provider quality settings apply to streaming;
Download asks for an available quality and saves a separate library copy.

The circled question-mark button on Discover and Music sources explains repository
setup, source capabilities, quality, and authorization. **Amazon is not enabled**:
the current Mornye Amazon package requires signed-session/session-grant host
features and an encrypted-transfer adapter absent from this app. Official Amazon
Music developer access must be approved; no public SDK alone enables it. Apple
metadata/lyrics support does not grant full Apple Music audio playback.

Current and next tracks use a bounded progressive disk buffer, with a configurable
128–1024 MiB budget and Clear temporary audio in Settings. Five/twenty-second
buffer targets refer to decoded audio, not exact compressed byte boundaries.
Data saver disables speculative next-track caching. Large tracks exceeding a
per-file budget stream without filling the cache. Notification shuffle/repeat,
player swipe dismissal, long-press selection in the bottom navigation bar,
headset mappings, frequent playlists and local statistics remain account-free.

See [feedback implementation and verification](docs/USER_FEEDBACK_10.8.0.md).
The supplied AOT preview installs as `com.kausthuban.yazhal.preview` (Yazhal
Preview), separately from the previous debug app, because its signing key is
unavailable. Export/restore the local statistics JSON and reselect music folders.
The clean source ZIP contains no signing keys. Create your own release key before
publishing or use a private test key for repeat preview installations.

### Online search repair (10.8.1)

Search now uses one rounded field with a provider button inside its left edge.
JioSaavn remains the default. Provider outages show Retry and Change provider;
changing source preserves and reruns the query. The picker also offers the
existing optional Live Music Archive FLAC catalogue and compatible installed
sources. Archive contains live concert recordings and has a different catalogue.
Download choices include quality and source, for example `AAC 320 kbps (JioSaavn)`.

Validated DNS address fallback and public NAT64 support improve mobile network
compatibility. JioSaavn HTML outage pages are reported as unavailable, rather than
empty search results. Upstream availability still varies by region/network. No
YouTube fallback is enabled. The 10.8.1 preview uses the same test-signing identity
as 10.8.0 and can update it without uninstalling. See
[online search implementation and verification](docs/ONLINE_SEARCH_10.8.1.md).

### Original search restored as a provider (10.8.2)

Choose **YouTube (Musify)** from the button inside the search bar to use the
original song-search backend. Its **Classic Musify search** action opens the
retained artist/album/playlist/history interface. The provider selector stays
available in the normal Search tab; choosing another source changes the search
route explicitly. Song artwork still follows the non-YouTube artwork policy.

The JioSaavn response guard now accepts valid JSON even when the server labels
it `text/html`; it no longer mistakes that header for an error page. JioSaavn's
API returned HTML errors on one network and valid song data through
an independent retrieval path, so a global outage cannot be assumed. The new
**Check source** screen compares DNS, HTTPS, direct API and installed-adapter
behavior on the phone and offers a redacted copyable report. No third-party
scraper/proxy is added to runtime. See
[restored search and JioSaavn findings](docs/RESTORED_SEARCH_10.8.2.md).
