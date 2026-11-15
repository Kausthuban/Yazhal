# Yazhal sources and extension compatibility

Yazhal 10.7.0 supports two distinct formats: declarative FLAC catalogs and real
Mornye/SpotiFLAC `.sflx` JavaScript extension packages. Neither is an arbitrary
repository-to-audio converter. An app's source repository is not a music catalog.

## Install a JavaScript provider

1. Open Settings → Music sources & repositories → Extension repositories.
2. The recommended index is the registry supplied for this project:
   https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json
3. Browse/refresh the repository, select a package and review its author, version,
   declared network hosts and license. SHA-256 is verified before parsing.
4. Install it. Packages start **disabled**, including updates. Open Music sources,
   configure any required account settings, then explicitly enable it.
5. Open Discover music / Search extensions and select a search provider. The
   selection is saved. Regular YouTube search remains available separately.

Public HTTPS JSON indexes, GitHub repositories containing `registry.json`, and
GitHub blob URLs are supported. A registry may list up to 1,000 entries and is
limited to 4 MiB. Index entries support snake_case/camelCase Mornye aliases:
`display_name`/`displayName`, `download_url`/`downloadUrl`, `sha256`/
`checksum_sha256`/`checksumSha256`. A checksum establishes consistency with the
index, not publisher trust. Repository refresh does not auto-install updates.

## JavaScript package contract

A `.sflx` package is a ZIP with `manifest.json`, `index.js` and retained license/
notice files. Its registry ID is stored separately from the manifest's internal
name, so legitimate aliases such as registry/package names can differ. Source
archives stay in app-private extension storage. Installed notices are available
in About even when a provider is disabled.

The host accepts up to 8 MiB compressed, 12 MiB declared uncompressed content,
100 entries, a 64 KiB manifest and 2 MiB JavaScript source. Archive directory
metadata is checked before decompression. Traversal, absolute paths, duplicate
names, symlinks, oversized entries and checksum/CRC mismatches are rejected.
Other files in the archive are retained but not extracted or executed.

The provider registers callbacks with `registerExtension({...})`. The synchronous
SDK currently implements:

- `http.get(url, headers)`, `http.post(url, body, headers)`, `http.head(url, headers)`.
  Responses expose statusCode/status, ok, body, headers and final URL.
- Scoped `storage.get/set/remove/clear`; settings and state are encrypted by
  platform secure storage. No plaintext fallback is used if the keyring fails.
- Silent `log` methods; `utils.md5`, `utils.sha256`, bounded `utils.sleep`, user-agent
  helpers and cancellation-query compatibility values.
- Local string/duration matching helpers and prepared download context.
- Provider callbacks such as searchTracks, getTrack, fetchLyrics and getDownloadUrl.

JavaScript runs in QuickJS on a worker isolate, not the UI isolate. The host
preserves the synchronous HTTP contract without rewriting third-party scripts.
A local native socket bridge delegates network I/O to asynchronous checked Dart
requests. Runtime calls are capped at two concurrent engines; queued calls are
bounded. Each VM defaults to 64 MiB heap, a 1 MiB stack and a 30-second evaluation
interrupt. Host calls have a 45-second outer deadline. HTTP/body/result/storage
quotas apply. These are application/VM controls, not an OS-process sandbox or a
claim that a JavaScript-engine vulnerability cannot exist.

The synchronous native bridge currently supports **Android and Linux**. Existing
Windows playback remains available, but JavaScript extension execution on Windows
is not implemented. The app does not have an existing iOS target.

## Permissions and credentials

Requests require public HTTPS, standard port 443, no URI credentials/fragments,
and declared hosts. Exact domains, `*.domain` and explicit `*` public-host grants
are recognized; the review dialog displays them. `*` never grants private-network
access. DNS results are checked and pinned at socket creation, and every redirect
is rechecked. Sensitive request headers are stripped on cross-host redirects.
Private/LAN HTTP, including private Jellyfin servers, is currently unsupported.

Only configure accounts and servers you are authorized to use. Tokens, passwords,
provider sessions and extension storage use platform secure storage and are not
exported in Hive backups. Android backup rules exclude the encrypted store and
its configuration. A new device requires credentials again. This does not change
the separate existing Local Sync pairing-key store described in SECURITY_AUDIT.md.

Provider artwork uses a separate checked fetch path, not a generic network-image
loader. Private/credential-bearing artwork URLs are rejected, redirects and DNS
are checked, bytes/pixel dimensions are capped, and a bounded private image cache
is used. The known JioSaavn public cover CDN is recognized alongside its declared
Saavn CDN. Credential-bearing image URLs are omitted; authenticated artwork may
therefore be unavailable. Sensitive fields/credential-bearing URLs are removed
from metadata persisted outside encrypted provider state.

## Download source and quality

