# Yazhal 10.7.0 extension and branding update

This delivery includes all prior playback/queue/security work described below,
plus a real synchronous QuickJS extension host. See EXTENSIONS.md for the exact
compatibility contract; this is not the full Mornye Rust backend.

New user-facing work:

- Verified `.sflx` installation from the supplied registry, disabled-by-default
  updates, encrypted settings/state, permission review and retained author licenses.
- Search-provider selection, metadata-only track information and explicit
  cross-source recording confirmation for individual audio downloads.
- Per-track quality selection and per-source playlist quality choices, preserving
  actual container/codec and audio-source provenance.
- Richer Android embedded metadata extraction; source metadata inspection and
  explicit library updates; line-timed/plain extension lyrics and offline cache.
- Checked provider artwork, a clearer teal source-management/search UI and the
  supplied harp image across app, Android launcher/splash/themed icons and Windows.
- Mornye, registry, engine, provider authors and original Musify attribution in
  README/NOTICE/About. The original JioSaavn fixture retains its own license.

Native engine evidence: the installed QuickJS core was compiled with GCC/G++ and
exercised through Flutter tests. Real unmodified JioSaavn code resolves the five
AAC qualities; synchronous HTTP, private-host refusal and CPU-loop interruption
are tested. Provider accounts/live catalogs, native Android builds and hardware
remain outside this environment's completed validation. Android/Linux host
support is implemented; JavaScript execution on Windows is not implemented.

Final validation: **305 passed, 9 conditional skips**, static analysis clean.
This is 14 additional tests over the 291-test enhanced-source baseline. The
native QuickJS core was compiled locally; the reproducible CI helper also built
successfully. Physical Android/AirPods/Bluetooth checks, native Android packaging
and authenticated/live provider verification are still pending. No remote push
or release was performed. A phone-width source-manager layout test passes;
Flutter test rendering uses its test font, so this is layout evidence rather
than a claim of complete on-device visual verification.

The following sections retain the earlier playback implementation findings, with
repository/runtime descriptions updated for this delivery.

Review date: 2026-11-13. Starting source: Kausthuban/Yazhal commit
`824bde48b568359437da62844e0fdc3eb5ec1283`, verified against all 567 files in
the previous clean source package. No remote branch or release was changed.

## Playback root cause and implementation

Search and recommendation rows could replace the queue with only the tapped
song; other paths called playback directly without maintaining queue position.
The rest of the displayed context was lost. Single-item playback also advertised
Rewind/Fast Forward rather than Next/Previous to media sessions.

`PlaybackSequenceManager` now retains the original ordered context separately
from the playback projection and flags manually inserted occurrences. Displayed
song lists provide an ordered `PlaybackContextScope`; tapping a result starts
that full context at the tapped occurrence. Existing playlist, album, artist and
favourites play callbacks keep using the shared handler. Duplicate tracks have
separate queue-entry identities.

Add to Queue inserts after pending manual additions, ahead of remaining context.
Play Next inserts immediately after the current song. Once manual requests are
played, the original list continues. Changing context retains pending manual
requests. Clearing manual additions preserves the current song and context.
Repeat All starts another context cycle without repeating consumed manual
requests. Shuffle keeps manual priority and can restore the original order.

The existing audio_service/just_audio handler remains the single playback owner.
Headset/media-session commands, in-app controls and completion use the same
Next/Previous paths. Next advances even with Repeat One selected; Repeat One
applies to automatic completion. Previous returns to the prior occurrence, or
seeks to the start when already at the beginning of the list. Existing repeat,
seek, shuffle, duration/progress and SponsorBlock handling are retained.

## Queue, player and favourites

The existing queue sheet is reused, with current/upcoming/manual labels, an
initial queue snapshot, drag reordering and individual removal. Queue state lives
in the handler across navigation. Mini-player and full-player navigation use the
same handler capability checks. Active playback is retained when the Android
task is removed. The existing Android background service is retained.

Song rows now show a reactive heart. Favourite Songs uses the existing persistent
liked-song library and Play All/Shuffle page. Local favourites are deduplicated
as well as online tracks. Serialized writes preserve the most recent rapid-toggle
intent and concurrent changes across different songs. No playlist migration is
needed; existing liked songs remain favourites.

## Streaming and recovery

