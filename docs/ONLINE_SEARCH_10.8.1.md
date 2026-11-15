# Yazhal 10.8.1: online search repair

## Changes

- A normal rounded search field replaces the two-field form and introductory block. The small button inside the left edge opens a source picker. JioSaavn is the first-setup default; the user's explicit selection persists.
- Retry and Change provider appear on provider/network failures. Messages never display JavaScript stacks, request URLs or credentials. Empty results are distinguished from provider outages and offline mode.
- Switching provider keeps the query and reruns it. An older in-flight response cannot overwrite the new provider's results. Editing the query clears stale results; long-press selection resets with the query/provider.
- Enabled/compatible installed JavaScript sources and FLAC catalogues share the picker. A disabled compatible installed source can be explicitly enabled by selecting it. Unsupported signed-session/DRM host adapters remain unavailable rather than being presented as working providers.
- The existing Live Music Archive FLAC catalogue can be explicitly enabled from this picker as an alternative. It contains live concert recordings, not the same commercial catalogue as JioSaavn, so a Tamil/pop song available on one service may not exist on another. Add or manage sources opens the existing repository/extension settings.
- Download choices display real provider quality followed by its source: `AAC 320 kbps (JioSaavn)`, `AAC 160 kbps (JioSaavn)`, `Original FLAC (Live Music Archive)`. Selecting a label retains the original quality ID. No bitrate conversion or relabelling as lossless occurs.
- Offline playback and download storage continue through the existing services. No account or login is introduced.

## Failure diagnosis and network fix

The supplied screenshot's `Extension host request failed` came from a transport
exception obscured by a generic host message. Inspection confirmed that the
secure HTTP client tried only the first DNS address. A failed IPv6 or IPv4 route
therefore prevented it from trying another valid address.

The client now interleaves validated address families and starts staggered
connection attempts, with bounded timeouts and cancellation of obsolete attempts.
DNS answers are validated before any dial and passed as numeric addresses to pin
the actual connection. A mixed public/private DNS response still fails closed.
The RFC 6052 well-known DNS64 prefix is accepted only when its embedded IPv4
address is public. Private/loopback/mapped/reserved destinations, invalid schemes,
ports and redirects remain blocked. TLS certificate checks remain enabled.
These fixes cover confirmed transport defects; the screenshot alone cannot
identify the user's specific DNS answer or network route.

A separate live check of JioSaavn's upstream endpoint in the build environment
returned HTTP 200 with an HTML **Site Unavailable** page. The extension previously
silently interpreted this as no songs. The host now reports that endpoint's HTTP
errors and HTML outage pages as provider unavailability. A provider-side or
regional outage cannot be repaired by the app; Retry and explicit provider
selection are necessary. No unofficial proxy, access bypass or silent YouTube
fallback is added. A live Archive catalogue query returned HTTP 200 and results;
this does not guarantee availability on every mobile network.

## Verification

**Final results:** full serial regression suite **351 passed, 9 skipped**, no failures.
The live YouTube and Linux D-Bus test files are excluded; native-backend/controller
opt-ins retain their nine explicit skip conditions. Native QuickJS tests were run
with the compiled test library. `flutter analyze --no-pub`: **No issues found**.

All 15 added transport/UI tests passed. Real-font screenshots of the search error
and source picker were inspected at 320×740 with 130% text scaling. Provider
selection persistence is covered separately from the widget's asynchronous view
logic. Existing offline playback and queue tests passed in the full suite.

The optimized Android ARM64 and x86_64 preview builds succeeded. The delivered
phone APK is ARM64 only. Signature, ZIP CRC, manifest/version, 16 KiB ZIP alignment
and native ELF LOAD alignment checks passed. The certificate matches the 10.8.0
preview test certificate, allowing an update over that preview installation.
This version was not installed or live-streamed on the user's physical phone;
no carrier-specific or real-provider playback guarantee is implied.

Phone APK size: **18230735 bytes**. SHA-256:
`0f31d483af07ab16d5844d0444b167430006ba00d0257bd5d3b99a03e25c0c04`.

 Network tests use controlled
responses and injected address/dial functions, including a failed/stalled first
address, public NAT64, blocked private NAT64, mixed DNS refusal, cancellation,
and actual native QuickJS execution against HTML outage responses. UI tests
cover query preservation and rerun, stale-response protection, retry/offline mode,
quality/source labels and narrow-screen layout. Existing regression tests cover
offline playback, queue order, caching, recommendations and security boundaries.

Live JioSaavn service availability and phone-carrier behavior require a device
with access to that provider. No physical-headset or live paid-service claim is
made by these tests.

## Installation and sources

The optimized ARM64 preview has version 10.8.1 (193), package
`com.kausthuban.yazhal.preview`, architecture-prefixed versionCode 2193, and the
same preview test-signing identity as 10.8.0. Install it over **Yazhal Preview** to
retain its local data. It does not replace the older separately signed Yazhal
app. Keep the supplied private test-signing kit outside Git; the source ZIP
retains the existing ignore rules and excludes generated outputs and keys.

Original Musify, Mornye, JioSaavn adapter, Live Music Archive and other source
attributions remain in README, NOTICE, About and installed-package notices.
The bundled JioSaavn adapter itself is unchanged in this update.
