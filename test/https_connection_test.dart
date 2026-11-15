// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/services/playback_cache.dart';
import 'package:yazhal/services/public_network_client.dart';

// This certificate/key pair is exclusively for a loopback test server.
// The application uses system roots and never loads these fixtures.
void main() {
  late HttpServer server;
  late SecurityContext trusted;
  late Completer<void> finishAudio;
  var requests = 0;
  final endpoint = Uri.https('audio.example.org', '/search');
  setUp(() async {
    finishAudio = Completer<void>();
    requests = 0;
    final serverContext = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/test-only-cert.pem')
      ..usePrivateKey('test/fixtures/tls/test-only-key.pem');
    trusted = SecurityContext()
      ..setTrustedCertificates('test/fixtures/tls/test-only-cert.pem');
    server =
        (await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          serverContext,
        ))..listen((request) async {
          requests++;
          if (request.uri.path == '/audio') {
            request.response.bufferOutput = false;
            request.response.headers.contentType = ContentType('audio', 'mpeg');
            request.response.contentLength = 8;
            request.response.add([1, 2, 3, 4]);
            await request.response.flush();
            await finishAudio.future;
            request.response.add([5, 6, 7, 8]);
            await request.response.close();
            return;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"results":[]}');
          await request.response.close();
        }, onError: (Object _) {});
  });
  tearDown(() async {
    if (!finishAudio.isCompleted) finishAudio.complete();
    await server.close(force: true);
  });

  test(
    'custom pinned HTTPS factory performs TLS with original hostname',
    () async {
      final client = PublicNetworkClient.create(
        context: trusted,
        lookup: (_) async => [InternetAddress('8.8.8.8')],
        // Only this test redirects the pinned TCP dial to a local TLS server.
        dial: (_, __) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
      );
      try {
        final response = await client
            .get(endpoint)
            .timeout(const Duration(seconds: 5));
        expect(response.statusCode, 200);
        expect(response.body, '{"results":[]}');
      } finally {
        client.close();
      }
    },
  );
  test('pinned HTTPS rejects a certificate for a different hostname', () async {
    final client = PublicNetworkClient.create(
      context: trusted,
      lookup: (_) async => [InternetAddress('8.8.8.8')],
      dial: (_, __) =>
          Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
    );
    try {
      await expectLater(
        client
            .get(Uri.https('wrong.example.org', '/'))
            .timeout(const Duration(seconds: 5)),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
      );
    } finally {
      client.close();
    }
  });
  test('pinned HTTPS rejects an untrusted certificate', () async {
    final client = PublicNetworkClient.create(
      context: SecurityContext(),
      lookup: (_) async => [InternetAddress('8.8.8.8')],
      dial: (_, __) =>
          Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
    );
    try {
      await expectLater(
        client.get(endpoint).timeout(const Duration(seconds: 5)),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
      );
    } finally {
      client.close();
    }
  });
  test('real HTTPS audio starts from initial bytes while the entire track fills in background', () async {
    final dir = await Directory.systemTemp.createTemp('yazhal_tls_buffer');
    final job = CachedAudioJob(
      File('${dir.path}/song.audio'),
      (client, headers) => client.send(
        // Production URL validation and TLS hostname checks are retained.
        http.Request('GET', Uri.https('audio.example.org', '/audio'))
          ..headers.addAll(headers),
      ),
      () => PublicNetworkClient.create(
        context: trusted,
        lookup: (_) async => [InternetAddress('8.8.8.8')],
        dial: (_, __) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
      ),
      1024,
    );
    try {
      final response = await job.request(0, 4);
      expect(
        await response.stream
            .expand((chunk) => chunk)
            .toList()
            .timeout(const Duration(seconds: 3)),
        [1, 2, 3, 4],
      );
      expect(finishAudio.isCompleted, false);
      expect(job.complete, false);
      finishAudio.complete();
      await job.finished.timeout(const Duration(seconds: 3));
      expect(await job.file.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(requests, 1);
    } finally {
      if (!finishAudio.isCompleted) finishAudio.complete();
      await job.cancel();
      await dir.delete(recursive: true);
    }
  });
}
