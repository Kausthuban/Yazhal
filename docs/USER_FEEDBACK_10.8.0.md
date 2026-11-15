# Yazhal 10.8.0 (192): user-feedback implementation

This update starts from the delivered 10.7.1 source. No code was pushed to GitHub.
The app requires no login. Local statistics remain exportable/shareable JSON;
playlist popularity is now included, with sanitized IDs and idempotent restore.

## Request status

| # | Change | Implemented behavior / limit |
|---|---|---|
| 1 | Startup | Branded first Flutter frame before async Hive/audio initialization, background local-sync init, AOT release-mode preview. No physical-phone startup benchmark claimed. |
| 2 | Source instructions | Circled ? on Discover and Music sources; full guide covers repositories, authorization, metadata vs audio, quality and buffering. |
| 3 | Higher quality | Pinned JioSaavn adapter enabled at first setup; up to AAC 320 kbps; streaming quality per provider; actual recording availability applies. User-installed/disabled provider preferences are retained. |
| 4 | Progressive buffer | Play promptly while full current audio streams to bounded temporary disk chunks; next actual queue item starts warming once buffered ahead >=5 seconds and bandwidth permits. Native target 20-second minimum/5-minute max buffer. 5/20 seconds are decoded-time targets, not exact VBR byte segments. Cache quota and safe clear added. Oversize or unknown-length files stream directly. |
| 5 | Download naming | Download replaces Make available offline, with quality selection in player; existing downloaded-file tap does not silently delete it. |
| 6 | Playback without Download | Playback resolves native provider audio itself; downloads are separate. Integration test plays a provider song without calling Download and checks actual source/quality. |
| 7 | Mornye Apple/Amazon | Current registry and packages inspected. Apple package provides metadata/lyrics. Amazon requires signed-session/session-grant and encrypted-transfer host features not implemented here; incompatible providers are clearly blocked. No SDK/credentials bypass. |
| 8 | Language recommendations | Preserve JioSaavn language; strongly weight recent plays; two recent Tamil plays outweigh old English history. Provider queries and ranking respect language; manual language preference available. Cold-start/unknown-language results still depend on provider catalogue. |
| 9 | Search source | YouTube search default off; selected extension drives discovery. Amazon-primary request remains blocked by authorization/host requirements; JioSaavn is the working default. No silent YouTube search fallback. Existing YouTube IDs may still need legacy playback support. |
| 10 | Swipe player down | Dismisses player route and restores previous screen; playback continues. |
| 11 | Time Machine logo | Render supplied colored harp image directly instead of monochrome ImageIcon masking. |
| 12 | Home ordering | Frequent user playlists, frequent songs and recent songs precede suggested playlists. Playlist counts start accruing from this version and are included in stats export. |
| 13 | Artwork | Block YouTube artwork hosts; provider covers and matched iTunes/Apple-CDN catalogue art with artist/title/duration checks; existing MusicBrainz/Cover Art Archive retained. No per-row artwork catalogue lookup. |
| 14 | Imported list scrolling | Constant-time offline lookup, cached row/context selection sets, correct displayed index for sorted/filtered playlists, bounded cover decoding, lazy rows; 5,000-row widget fling test. Physical-device frame timing pending. |
| 15 | Headset mappings | Single toggle/double Next/triple Previous; configurable tap window 150–500 ms (280 default), recorded >=4-tap custom pattern <=2 s, seek actions. Dedicated Next/Previous immediate. Single-button multipress needs a short grouping delay; instant-single option disables grouping. Headsets/OS may consume click patterns before delivering them. |
| 16 | Selection | Long press activates bulk selection; bottom navigation replaced by inline actions, no top Select songs button. Desktop/standalone list fallback uses bottom dock. |
| 17 | Notification | Transparent monochrome harp small icon, colored harp fallback large artwork, Previous/Play/Next plus Shuffle/Repeat custom actions. Android decides visible action count/layout. Physical notification/headset validation pending. |

## Architecture and root causes

Default discovery and recommendations previously queried YouTube independently of
extension selection and language. Preloading waited until <=45 seconds remained
and only warmed a short relay prefix. Extension playback could wait for a separate
download path; imported content URIs were copied before audio opened. Playlist
rows used the index of a sorted/filtered list against a different underlying list,
and repeated offline-song lookup scanned the entire library for each row.

The existing unified playback sequence remains the authority for context and
manual-queue priority. The new PlaybackCache wraps that same actual-next item,
shares active/speculative transfer jobs, cancels obsolete preloads and bounds
reads to 64 KiB. No full audio files are held in Dart memory. Download paths stay
separate. Native Android content URIs open directly for playback after a readable
asset-descriptor check. Provider URL resolution deduplicates a short-lived cache;
quality/provider identity are part of cache keys. Long-list row lookup uses an
indexed map. Metadata enrichment runs after playback starts and is bounded/cached.

