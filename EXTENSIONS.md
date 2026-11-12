# Optional FLAC catalog extensions

Open Settings → FLAC sources & extensions → Install catalog extension (.json).
Review the listed hosts, then enable the extension. Importing or updating an
extension always leaves it disabled until you enable it.

A catalog extension is a small declarative JSON document, not executable code:

```json
{
  "schemaVersion": 1,
  "id": "my-catalog",
  "name": "My FLAC catalog",
  "searchUrl": "https://catalog.example.org/search?q={query}",
  "allowedHosts": ["catalog.example.org", "audio.example.org"]
}
```

This URL is illustrative: replace it with your own compatible catalog endpoint.
`{query}` is replaced with URI-encoded search text. All URLs must be HTTPS without
credentials, fragments, or nonstandard ports. Custom hosts match exactly (there
are no wildcard subdomains). Include final audio/CDN hosts if the source redirects.
Manifests are limited to 64 KiB. IDs start with a lowercase letter and use 3–40
lowercase letters, digits, underscores or hyphens; `archive` is reserved.

The endpoint returns JSON:

```json
{
  "tracks": [
    {
      "title": "Song title",
      "artist": "Artist",
      "album": "Album",
      "format": "flac",
      "audioUrl": "https://audio.example.org/music/track.flac",
      "attribution": "Artist / catalog credit"
    }
  ]
}
```

The catalog response is limited to 4 MiB and 100 candidate entries. Entries need
a title, declared FLAC format, and an allowed audio URL. Up to five redirects
are followed, validating the host and HTTPS scheme at every hop. Downloads use
a private staging file and check the native FLAC signature before publication;
a failed download never becomes a completed library entry. There is a 2 GiB
per-file download limit. Selected-folder writes use the existing storage layer.

No authentication headers, API secrets, JavaScript, Dart plugins, HTML scraping,
or arbitrary executable plugins are supported in v2. For an API with another
response shape, expose a compatible catalog adapter rather than placing scripts
in a manifest. Extensions do not replace the standard search automatically.

The bundled Live Music Archive provider uses Archive's advanced-search API,
limits discovery to `collection:etree`, reads each item's metadata/files, and
exposes `.flac` files only. A query expands at most four items and 80 files.
The provider is disabled by default. Live availability and catalog completeness
can change independently of Yazhal.

Reference API documentation:
- https://archive.org/developers/metadata.html
- https://archive.org/advancedsearch.php
- https://musicbrainz.org/doc/Development/XML_Web_Service/Version_2/Search
- https://musicbrainz.org/doc/Cover_Art_Archive/API
