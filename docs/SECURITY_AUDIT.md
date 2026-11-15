# Yazhal security review

Date: 2026-11-13. Updated for Yazhal 10.7.0. Scope: application Dart/Kotlin/native configuration, vendored
source, scripts, workflows, catalog/repository inputs, playback URL handling,
backup/import paths, Local Sync authentication/authorization and locked Pub
versions in the delivered Yazhal source. Starting revision:
`824bde48b568359437da62844e0fdc3eb5ec1283`.

This is a source review and automated analysis, not a penetration-test
certification or proof that malware/vulnerabilities cannot exist. No user account,
private data, production deployment or third-party endpoint was attacked.

## Confirmed findings and fixes

| ID | Severity | Finding | Resolution / evidence |
| --- | --- | --- | --- |
| YAZ-01 | High | Catalog host declarations checked URI names but did not prevent a declared DNS name from resolving to loopback/private/link-local services. Native playback could also follow redirects independently of the Dart preflight. | `PublicNetworkClient` validates public HTTPS, rejects private/reserved DNS answers and pins the actual socket to a validated address. Catalog/repository requests recheck every redirect. Catalog native playback uses `AudioRelayService`, preserving the declared-host restriction on the actual transfer. Tests reject private/mapped addresses, bad schemes/credentials/ports, undeclared redirects and a redirect to loopback. |
| YAZ-02 | Medium | Redirect/error paths drained arbitrary response bodies without a body deadline/size bound. A malicious source could indefinitely consume network/data/resources before an error or redirect completed. | Replaced draining with stream cancellation. Repository JSON, manifests and audio prefixes have size/time limits. A streaming regression test supplies a never-ending full-body preload response and verifies cancellation without waiting for EOF. |
| YAZ-03 | Medium | Non-live online audio could fall through to an arbitrary native URL if it did not match the expected YouTube CDN path. A malformed proxy/cache response could bypass the controlled playback path. | Ordinary online audio now requires an approved public YouTube/CDN URL and uses the validated relay. Integration test verifies a loopback URL cannot create a native source. This restriction does not change intentionally configured radio streams or the separate Local Sync LAN feature. |

Other hardening: malformed persisted catalog records no longer crash the source
manager; installation is capped at 100 catalogs and 30 repositories. Remote
manifest integrity and identity are checked before parsing/installing. New
catalogs start disabled. A bounded QuickJS compatibility host is now intentionally present. Untrusted
packages are hash-checked, permission-reviewed and disabled by default. VM CPU,
heap, host-request, storage and result quotas are enforced. Callback execution is
on worker isolates; native socket ownership/disposal is coordinated. This is a VM
boundary within the app process, not an OS sandbox. New tests execute the real VM,
not an always-successful mock runtime. URL tokens for
the loopback relay are generated securely, rotated per track, kept out of Hive
and served with `Cache-Control: no-store`. The listener binds only to IPv4
loopback, accepts GET/HEAD and supports one byte-range request, with no CORS grant.
Prefix reuse requires representation revalidation, including exact range/total.

## Automated analysis

- **Flutter/Dart:** `flutter analyze --no-pub` reports no issues.
- **Dependency advisories:** OSV `/v1/querybatch` queried **133 hosted Pub
  package/version pairs** from the application `pubspec.lock`. All 133 results
  were empty: no known advisories returned at the time of this review. This is a
  database result, not evidence that every dependency is secure. Reproduce with
  `python tool/security_audit.py` (Python 3, PyYAML, network access required).
- **Static security and secrets:** Semgrep OSS **1.185.0**, registry configs
  `p/secrets` and `p/security-audit`, metrics disabled. The comprehensive source
  pass ran **180 rules** over **495 targets**, with **zero parser errors**. Build,
  SDK caches and generated output were excluded; default ignore rules also
  skipped unsupported/non-source files. Generic secret rules cover text, but the
  rule set does not provide complete Dart semantic/taint analysis.
- **One Semgrep warning was reviewed as a false positive:**
  `python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected`
  in `tool/security_audit.py`. It flags passing a Request variable to `urlopen`.
  The destination is the literal `https://api.osv.dev/v1/querybatch`; lockfile
  values only populate the JSON body and cannot supply a URL or `file://` scheme.
  The warning is retained, not suppressed. No hardcoded credential finding was
  returned by the secret rules.