## Source review and authorization

- Mornye: https://github.com/mornyeapp/Mornye
- Registry: https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
- Mornye extensions: https://github.com/mornyeapp/Mornye-Extension
- Official Amazon overview: https://developer.amazon.com/docs/music/get_started_program-overview.html
- Apple catalogue API: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/

Reviewed current registry packages: Amazon 2.3.19, Apple 1.4.17, JioSaavn 1.0.10.
Amazon's official API is closed beta and has no public SDK; approved developer
access and OAuth/security-profile setup are needed. Downloading another app's
SDK does not grant service access. This build does not impersonate Mornye sessions
or expose protected-service decryption keys. Public Apple catalogue metadata is
separate from MusicKit playback. Attribution and licenses remain in README,
NOTICE, About and each installed package. The bundled JioSaavn derivative changes
only language propagation; source JS and original notices are in its archive.

## Security delta

| Severity | Finding | Resolution |
|---|---|---|
| Medium | A full provider-song map could carry transient authorization headers into recently-played Hive history. | Strip `_extensionHeaders`, `_streamHeaders`, `_resolvedStreamUrl` before saving. Integration test checks credential values absent from persisted history. |
| Medium | Deferred progressive-source network opening could delay rejection of prohibited URLs until after source creation. | Validate public HTTPS and source permissions before constructing source; retain DNS/redirect permission checks in transfer and range requests. Existing SSRF tests rerun. |
| Medium | Unsupported signed-session/encrypted providers could appear enabled/playable. | Explicit unsupported-feature readiness check, block enable, filter discovery, reject decryption-key downloads. |
| Low | Buffer storage/network usage could grow without a quota or cancelled speculative work. | Quota/per-file cap, current/next sharing, obsolete cancellation, content-type/range validation, timeout and safe clear; Data saver honors no speculative transfer. |

New backup fields accept only bounded safe playlist IDs/counts and exclude paths,
credentials, settings and audio. Provider installs retain digest/permission checks.
No app authentication server, browser uploads or new SQL backend is introduced.
This is a change-focused security review with tests, not a claim that every
third-party dependency or remote extension is free of vulnerabilities.

## Verification

- Full regression suite: **336 passed, 9 skipped**, no failures; serial execution with the real native QuickJS test library. The live-YouTube and Linux D-Bus test files are excluded; the nine per-test skips retain their explicit opt-in/controller conditions.
- `flutter analyze --no-pub`: **No issues found** on the final project.
- Cache-specific tests cover first bytes before transfer completion, shared current/next request, promotion, safe clear, invalid HTML retry, oversize and unknown-length direct streaming.
- Widget checks cover splash first frame, swipe dismissal, navigation-bar selection, 5,000-row lazy rendering/fling, short headset grouping, and 320×740 screens at 130% text scale. Screenshots were inspected with real text fonts. New settings/help pages include scrollable space above the persistent navigation/mini-player.
- Optimized Android `githubRelease` preview: ARM64 and x86_64 split builds succeeded. Phone APK: **18,221,451 bytes**, minimum API 24, target API 36, versionCode 2192, package `com.kausthuban.yazhal.preview`.
- APK signature, ZIP CRC, architecture, packaged provider asset, 16 KiB ZIP alignment and >=16 KiB native ELF LOAD alignment passed. APK SHA-256: `ec0f1092dbb7edfb41456c9a4514b1b84a3e05eb64d6a987160a8577a73f05eb`.
- Software Android API 28 emulator: installed/launched successfully, confirmed JioSaavn default selection and circled help guide; selected a SAF Downloads folder, scanned/imported three generated WAV files, started playback directly with Play All, and observed the persistent mini-player and three-item native media-session queue. Native media Next and Previous advanced/restored the context without adding a manual queue. The full-screen player showed live progress and duration; a downward swipe restored the prior Offline songs screen while playback continued. Shuffle and Repeat custom actions are present in Android's media session; the status bar renders the harp-shaped small icon.
- The emulator runs without hardware acceleration; its startup/transfer timings are not phone performance measurements. Live JioSaavn audio quality/download availability and paid-service authorization were not validated in the emulator network. Native prepared AAC-320 resolution and online playback are covered by runtime/handler tests with controlled responses.
Hardware audio controls, live Amazon/Apple authorization, mobile-network behavior,
phone cold-start timings and OEM notification layouts require real devices and
service access. Widget/handler tests simulate platform behavior and do not certify
physical AirPods, wired headsets or Bluetooth hardware.
