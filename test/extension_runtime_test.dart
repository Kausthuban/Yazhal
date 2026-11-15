import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/extension_runtime.dart';

ExtensionPackage fixture(String source) => ExtensionPackage(
  id: 'fixture',
  manifest: {
    'name': 'fixture',
    'version': '1',
    'permissions': {
      'network': ['api.example.org'],
    },
  },
  source: source,
  digest: '',
  licenses: {'LICENSE': 'Test fixture'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'];
  test(
    'synchronous provider HTTP runs through bounded async Dart bridge',
    () async {
      final runtime = ExtensionRuntime(
        client: MockClient((request) async {
          expect(request.url.host, 'api.example.org');
          return http.Response(
            jsonEncode({
              'tracks': [
                {'id': 'one', 'name': 'Result'},
              ],
            }),
            200,
          );
        }),
      );
      final provider = fixture(
        "registerExtension({searchTracks:function(q){var r=http.get('https://api.example.org/search?q='+encodeURIComponent(q));if(!r.ok)throw new Error('request failed');storage.set('last',q);return JSON.parse(r.body).tracks;}})",
      );
      final result = await runtime.call(provider, 'searchTracks', ['hello']);
      expect((result.value as List).single['name'], 'Result');
      expect(result.storage['last'], 'hello');
      runtime.close();
    },
    skip: native == null
        ? 'Set FLUTTER_QJS_NEXT_LIBRARY to the compiled QuickJS test library'
        : false,
  );
  test('real JioSaavn package honors each declared AAC quality without relabelling', () async {
    final dir = Directory('test/fixtures/jiosaavn');
    final manifest = jsonDecode(
      File('${dir.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final provider = ExtensionPackage(
      id: 'jiosaavn',
      manifest: manifest,
      source: File('${dir.path}/index.js').readAsStringSync(),
      digest: 'fixture',
      licenses: {},
    );
    final runtime = ExtensionRuntime(
      client: MockClient(
        (_) async => throw StateError('Prepared context must avoid network'),
      ),
    );
    for (final quality in provider.qualities) {
      final result = await runtime.call(provider, 'getDownloadUrl', [
        'abcd1234',
        quality.id,
        {
          'preparedContext': {
            'track': {
              'id': 'abcd1234',
              'preview_url': 'https://aac.saavncdn.com/123/example_320.mp4',
            },
          },
        },
      ]);
      final value = result.value as Map;
      expect(value['success'], true, reason: value.toString());
      expect(value['actual_extension'], 'm4a');
      final bitrate = quality.id.split('_').last;
      expect(value['url'], endsWith('_$bitrate.mp4'));
    }
    runtime.close();
  }, skip: native == null ? 'Native QuickJS library required' : false);
  test(
    'undeclared network destinations fail before the HTTP client is called',
    () async {
      var calls = 0;
      final runtime = ExtensionRuntime(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        runtime.call(
          fixture(
            "registerExtension({searchTracks:function(){return http.get('https://127.0.0.1/secret');}})",
          ),
          'searchTracks',
          [],
        ),
        throwsStateError,
      );
      expect(calls, 0);
      runtime.close();
    },
    skip: native == null ? 'Native QuickJS library required' : false,
  );
  test('archive identity and digest are checked before installation', () {
    final archive = Archive();
    final manifest = jsonEncode({
      'name': 'test',
      'version': '1',
      'permissions': {
        'network': ['api.example.org'],
      },
    });
    for (final entry in {
      'manifest.json': manifest,
      'index.js': 'registerExtension({});',
      'LICENSE': 'Test fixture license',
    }.entries) {
      archive.addFile(
        ArchiveFile(
          entry.key,
          utf8.encode(entry.value).length,
          utf8.encode(entry.value),
        ),
      );
    }
    final bytes = ZipEncoder().encode(archive);
    final package = ExtensionPackage.decode(
      'test',
      bytes,
      sha256.convert(bytes).toString(),
    );
    expect(package.id, 'test');
    expect(
      () => ExtensionPackage.decode('test', bytes, '0' * 64),
      throwsFormatException,
    );
    archive.addFile(ArchiveFile('../escape', 1, [1]));
    final bad = ZipEncoder().encode(archive);
    expect(
      () =>
          ExtensionPackage.decode('test', bad, sha256.convert(bad).toString()),
      throwsFormatException,
    );
  });
  test(
    'untrusted JavaScript loops are interrupted by the native VM deadline',
    () async {
      final runtime = ExtensionRuntime(
        jsTimeoutMillis: 300,
        client: MockClient((_) async => http.Response('', 200)),
      );
      final watch = Stopwatch()..start();
      await expectLater(
        runtime.call(
          fixture(
            'registerExtension({searchTracks:function(){while(true){} }});',
          ),
          'searchTracks',
          [],
        ),
        throwsStateError,
      );
      expect(watch.elapsed.inSeconds, lessThan(5));
      runtime.close();
    },
    skip: native == null ? 'Native QuickJS library required' : false,
  );
}
