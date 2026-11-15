import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/bundled_providers.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/extension_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ExtensionPackage bundled() => ExtensionPackage.decode(
    'jiosaavn',
    File('assets/providers/jiosaavn.sflx').readAsBytesSync(),
    BundledProviders.digest,
  );
  test('bundled high-quality source is pinned and includes upstream authors and licenses', () {
    final package = bundled();
    expect(package.qualities.first.id, 'AAC_320');
    expect(package.author, contains('HemanthJabalpuri'));
    expect(package.licenses, isNotEmpty);
    expect(
      package.source,
      contains('language: String(more.language || song.language'),
    );
  });
  test(
    'bundled source resolves AAC 320 without first downloading the song',
    () async {
      final runtime = ExtensionRuntime(
        client: MockClient(
          (_) async => throw StateError('Prepared metadata must avoid network'),
        ),
      );
      try {
        final r = await runtime.call(
          bundled(),
          'getDownloadUrl',
          [
            'abcd1234',
            'AAC_320',
            {
              'preparedContext': {
                'track': {
                  'id': 'abcd1234',
                  'preview_url': 'https://aac.saavncdn.com/123/example_96.mp4',
                },
              },
            },
          ],
          settings: {'lang': 'tamil'},
        );
        expect(
          (r.value as Map)['url'],
          'https://aac.saavncdn.com/123/example_320.mp4',
        );
        expect((r.value as Map)['actual_extension'], 'm4a');
      } finally {
        runtime.close();
      }
    },
    skip: Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] == null
        ? 'Native QuickJS test runtime required'
        : false,
  );
  test(
    'source-declared Tamil survives catalogue normalization',
    () async {
      final runtime = ExtensionRuntime(
        client: MockClient((request) async {
          expect(request.url.host, 'www.jiosaavn.com');
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'abcd1234',
                  'type': 'song',
                  'title': 'Tamil song',
                  'primary_artists': 'Tamil artist',
                  'more_info': {'language': 'tamil', 'duration': '180'},
                  'image': 'https://c.saavncdn.com/art/150x150.jpg',
                },
              ],
            }),
            200,
          );
        }),
      );
      try {
        final r = await runtime.call(
          bundled(),
          'searchTracks',
          ['Tamil song', 5],
          settings: {'lang': 'tamil'},
        );
        expect((r.value as List).single['language'], 'tamil');
      } finally {
        runtime.close();
      }
    },
    skip: Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] == null
        ? 'Native QuickJS test runtime required'
        : false,
  );
}
