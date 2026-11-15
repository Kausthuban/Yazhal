// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/playback_cache.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_buffer');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'plays first bytes while the full song continues filling on disk',
    () async {
      final controller = StreamController<List<int>>();
      final file = File('${dir.path}/progressive.audio');
      final client = MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          controller.stream,
          200,
          contentLength: 8,
          headers: {'content-type': 'audio/mpeg'},
        ),
      );
      final job = CachedAudioJob(
        file,
        (c, h) => c.send(
          http.Request('GET', Uri.https('audio.example', '/song'))
            ..headers.addAll(h),
        ),
        () => client,
        1024,
      );
      final response = await job.request(0, 4);
      final first = response.stream.expand((x) => x).toList();
      controller.add([1, 2, 3, 4]);
      expect(await first, [1, 2, 3, 4]);
      expect(job.complete, false);
      controller.add([5, 6, 7, 8]);
      await controller.close();
      final rest = await job.request(4, 8);
      expect(await rest.stream.expand((x) => x).toList(), [5, 6, 7, 8]);
      await job.finished;
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
    },
  );
  test(
    'current and next readers share a single request and survive promotion',
    () async {
      var requests = 0;
      final client = MockClient.streaming((_, __) async {
        requests++;
        return http.StreamedResponse(
          Stream.value([1, 2, 3, 4]),
          200,
          contentLength: 4,
          headers: {'content-type': 'audio/flac'},
        );
      });
      final cache = PlaybackCache(
        directory: Directory('${dir.path}/shared'),
        clientFactory: () => client,
      );
      Future<http.StreamedResponse> open(
        http.Client c,
        Map<String, String> headers,
      ) => c.send(
        http.Request('GET', Uri.https('audio.example', '/shared'))
          ..headers.addAll(headers),
      );
      await cache.preload('same', open);
      await cache.cancelPreload(preserveKey: 'same');
      final source = await cache.source('same', open) as BufferedAudioSource;
      final a = await source.request();
      expect(await a.stream.expand((x) => x).toList(), [1, 2, 3, 4]);
      final b = await source.request();
      expect(await b.stream.expand((x) => x).toList(), [1, 2, 3, 4]);
      expect(requests, 1);
    },
  );
  test(
    'clearing temporary cache keeps active audio and unrelated downloads',
    () async {
      final downloads = File('${dir.path}/Music/my-download.flac');
      await downloads.create(recursive: true);
      await downloads.writeAsBytes([1, 2]);
      final cache = PlaybackCache(
        directory: Directory('${dir.path}/clear'),
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'audio/mpeg'},
          ),
        ),
      );
      final source = await cache.source(
        'active',
        (c, h) =>
            c.send(http.Request('GET', Uri.https('audio.example', '/active'))),
      ) as BufferedAudioSource;
      final r = await source.request();
      await r.stream.drain<void>();
      await source.job.finished;
      await File('${(await cache.root()).path}/old.audio').writeAsBytes([1]);
      await cache.clear();
      expect(await source.job.file.exists(), true);
      expect(
        await File('${(await cache.root()).path}/old.audio').exists(),
        false,
      );
      expect(await downloads.exists(), true);
    },
  );
  test(
    'HTML errors are not saved as music and a new attempt can retry',
    () async {
      var count = 0;
      final cache = PlaybackCache(
        directory: Directory('${dir.path}/retry'),
        clientFactory: () => MockClient((_) async {
          count++;
          return count == 1
              ? http.Response(
                  '<html>failure</html>',
                  200,
                  headers: {'content-type': 'text/html'},
                )
              : http.Response.bytes(
                  [1, 2, 3, 4],
                  200,
                  headers: {'content-type': 'audio/mpeg'},
                );
        }),
      );
      Future<http.StreamedResponse> open(
        http.Client c,
        Map<String, String> h,
      ) => c.send(http.Request('GET', Uri.https('audio.example', '/retry')));
      final first = await cache.source('retry', open) as BufferedAudioSource;
      await expectLater(first.request(), throwsFormatException);
      final second = await cache.source('retry', open) as BufferedAudioSource;
      final r = await second.request();
      expect(await r.stream.expand((x) => x).toList(), [1, 2, 3, 4]);
      expect(count, 2);
    },
  );
  test(
    'a track larger than storage allowance streams without filling the disk',
    () async {
      var count = 0;
      final file = File('${dir.path}/oversized.audio');
      final job = CachedAudioJob(
        file,
        (c, h) async {
          count++;
          return http.StreamedResponse(
            Stream.value([1, 2, 3, 4]),
            200,
            contentLength: 4,
            headers: {'content-type': 'audio/mpeg'},
          );
        },
        () => MockClient((_) async => http.Response('', 200)),
        2,
      );
      final r = await job.request();
      expect(await r.stream.expand((x) => x).toList(), [1, 2, 3, 4]);
      expect(await file.exists(), false);
      expect(count, 1);
    },
  );
  test('unknown-length audio streams directly instead of failing at the disk limit', () async {
    final file = File('${dir.path}/unknown.audio');
    final job = CachedAudioJob(
      file,
      (c, h) async => http.StreamedResponse(
        Stream.value([1, 2, 3, 4]),
        200,
        headers: {'content-type': 'audio/mpeg'},
      ),
      () => MockClient((_) async => http.Response('', 200)),
      2,
    );
    final response = await job.request();
    expect(await response.stream.expand((x) => x).toList(), [1, 2, 3, 4]);
    expect(await file.exists(), false);
  });
  test(
    'AAC tail metadata below 1 MiB is read without waiting for the full song',
    () async {
      final body = StreamController<List<int>>();
      final headers = <Map<String, String>>[];
      final job = CachedAudioJob(
        File('${dir.path}/small-aac.audio'),
        (c, h) async {
          headers.add(Map.of(h));
          if (h.containsKey('Range')) {
            return http.StreamedResponse(
              Stream.value([7, 8]),
              206,
              contentLength: 2,
              headers: {'content-range': 'bytes 6-7/8', 'etag': 'stable'},
            );
          }
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: 8,
            headers: {
              'content-type': 'audio/mp4',
              'accept-ranges': 'bytes',
              'etag': 'stable',
            },
          );
        },
        () => MockClient((_) async => http.Response('', 200)),
        1024,
      );
      try {
        await job.start();
        // The main transfer has not delivered its body or completed.
        final tail = await job
            .request(6, 8)
            .timeout(const Duration(seconds: 1));
        expect(await tail.stream.expand((x) => x).toList(), [7, 8]);
        expect(job.complete, false);
        expect(headers.last, {'Range': 'bytes=6-7', 'If-Range': 'stable'});
        body.add([1, 2, 3, 4, 5, 6, 7, 8]);
        await body.close();
        await job.finished;
        expect(await job.file.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
      } finally {
        await job.cancel();
      }
    },
  );
}
