# Attribution

Yazhal is maintained by Kausthuban R S at https://github.com/Kausthuban/Yazhal.

Yazhal was cloned and updated from **Musify**, originally created by **Valeri Gokadze**:
https://github.com/gokadzev/Musify

The custom source is based on upstream commit
`52bd36828763b2d2be6e404b1ad3e867b22fcea7` and the previously delivered custom v2.
Original copyright notices, the GPL v3-or-later license and third-party notices
remain in the source. Legacy playback/control assets derive from the original project. The current harp logo was supplied by Kausthuban R S.
The Yazhal rebranding does not claim original authorship of the upstream code.

## Mornye

Repository browsing, runtime compatibility checks and source selection were
inspired by [Mornye](https://github.com/mornyeapp/Mornye), by Zarz Eleutherius
(zarzet) and contributors, licensed LGPL-3.0-only. Reviewed revision:
`45df9860661e9c4e731ef26a60c44b2b5d8cf125`.

Yazhal implements its own declarative catalog client and synchronous JavaScript
SDK compatibility host. The Mornye Rust backend is not copied or bundled.
Repository-installed `.sflx` packages are downloaded only after user review and start
disabled. The pinned, attributed JioSaavn adapter below is bundled and enabled on first setup. Their exact source archive, manifest, author, repository and license
notices are retained. Installed package notices are accessible from About.
Original Musify attribution and Yazhal's GPL-3.0-or-later license remain unchanged.

## SpotiFLAC / Mornye extensions

Recommended registry supplied by the project owner:
https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json

The inspected registry links packages from https://github.com/mornyeapp/Mornye-Extension.
Credits are package-specific, not assigned wholesale to Yazhal. The unmodified
JioSaavn 1.0.10 test fixture is originally by **HemanthJabalpuri**, with Mornye
compatibility fixes; see https://github.com/HemanthJabalpuri/spotiflac-jiosaavn-extension
and `test/fixtures/jiosaavn/LICENSE` / `NOTICE.md`. The unmodified fixture remains
for compatibility testing.

Version 10.8.0 also bundles an attributed derivative in
`assets/providers/jiosaavn.sflx` (1.0.10-yazhal.1). The modification preserves the
provider's `language` field so listening recommendations can honor Tamil and
other languages. Original LGPL/GPL texts and notices are retained beside it and
inside the package. Upstream archive SHA-256:
`e35852c5ced6b0ea651eea0867c5dac46c79482c4ae4602185186621b4044887`.
Bundled derivative SHA-256:
`78e5c97b6aabc78833654080e1b6573d0972526b37a19e151c831d51e90816bc`.
JioSaavn/catalogue and audio rights remain with their respective owners.

Public iTunes Search API metadata and Apple CDN artwork are used for matched
catalogue enrichment. This is not an Apple Music playback SDK integration.
https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/

## JavaScript engine and bindings

QuickJS by **Fabrice Bellard and Charlie Gordon**, MIT license.
Flutter bindings: **NanCunChild/flutter_qjs_next** (copyright NanCunChild and Moustapha Kodjo Amadou), based on
**ekibun/flutter_qjs**; upstream license notices remain in the package and Flutter
license registry. https://github.com/NanCunChild/flutter_qjs_next

Yazhal's host, permission checks, recording-confirmation workflow, normalized
metadata/lyrics bridge, quality UI and secure state integration are its own
implementation of compatible interfaces, inspired by Mornye. This does not claim
authorship of Mornye, extension-provider code, service catalogs, lyrics or artwork.