- **Regression tests:** see the final validation record below and
  IMPLEMENTATION_SUMMARY.md. Existing Local Sync/backup/import negative tests
  remain part of the available suite. New security tests cover repository
  parsing/runtime refusal, manifest checksums/identity, network restrictions,
  bounded cancellation and prefix revalidation/cancellation.

No evidence of malicious scripts, embedded private signing keys or hardcoded
production credentials was identified in the reviewed source. Source inspection
included shell/Python maintenance scripts, the update flow and process-launch
sites. Existing vendored YouTube challenge-solving JavaScript/Deno support is a
known playback dependency, separate from the newly supported, explicitly enabled provider scripts. The Deno path
uses argument arrays and restricted process permissions; it was not executed as
part of this audit. APK auto-updates remain disabled unless explicitly enabled
at build time; this delivery does not publish or install executable updates.

## Authentication, data and web attack classes

| Area | Review result |
| --- | --- |
| App/cloud login | No cloud account/login or cloud authorization backend is implemented here. No cloud-session tokens were found to audit. |
| Local Sync | Intentional LAN server with POST JSON endpoints. Existing SRP/PIN pairing, encrypted authenticated AES-GCM messages, context checks, replay counters, size limits and rejection tests were inspected and exercised by the suite. Re-pairing/replay and failed-delivery cleanup tests remain enabled. |
| Sensitive storage | New provider settings/tokens/state use platform secure storage, with Android encrypted-store/configuration backup exclusions and no plaintext fallback. Existing Local Sync pairing secrets reside in app-private `userNoBackup` Hive storage, not OS-keystore-encrypted storage. Manual exports and Android cloud/device-transfer rules exclude this device identity/secret store. This is a residual hardening concern if an attacker can already read app-private files; no remotely accessible storage bypass was confirmed. OS keystore/keyring migration remains future hardening. |
| SQL/NoSQL injection | The app uses Hive; no app SQL string execution, MongoDB queries or remote database API accepting query fragments was identified. Native parsing and data validators are relevant instead; this is not a web database audit. |
| XSS | Native Flutter widgets render the reviewed remote text. No app WebView/DOM/HTML execution sink was identified. Provider JavaScript is an intentional non-DOM VM feature with restricted host APIs. The existing YouTube challenge solver is a separate script-processing dependency. No browser XSS exploit was confirmed. |
| CSRF/CORS | Local Sync requires JSON and authenticated encrypted requests for protected operations; no permissive CORS or preflight path was identified. Relay read URLs require an unpredictable per-track token and send no CORS allow-origin header. No cross-origin state-changing bypass was confirmed. |
| Security headers | CSP/HSTS/frame headers on a hosted web UI are not applicable to this native app. Android network-security config denies general cleartext in the native stack and permits only player loopback HTTP; Dart networking has explicit checks on untrusted catalogs. This is not a global ban on intentional radio/Local Sync networking. |
| File input/import/backup | Existing bounded backup validation and restore lifecycle tests, local file/playlist import and storage/folder handling were reviewed. There is no public file-upload web endpoint. Existing backups can contain personal library/history data and should be treated as private exports. |
| Catalog/stream URLs | Untrusted catalogs and repository downloads now use public HTTPS, socket-pinned DNS checks and redirect checks. Native non-live audio follows the controlled relay path. User-configured radio and trusted live HLS retain existing native handling; they do not gain equivalent per-segment redirect enforcement in this delivery. |

## Limits and residual risks

- **Informational — native supply chain:** OSV Pub results do not resolve Android
  Gradle/Maven transitives, desktop native binaries, engine codecs, vendored
  modifications or operating-system libraries. No full Android/desktop build or
  native dependency graph was available. Recheck those in the release toolchain.
- **Informational — publisher trust:** HTTPS and checksums do not establish a
  catalog publisher's honesty. Source operators receive search terms/IPs and can
  serve incorrect audio/metadata. The user must review hosts and enable sources.
- **Informational — storage:** app-private pairing keys are not protected against
  root/debug/app-directory compromise by an OS keystore in this version.
- **Informational — workflows:** actions use upstream version tags, not immutable
  commit pins. CI permissions are read-only and no credentials are embedded;
  pinning/reviewing action SHAs is recommended for release supply-chain hardening.
