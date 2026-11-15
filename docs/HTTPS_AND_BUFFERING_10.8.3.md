# Yazhal 10.8.3 — HTTPS and progressive playback

## Diagnosis

The supplied 10.8.2 device report resolved JioSaavn to public IPv4/IPv6
addresses, but website HTTPS, direct search, and the installed adapter all
failed with `network_unreachable`. That report alone cannot identify a global
outage, region restriction, or broken adapter.

Code inspection uncovered an application defect shared by these requests:
`PublicNetworkClient` supplied a custom `HttpClient.connectionFactory` that
returned a plain TCP socket. Dart's HttpClient does **not** wrap a custom
factory's direct socket in TLS. This was verified against the pinned Dart
3.13.7 SDK's `_ConnectionTarget.connect` implementation. HTTPS traffic therefore
could not complete correctly despite successful DNS/TCP connectivity. Earlier
mock transport checks did not exercise an actual TLS server and missed this.

The connection now races validated public DNS addresses for TCP, then uses
`SecureSocket.secure` with the **original provider hostname** before giving the
socket to HttpClient. SNI, trusted-root checks, certificate hostname validation,
private-network refusal, redirect restrictions and cancellation remain enabled.
No insecure certificate bypass, login, proxy service or new dependency was added.

This repairs the app-side transport defect. A provider can still be unavailable
or return an error after a correct TLS connection; this release does not certify
live JioSaavn availability on the user's phone. Re-run Settings/source
**Check source** after installing and share the new report if a failure remains.

## Initial audio and background filling

For normal finite audio with a known size within the cache budget:

1. Resolve the selected provider's actual stream URL and quality.
2. Start one continuous network transfer into a bounded temporary disk file.
3. Expose the arriving bytes to the decoder immediately; Android's initial
   playback buffer target remains **500 ms**, rather than a full-file wait.
4. Keep filling the rest of the track while it plays. Network chunks are read
   from disk in at most 64 KiB blocks, without loading a full track into RAM.
5. Reuse the cached track and preserve the existing bandwidth-aware next-track
   preloader, queue priority, cache quota and cache-clear controls.

A fixed five-second byte range cannot be calculated reliably for every variable
bitrate/container format. The decoder buffers playable audio while the transfer
continues; start time also depends on network speed, provider resolution and the
file's metadata layout. An unavailable source cannot be made playable by buffering.

Two startup defects were also fixed:

- **AAC/MP4 tail metadata:** a nonzero uncached range can now be fetched directly
  when the server advertises byte ranges, even for files smaller than 1 MiB.
  Previously the 1 MiB threshold could make the decoder wait for almost the
  complete small song just to inspect metadata at its end. The original full
  transfer continues; the range remains representation/ETag validated.
- **Unknown-size or over-budget tracks:** direct streaming reuses the already-open
  initial response. It no longer discards that response and repeats its GET/TLS
  setup. These tracks stream without being fully stored in the disk cache.

Existing Data Saver and cache-disabled preferences still use direct streaming.
Offline playback code and imported audio files were not changed. Cache controls
are under **Settings → Playback buffer**; clearing the buffer protects active
playback and keeps user downloads.

## Verification

New regression checks use a **real loopback HTTPS server**, not a mocked HTTP
response. An explicitly test-only certificate/key pair lives under
`test/fixtures/tls`; it is not included as an application asset or trusted by
the production app. Only test-injected dialing maps a public hostname to loopback.

- A pinned HTTPS request succeeds using the correct original hostname.
- A certificate for a different hostname is rejected.
- An untrusted certificate is rejected.
- A real HTTPS audio response yields its first part while the server deliberately
  withholds the rest; the rest later completes a single cached transfer.
- A sub-1-MiB AAC tail range is served before the original body completes.
- An over-budget stream makes one initial request, without filling the disk.
- Existing progressive cache, promotion, clear, retry, source, queue, security,
  offline and UI regressions remain in the suite.

**Validation:** full serial regression suite **373 passed, 9 skipped**, zero failures. Static analysis: **No issues found**. The live YouTube and Linux D-Bus test files were excluded; nine native-backend/controller tests retain their explicit opt-in skips. QuickJS cases used the native test library.

Optimized ARM64 preview assembly succeeded. Signature, manifest, ZIP integrity, architecture, 16 KiB ZIP alignment and native ELF LOAD alignment passed. The signing certificate matches the previous preview. AOT freshness was verified against the latest application source edit. APK size: **18248427 bytes**. SHA-256: `b0207c1eb1b620901aec3acc09b43add7152fe77d53d7419882f110d387bf108`.

Physical-device listening, Bluetooth/AirPods actions, and real JioSaavn playback
on the user's connection were not exercised here. These results establish the
transport/buffer behavior tested above, rather than a claim that every provider
or device is available and working.

## Build and attribution

Version **10.8.3+195**, ARM64 Android preview, Android 7.0/API 24 minimum.
The application ID and retained preview signing certificate match 10.8.2, so it
can update that preview without uninstalling it. This remains a test-signed
preview; production signing ownership has not changed.

Maintainer: Kausthuban R S. Yazhal derives from Musify by Valeri Gokadze.
Mornye/SpotiFLAC compatibility and individual extension authors remain credited
in README, NOTICE, About and the previous implementation reports. This update
adds transport and cache corrections rather than new third-party provider code.
