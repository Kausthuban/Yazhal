# Android preview build 10.8.0 (192)

## Install

Install the supplied ARM64 APK on Android 7.0/API 24 or later. The preview is
release-mode/AOT optimized, signed with a private-to-this-delivery Android test
key, and labelled **Yazhal Preview**. It is not a production-signed release.
Package: `com.kausthuban.yazhal.preview`; ARM64 versionCode `2192`.

It installs alongside the previous `com.kausthuban.yazhal.debug` APK. Its old
signing key was not available; replacing that app safely is therefore not
possible. Keep the previous app/data. Export its local statistics JSON, restore
in the preview, reselect local music folders and reimport playlists as needed.
Statistics backup intentionally does not copy audio, playlists or credentials.

## Reproduce

Flutter 3.47.9 / Dart 3.13.7, full JDK 21, SDK 36, NDK 28.2.13676358,
CMake 3.22.1 and Gradle 9.3.1 are used. Flutter regenerates wrapper and plugin files.

```sh
flutter pub get
flutter analyze
python3 tool/build_extension_test_runtime.py
export FLUTTER_QJS_NEXT_LIBRARY="$PWD/build/native_extensions/libflutter_qjs_next_plugin.so"
flutter test --no-pub --concurrency=1 $(find test -name '*_test.dart' ! -path 'test/fetch_audio_stream_live_test.dart' ! -path 'test/linux/media_controls_test.dart')
```

Build the optimized preview with the generated Android Gradle wrapper after
`flutter pub get`:

```sh
cd android
./gradlew :app:assembleGithubRelease -PyazhalPreview=true -Ptarget-platform=android-arm64,android-x64 -Psplit-per-abi=true
```

The direct Gradle invocation is the path validated for this delivery. An optional
`-PyazhalPreviewKeyPath=/absolute/private/path/test.jks` overrides the preview debug
keystore so repeated previews can use the same test identity (alias
`androiddebugkey`, conventional Android debug test password). Do not commit it.
For production, omit `yazhalPreview` and provide your private `key.properties`
release signing configuration. Production uses `com.kausthuban.yazhal`.

Generated files, SDKs, caches, APKs and private signing material are excluded from
the clean source ZIP. Keep your own signing keys backed up securely. The test
signing kit supplied separately is for this preview identity only.

## Verification

The APK signature, ZIP integrity, manifest/ABI and 16 KiB ZIP/native ELF LOAD
alignment are checked. Static analysis and regression tests are summarized in
`USER_FEEDBACK_10.8.0.md`. A separate x86_64 split is used only for emulator checks;
the phone download contains ARM64 libraries. No physical hardware behavior or
live paid-service authorization is implied by a successful build.