Individual song downloads show the provider's declared quality options. Built-in
YouTube downloads offer high/medium/low original streams; these mean available
stream ranks, not fixed bitrate promises. Catalog FLAC downloads preserve the
original file. JavaScript quality IDs are passed unchanged to the provider.

When the search provider supplies metadata only, an individual download can select
an enabled audio provider, search for candidates, and **confirm the exact recording**
before selecting quality. The library retains the original metadata identity and
records the chosen audio provider/track and requested/reported quality. No silent
cross-source recording guess is made. Such results open Track information rather
than pretending the metadata provider supplies audio.

Playlist downloads ask once per source. Mixed-source playlists keep separate
quality choices. Bulk cross-provider recording matching for metadata-only lists
is not implemented: use the individual recording-confirmation flow. Existing
completed downloads are not silently overwritten or transcoded.

The current download host supports validated **direct audio URLs**. It uses the
existing staging/folder publication service, rejects obvious text responses and
checks FLAC magic. Lossy audio is never renamed to `.flac`. Native provider file
transfer/decryption, DRM/proprietary transfer adapters, browser-auth callbacks,
and async provider callbacks are **not implemented**. A package can support
metadata/search while its download path needs one of those additional adapters.

Compatibility evidence includes the unmodified JioSaavn 1.0.10 fixture: the native
VM resolves all five declared AAC quality IDs from prepared context, returning
AAC-in-MP4 (`.m4a`) rather than pretending to produce FLAC. Deezer's inspected
package exposes a native download path and no direct getDownloadUrl result, so
its native encrypted transfer is not supported here. Apple Music lyrics require
its account token/subscription where the provider says so. Other packages are
not certified universally compatible merely because they appear in the registry.

## Metadata and lyrics

Track information shows catalog/release fields and can fetch full metadata from
the original provider ID. Saving to the local library is explicit and does not
rewrite imported audio. Android folder scans extract title, artist, album,
embedded cover art, duration, album artist, genre, year, track/disc numbers,
composer, writer, MIME type and bitrate when the decoder exposes them. Actual
file-tag embedding/remuxing via Mornye/FFmpeg is not included.

Music sources contains a lyrics-provider selector. Enabled lyric extensions can
precede the existing LRCLIB/plain-text fallbacks. Mornye line timing, LRC and plain
responses are normalized with attribution. Successfully fetched lyrics are cached
for offline use (64 bounded entries); opening the lyrics side can use that cache
in offline mode. This is cache-after-lookup, not a promise that every download has
automatically fetched or embedded lyrics. Word-by-word TTML translation/pronunciation
editing and Mornye's home-feed/album/artist browsing UI are not ported.

## Declarative FLAC catalogs

Settings → Music sources → Declarative FLAC catalogs retains the existing format:

```json
{
  "schemaVersion": 1,
  "id": "my-catalog",
  "name": "My catalog",
  "searchUrl": "https://catalog.example.org/search?q={query}",
  "allowedHosts": ["catalog.example.org", "audio.example.org"]
}
```

The endpoint returns `{ "tracks": [{ "title": "Track", "artist": "Artist",
"format": "flac", "audioUrl": "https://audio.example.org/track.flac" }] }`.
Illustrative domains must be replaced with a real endpoint. Catalog manifests
are limited to 64 KiB, responses to 4 MiB/100 candidates; custom hosts match
exactly, and downloads are capped at 2 GiB. The optional built-in Live Music
Archive provider remains disabled until enabled. It searches live recordings,
not arbitrary commercial catalogs. Declarative catalogs execute no JavaScript.

A registry entry with `runtime: "yazhal-catalog-v1"` can embed a manifest or link
`manifestUrl` with a mandatory SHA-256 digest. JavaScript entries use
`runtime: "javascript"` (or the Mornye default) and a verified `.sflx` URL.


## Provider compatibility evidence

| Provider | Evidence in this delivery | Remaining limitation |
| --- | --- | --- |
| JioSaavn 1.0.10 | Unmodified source loads in native QuickJS; all five AAC quality IDs resolve correctly from prepared context. | Real account/network/catalog availability is not certified by the fixture. |
| Apple Music 1.4.17 | Manifest and source inspected; synchronous SDK and lyric-response interfaces implemented. | Authenticated lyrics/subscription and live service behavior need account/device verification. |
| Deezer 1.3.11 | Manifest/source inspected; metadata/search can use the documented synchronous SDK. | Its package exposes native download/decryption rather than direct getDownloadUrl; that transfer is not implemented. |
| Jellyfin 1.1.1 | Manifest/source inspected; wildcard public-host and line-lyrics contracts recognized. | Private/LAN HTTP is blocked; live server/account behavior is unverified. |
| Other registry packages | Listed and hash-verified installation is supported when the package format is valid. | Not individually certified; native/async/browser-auth dependencies may require adapters. |

This matrix distinguishes implemented host interfaces from tested provider
behavior. Installation or a declared `download_provider` type does not prove
that the complete provider-specific transfer pipeline is supported.
