# Yazhal 10.8.2: original search provider and JioSaavn diagnosis

## What happened to Musify search

Musify's original online search uses YouTube through the app's existing
`youtube_explode_dart` client, formatter, artist and playlist services. That code
was retained, but the earlier request to turn YouTube search off routed the main
Search tab into extension-only search. The provider picker did not list YouTube.
A legacy global flag could also choose the old UI/data path independently of the
selected provider. This made the original search inaccessible as a normal source.

## Implemented behavior

- **YouTube (Musify)** now appears in the same provider picker as JioSaavn,
  installed compatible extensions and FLAC catalogues. Select the small button
  inside the left side of the search bar to choose it. It needs no extension
  installation. First selection enables it explicitly; JioSaavn remains the
  default until the user chooses a different source.
- The provider reuses the original Musify YouTube song-search client and song
  normalization. Existing video IDs, queue handling, playback and source-labelled
  download quality remain compatible. No fake FLAC/bitrate conversion is added.
- After selecting YouTube, **Classic Musify search** opens the retained original
  interface, including its artist, album, playlist, radio and search-history
  features. Return to the unified search page to change providers. Classic search
  and suggestions now honor offline mode.
- The normal Search tab always retains its provider selector, including after
  enabling YouTube. Selected source and the legacy YouTube enable flag are no
  longer treated as interchangeable. Switching back to JioSaavn does not silently
  keep sending searches/recommendations to YouTube.
- YouTube artwork remains excluded from song artwork, preserving the earlier
  non-YouTube artwork preference. Original Musify attribution and license notices
  remain intact.

## JioSaavn: what the investigation established

**Confirmed app bug fixed:** the 10.8.1 guard rejected any `text/html` MIME label
before parsing the response. The independent successful JioSaavn retrieval also
reported `text/html; charset=UTF-8` while containing song-search data. The host
now parses and validates JSON first, accepting valid song data even under an
incorrect MIME label. Only invalid/non-JSON bodies are classified as HTML error
pages. A valid JSON song title containing "Site Unavailable" is also no longer
misclassified. A native QuickJS regression test exercises valid JioSaavn search
JSON served with a `text/html` header. This is an actual app defect, although a
trace from the user's phone is still needed to confirm its particular failure.

Checks on **14 November 2026** reproduced HTTP **200**, content type **text/html**,
with a **Site Unavailable** page in the build network. These were not valid empty
song results. Five normal request variants (current web parameters, minimal
parameters, mobile context, autocomplete and cookie variant) failed this way.
Three further requests reproduced the adapter's full headers, Tamil-only language
cookie, and full headers without a cookie; these also returned the HTML page.
The response reported `server: envoy`, which alone cannot identify whether the
response originated from a provider edge or an intermediary.

An independent retriever successfully fetched the JioSaavn homepage and the same
`search.getResults` API query for **magale**, which returned valid song data and
`total: 627`, including a Tamil recording with the provider's 320 kbps flag.
This disproves a blanket claim that the API is globally unavailable or that the
query has no matching songs. The earlier broad outage explanation was not
sufficient: behavior depends on request/network path. It does **not** establish
whether the user's phone sees DNS failure, TLS failure, an API rejection, or an
adapter problem. No phone network trace was available during this build.

The supplied extension registry still lists JioSaavn **1.0.10**, upstream SHA-256
`e35852c5ced6b0ea651eea0867c5dac46c79482c4ae4602185186621b4044887`.
The bundled `1.0.10-yazhal.1` derivative retains its language-metadata patch; no
newer registry adapter was found to install as a presumed fix. No undocumented
proxy, scraper service or authentication/region bypass is added to the app.

Primary endpoints/repositories inspected:

- https://www.jiosaavn.com/
- https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&q=magale&p=1&n=1
- https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
- https://github.com/mornyeapp/Mornye-Extension

## How to identify the failure on the phone

With JioSaavn selected, tap **Check source → Run source check**. The checks run
only when requested and download no audio:

1. DNS resolves and validates public destinations. Only counts of IPv4/IPv6
   answers are reported; addresses are omitted.
2. Website HTTPS reports the response status/content type. A working website is
   explicitly distinguished from a working API.
3. A direct search API probe checks HTTP status, MIME, valid JSON and the expected
   results schema, using a fixed neutral query rather than listening history.
4. The installed adapter is tested independently with its actual current settings
   so header/storage/runtime differences are not mistaken for a global outage.

Reports distinguish DNS, blocked destination, TLS, timeout, HTTP refusal/rate
limit, HTML Site Unavailable, malformed JSON, and adapter failure. If one request
path works and another fails, the summary says so. If both fail, it does not claim
to prove a global outage or regional restriction. DNS failures stop unsafe or
impossible requests before HTTP. Diagnostics honor offline mode.

**Copy diagnostic report** copies the checked stages, safe codes, adapter version,
app version and timestamp. Credentials, request headers, user queries/history,
response bodies and device file paths are excluded. The report stays in memory
until copied; it is not uploaded automatically or included in stats backups.
Normal search also shows the specific Site Unavailable/rate-limit/refusal category
instead of a JavaScript stack trace.

## Verification

**Final validation:** full serial regression suite **368 passed, 9 skipped**,
no failures. The live YouTube and Linux D-Bus test files are excluded; nine
native-backend/controller tests retain explicit opt-in skips. Native QuickJS
cases used the compiled test library. Static analysis: **No issues found**.

The added checks cover explicit YouTube enable/select/persist, source switching,
original video IDs/metadata, the classic interface, offline-mode guards, direct
API versus adapter outcomes, safe diagnostic copying, DNS/private destination
refusal, narrow-screen layout, and actual QuickJS search JSON labelled text/html.
The literal phrase Site Unavailable in valid JSON does not falsely cause failure.

Optimized ARM64 preview assembly succeeded. Signature, ZIP integrity, manifest,
architecture, 16 KiB ZIP alignment and native ELF LOAD alignment passed. The
signing certificate matches earlier previews. AOT freshness was checked against
the last source edit, including the MIME fix. APK size: **18246587 bytes**.
SHA-256: `808831f9a0dc80298fc1d4d65c2cca1b9a277c70823e8feb5a43eb894c6f6055`.

This APK was not live-streamed or installed on the user's physical phone. Tests
and diagnostics do not certify provider availability or physical audio controls.

 Controlled
response tests do not certify the user's mobile carrier or live YouTube/JioSaavn
availability. Paid-provider authorization and physical audio-control behavior
remain outside these checks.

## Delivery

The ARM64 preview is version **10.8.2 (194)**, application ID
`com.kausthuban.yazhal.preview`, architecture-prefixed versionCode **2194**. It uses
the retained preview test-signing certificate, allowing installation over the
10.8.0/10.8.1 previews without uninstalling. This is an optimized AOT preview,
not a production-key release. The source ZIP excludes SDKs, generated files,
build output, caches and signing material and retains the Git ignore rules.
