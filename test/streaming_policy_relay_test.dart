import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/audio_relay_service.dart';
import 'package:yazhal/services/streaming_policy.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_streaming');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDown(() async {
    await Hive.box('settings').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'adaptive quality downgrades fast and respects the configured ceiling',
    () {
      final p = StreamingPolicy()..observe(65536, const Duration(seconds: 5));
      expect(p.quality.value, 'low');
      expect(p.effectiveQuality('high'), 'low');
      for (var i = 0; i < 40; i++) {
        p.observe(65536, const Duration(milliseconds: 20));
      }
      expect(p.quality.value, 'high');
      expect(p.effectiveQuality('medium'), 'medium');
      p.stalled();
      expect(p.quality.value, 'low');
    },
  );
  test(
    'data saver disables speculation and manual quality remains available',
    () async {
      final p = StreamingPolicy();
      await Hive.box('settings').put('adaptiveStreaming', false);
      expect(p.effectiveQuality('high'), 'high');
      await Hive.box('settings').put('streamingDataSaver', true);
      expect(p.effectiveQuality('high'), 'low');
      expect(
        p.shouldPreload(
          remaining: const Duration(seconds: 20),
          bufferedAhead: const Duration(seconds: 15),
          playing: true,
        ),
        false,
      );
    },
  );
  test('preload starts early with enough buffer and respects data saver', () {
    final p = StreamingPolicy();
    expect(
      p.shouldPreload(
        remaining: const Duration(seconds: 20),
        bufferedAhead: const Duration(seconds: 15),
        playing: true,
      ),
      true,
    );
    expect(
      p.shouldPreload(
        remaining: const Duration(seconds: 60),
        bufferedAhead: const Duration(seconds: 15),
        playing: true,
      ),
      true,
    );
    expect(
      p.shouldPreload(
        remaining: const Duration(seconds: 20),
        bufferedAhead: const Duration(seconds: 3),
        playing: true,
      ),
      false,
    );
    expect(
      p.shouldPreload(
        remaining: const Duration(seconds: 20),
        bufferedAhead: const Duration(seconds: 15),
        playing: false,
      ),
      false,
    );
  });
  test('speculative request is bounded and validated prefix is reused by native relay', () async {
    final audio = List<int>.generate(150000, (i) => i % 251);
    final ranges = <String?>[];
    final relay = AudioRelayService(
      clientFactory: () => MockClient((request) async {
        final range = request.headers['Range'];
        ranges.add(range);
        if (range == 'bytes=0-131071')
          return http.Response.bytes(
            audio.take(131072).toList(),
            206,
            headers: {
              'content-range': 'bytes 0-131071/150000',
              'etag': '"v1"',
              'content-type': 'audio/mp4',
            },
          );
        expect(request.headers['If-Range'], '"v1"');
        return http.Response.bytes(
          audio.skip(131072).toList(),
          206,
          headers: {
            'content-range': 'bytes 131072-149999/150000',
            'etag': '"v1"',
          },
        );
      }),
    );
    final origin = Uri.parse('https://example.org/audio');
    await relay.preload('next-entry', origin, {}, allows: (_) => true);
    final local = await relay.register(origin, allows: (_) => true);
    final client = HttpClient();
    final response = await (await client.getUrl(Uri.parse(local))).close();
    final received = await response.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    expect(response.statusCode, 200);
    expect(received, audio);
    expect(ranges, ['bytes=0-131071', 'bytes=131072-']);
    client.close(force: true);
    await relay.dispose();
  });
  test(
    'ignores full-body preload response instead of draining unlimited audio',
    () async {
      var cancelled = false;
      final relay = AudioRelayService(
        clientFactory: () => MockClient.streaming((request, body) async {
          final stream = StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          );
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      await relay
          .preload(
            'entry',
            Uri.parse('https://example.org/audio'),
            {},
            allows: (_) => true,
          )
          .timeout(const Duration(seconds: 2));
      expect(cancelled, true);
      await relay.dispose();
    },
  );
  test(
    'a cancelled prefix cannot be reused after queue priority changes',
    () async {
      var ordinary = false;
      final relay = AudioRelayService(
        clientFactory: () => MockClient((request) async {
          if (request.headers['Range'] == 'bytes=0-131071')
            return http.Response.bytes(
              [1, 2, 3, 4],
              206,
              headers: {'content-range': 'bytes 0-3/8', 'etag': '"v1"'},
            );
          ordinary = request.headers['Range'] == null;
          return http.Response.bytes([8, 7, 6, 5], 200);
        }),
      );
      final origin = Uri.parse('https://example.org/audio');
      await relay.preload('old-next', origin, {}, allows: (_) => true);
      relay.cancelPreload();
      final local = await relay.register(origin, allows: (_) => true);
      final client = HttpClient();
      final response = await (await client.getUrl(Uri.parse(local))).close();
      await response.drain<void>();
      expect(ordinary, true);
      client.close(force: true);
      await relay.dispose();
    },
  );
}