The adaptive policy estimates throughput from useful audio transfers rather than
extra speed-test traffic. It lowers quality quickly, raises it after sustained
samples and respects the user's configured quality ceiling. Changes apply at
song boundaries/reloads, not seamless mid-track bitrate switching. Settings add
Adaptive streaming, Streaming data saver and Preload next song. Data saver forces
low quality and disables speculative preloads. These policies apply to ordinary
YouTube audio; FLAC is not silently transcoded, and live radio/HLS retain their
existing streaming behavior. There is no automatic cellular/Wi-Fi detector.

Manifest, selected-stream and URL lookups coalesce concurrent requests. Quality
variants have separate caches. Downloads keep their configured quality.

When 3–45 seconds remain and at least eight seconds are buffered, the actual next
queue occurrence may preload at most 128 KiB. Manual priority is included. Only
one candidate is fetched; obsolete fetches are cancelled and stale resolutions
are ignored. Offline/local, FLAC extension and live items are not speculatively
fetched. A server must support a bounded range and a representation validator;
otherwise its body is cancelled. Cached prefixes are reused only after origin
revalidation. This improves startup opportunity without promising gapless audio.

The just_audio 0.10 error stream now triggers bounded retries of the same queue
occurrence, with position restoration, rather than skipping the user's song.
Delays are 1, 2, 4, 8, 15 and 30 seconds, plus request/load time. Pause, Stop and
track changes cancel obsolete recovery. Reconnection during these attempts can
resume playback; after exhaustion use Play to retry. This is bounded retry, not
an indefinite connectivity-monitor service.

## Repositories and source choice

Settings → Music sources & repositories retains the optional FLAC source manager
and adds Source repositories. Users can add/remove/enable/disable public HTTPS
indexes or GitHub extension repositories, browse/refresh entries, and review
compatible catalogs before installation. Remote manifests require a matching
SHA-256 digest; installs start disabled. Repository refresh never silently
installs or updates packages. Individual enabled catalogs or all enabled catalogs
can be selected in FLAC search, with the choice saved across restarts. Regular
search remains the YouTube source.

Mornye's registry/runtime interfaces were reviewed at
`45df9860661e9c4e731ef26a60c44b2b5d8cf125`. The supplied registry was retrieved and
sample archive hashes verified. Yazhal now executes the documented synchronous
JavaScript SDK through its own bounded QuickJS host. Arbitrary native file APIs,
encrypted transfers and browser-auth callbacks still need additional adapters.
Mornye is credited in README, NOTICE and About, alongside original Musify credit.
See EXTENSIONS.md for current compatibility and usage.

## Validation and release limits

The prior enhanced-source baseline had 291 passing tests and nine conditional skips. The final result for this delivery is recorded above. See SECURITY_AUDIT.md for the tool results and severity review. New tests cover
context order, duplicates, manual priority/continuation, shuffle, repeat cycles,
queue edits, simulated native completion/media commands, recovery, pause intent,
favourite persistence, source verification, private URL rejection, prefix reuse,
preload cancellation and adaptive/data-saver policy. The integration bridge is
deterministic; it does not decode audio or emulate physical Bluetooth hardware.

Before publishing an APK, complete the device checklist below. This workspace
does not provide an Android SDK/JDK build toolchain or a physical phone; no APK
build, headset test, on-device background test or live network-shaping test is
claimed. The existing mini/full player and other app features were regression
tested where covered; automated tests cannot establish that every feature works
on every device. iOS is not an existing supported target of this project.

1. On Android, start from search, an album and a playlist with no manual queue;
   exercise AirPods/Bluetooth Next/Previous, lock-screen actions and completion.
2. Insert Add to Queue and Play Next items, reorder/remove upcoming entries,
   change screens, and verify context continuation and Repeat One/All behavior.
3. Test screen-off playback, task removal, audio focus/phone calls, reconnecting
   Bluetooth, battery optimization and notification permissions on real devices.
4. Shape Wi-Fi/mobile bandwidth, disconnect/reconnect during playback and retry,
   verify position/intent and data-saver behavior, then check actual mobile bytes.
5. Test real public catalogs, FLAC decoding/downloads, selected Android storage
   folders, original-file imports, metadata/artwork, favourites and Local Sync.
6. Build debug and release Android flavors in the supplied workflows/toolchain;
   rerun the native desktop opt-in tests with libmpv/D-Bus before desktop releases.