- Native decoder bugs, device permissions, media-session OEM differences,
  background battery restrictions and physical Bluetooth behavior were not
  established by static review. Actual network-shaping/mobile-data measurement
  was not performed. No ClamAV/antivirus executable scan or external professional
  penetration test is claimed.
- Mornye itself was inspected for interface/license compatibility, not subjected
  to a full security audit. Its Rust backend is not included; an unmodified licensed JioSaavn fixture is retained for compatibility testing, and user-installed JavaScript packages execute through the documented restricted host.

## Final validation record

- Flutter 3.47.9 / Dart 3.13.7: analysis passed with no issues.
- Available full regression suite: **305 passed, 9 conditional skips**; no failures.
  This includes prior regression coverage plus native runtime, quality UI, cross-source, lyrics-cache, metadata and source-security tests.
- Excluded by the existing CI command: `test/fetch_audio_stream_live_test.dart`
  (live YouTube) and `test/linux/media_controls_test.dart` (Linux D-Bus).
- The nine conditional skips retain their existing independent-worker/native
  libmpv/D-Bus conditions. Simulated native bridge tests run normally.
- `git diff --check` passed. Clean ZIP CRC/content and Git-staging checks are
  performed during packaging; build outputs and private keys are excluded.
- Physical AirPods/Bluetooth, Android lock-screen/background/permission checks,
  live network shaping, full native builds and native dependency graphs remain
  unverified. No signed APK or release was produced or pushed.

Reproduce the source checks:

```bash
flutter pub get
flutter analyze
python3 tool/build_extension_test_runtime.py
export FLUTTER_QJS_NEXT_LIBRARY="$PWD/build/native_extensions/libflutter_qjs_next_plugin.so"
flutter test --no-pub --concurrency=1 $(find test -name '*test.dart' ! -path 'test/fetch_audio_stream_live_test.dart' ! -path 'test/linux/media_controls_test.dart')
python tool/security_audit.py
```

Static security scan (install Semgrep separately; registry access needs network):

```bash
semgrep scan --config p/secrets --config p/security-audit --metrics=off \
  --no-git-ignore --exclude .git --exclude .dart_tool --exclude build \
  --exclude '**/ephemeral/**' --exclude '**/.gradle/**' \
  --exclude '**/app_localizations*.dart'
```

New extension-specific review: package directory checks precede decompression;
unsafe paths/symlinks/duplicates and size overruns are rejected. Credential-bearing
artwork URLs and sensitive metadata fields are omitted from plaintext metadata.
Artwork uses pinned public HTTPS and provider/CDN checks, byte/pixel bounds and a
bounded private cache. Direct native audio keeps the validated relay. Sensitive
headers are removed on cross-host redirects. No external package is auto-enabled.

Residual capability limits include public HTTPS only (private Jellyfin/LAN
endpoints blocked), unsupported native encrypted transfers and browser-auth
callbacks, and no proof of universal third-party package compatibility. Physical
AirPods/Bluetooth, native Android packaging and account-gated service behavior
remain unverified. New provider credentials are keystore/keyring-backed; this
has not migrated the older Local Sync pairing store.

The retained urllib warning above is expected and requires review rather than
blind suppression. Version-tagged rule registries and advisory databases change
over time, so future results can differ.

Useful primary references:

- [OSV batch API](https://google.github.io/osv.dev/post-v1-querybatch/)
- [just_audio 0.10.6](https://pub.dev/packages/just_audio/versions/0.10.6)
- [audio_service 0.18.19](https://pub.dev/packages/audio_service/versions/0.18.19)
- [Mornye reviewed source](https://github.com/mornyeapp/Mornye/tree/45df9860661e9c4e731ef26a60c44b2b5d8cf125)


## 10.7.1 local statistics backup

The normal Settings backup workflow now exports/imports a data-only JSON file.
It whitelists listening totals and song/history metadata, excludes settings,
provider credentials, pairing secrets and file-path fields, and rejects files
over 5 MiB or with unsupported format/version headers before restoring. Restore
replaces counts instead of merging them, and does not restore executable
extensions, repositories or authentication state. Android automatic app backup
is disabled. Seven added tests cover privacy, idempotence, invalid/oversized input
and availability in both offline and online modes. No new dependency was added
for this backup workflow. APK build/signature and emulator checks are described
in `ANDROID_BUILD_10.7.1.md`; physical device checks remain necessary.
