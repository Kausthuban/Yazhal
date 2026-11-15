import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/services/streaming_policy.dart';

class AudioPrefix {
  AudioPrefix(this.bytes, this.total, this.validator, this.type);
  final List<int> bytes;
  final int total;
  final String validator, type;
}

/// Bounded speculative fetch and a local-only relay. Native decoders cannot
/// bypass custom-source URL/DNS/redirect checks, and can reuse validated prefixes.
class AudioRelayService {
  AudioRelayService({http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? PublicNetworkClient.create;
  static final instance = AudioRelayService();
  final http.Client Function() clientFactory;
  HttpServer? _server;
  bool _listening = false;
  Future<HttpServer>? _starting;
  final _routes =
      <
        String,
        ({Uri url, Map<String, String> headers, bool Function(Uri) allows})
      >{};
  final _prefixes = <String, AudioPrefix>{};
  http.Client? _preloadClient;
  int _generation = 0;
  String? _candidate;
  static const prefixBytes = 128 * 1024;
  void cancelPreload() {
    _generation++;
    _candidate = null;
    _preloadClient?.close();
    _preloadClient = null;
    _prefixes.clear();
  }

  static bool youtube(Uri u) =>
      PublicNetworkClient.publicHttps(u) &&
      (u.host == 'googlevideo.com' ||
          u.host.endsWith('.googlevideo.com') ||
          u.host == 'youtube.com' ||
          u.host.endsWith('.youtube.com'));
  Future<http.StreamedResponse> open(
    http.Client client,
    Uri uri, {
    Map<String, String> headers = const {},
    required bool Function(Uri) allows,
  }) async {
    final requestHeaders = Map<String, String>.from(headers);
    for (var i = 0; i <= 5; i++) {
      if (!PublicNetworkClient.publicHttps(uri) || !allows(uri))
        throw const FormatException(
          'Stream URL outside approved public HTTPS hosts',
        );
      final response = await client
          .send(
            http.Request('GET', uri)
              ..headers.addAll(requestHeaders)
              ..followRedirects = false,
          )
          .timeout(const Duration(seconds: 20));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await PublicNetworkClient.cancelBody(response);
        if (location == null) throw const HttpException('Missing redirect');
        final target = uri.resolve(location);
        if (target.host != uri.host)
          requestHeaders.removeWhere(
            (key, value) => RegExp(
              'authorization|cookie|token|api.?key',
              caseSensitive: false,
            ).hasMatch(key),
          );
        uri = target;
      } else {
        return response;
      }
    }
    throw const HttpException('Too many redirects');
  }

  Future<void> preload(
    String key,
    Uri url,
    Map<String, String> headers, {
    required bool Function(Uri) allows,
  }) async {
    if (_candidate == key) return;
    cancelPreload();
    _candidate = key;
    final generation = _generation;
    final client = clientFactory();
    _preloadClient = client;
    final watch = Stopwatch()..start();
    try {
      final response = await open(
        client,
        url,
        headers: {...headers, 'Range': 'bytes=0-${prefixBytes - 1}'},
        allows: allows,
      );
      final match = RegExp(r'^bytes 0-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      final validator =
          (response.headers['etag']?.startsWith('W/') == false
              ? response.headers['etag']
              : null) ??
          response.headers['last-modified'] ??
          '';
      if (response.statusCode != 206 || match == null || validator.isEmpty) {
        await PublicNetworkClient.cancelBody(response);
        return;
      }
      final total = int.parse(match[2]!);
      final length = int.parse(match[1]!) + 1;
      if (length > prefixBytes || total <= length) {
        await PublicNetworkClient.cancelBody(response);
        return;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        if (generation != _generation) return;
        bytes.addAll(chunk);
        if (bytes.length > prefixBytes)
          throw const FormatException('Oversized audio prefix');
      }
      if (bytes.length == length && generation == _generation) {
        _prefixes[url.toString()] = AudioPrefix(
          bytes,
          total,
          validator,
          response.headers['content-type'] ?? 'audio/mp4',
        );
        StreamingPolicy.instance.observe(bytes.length, watch.elapsed);
      }
    } catch (_) {
      /* Speculation cannot interrupt the playing item. */
    } finally {
      client.close();
      if (identical(_preloadClient, client)) _preloadClient = null;
    }
  }

  Future<String> register(
    Uri url, {
    Map<String, String> headers = const {},
    required bool Function(Uri) allows,
  }) async {
    if (!allows(url) || !PublicNetworkClient.publicHttps(url))
      throw const FormatException('Unsafe audio URL');
    final server = _server ??= await (_starting ??= HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    ));
    if (!_listening) {
      _listening = true;
      server.listen((r) => unawaited(_serve(r)));
    }
    _routes.clear();
    final token = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _routes[token] = (url: url, headers: headers, allows: allows);
    return 'http://127.0.0.1:${server.port}/audio/$token';
  }

  Future<void> _serve(HttpRequest request) async {
    final token =
        request.uri.pathSegments.length == 2 &&
            request.uri.pathSegments.first == 'audio'
        ? request.uri.pathSegments.last
        : '';
    final route = _routes[token];
    if (route == null || !['GET', 'HEAD'].contains(request.method)) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final client = clientFactory();
    try {
      final range = request.headers.value('range');
      if (range != null && !RegExp(r'^bytes=(?:\d+-\d*|-\d+)$').hasMatch(range))
        throw const FormatException('Unsupported byte range');
      final prefix = _prefixes[route.url.toString()];
      // Serve a prefix only after the origin revalidates the exact representation.
      final usePrefix =
          prefix != null && (range == null || range == 'bytes=0-');
      final response = await open(
        client,
        route.url,
        headers: {
          ...route.headers,
          if (range != null) 'Range': range,
          if (usePrefix) 'Range': 'bytes=${prefix.bytes.length}-',
          if (usePrefix) 'If-Range': prefix.validator,
        },
        allows: route.allows,
      );
      final revalidated =
          usePrefix &&
          response.statusCode == 206 &&
          response.headers['content-range'] ==
              'bytes ${prefix.bytes.length}-${prefix.total - 1}/${prefix.total}' &&
          (response.headers['etag'] ?? response.headers['last-modified']) ==
              prefix.validator;
      request.response.headers.set('Cache-Control', 'no-store');
      if (revalidated) {
        request.response.statusCode = range == null ? 200 : 206;
        request.response.headers.set('Content-Type', prefix.type);
        request.response.contentLength = prefix.total;
        if (range != null)
          request.response.headers.set(
            'Content-Range',
            'bytes 0-${prefix.total - 1}/${prefix.total}',
          );
        request.response.headers.set('Accept-Ranges', 'bytes');
        if (request.method == 'GET') request.response.add(prefix.bytes);
      } else {
        // If-Range failure should yield a fresh 200 body. A mismatched 206 must
        // never be interpreted as the beginning of the track.
        if (usePrefix && response.statusCode == 206)
          throw const HttpException('Audio prefix changed');
        request.response.statusCode = response.statusCode;
        for (final h in [
          'content-type',
          'content-length',
          'content-range',
          'accept-ranges',
        ]) {
          final v = response.headers[h];
          if (v != null) request.response.headers.set(h, v);
        }
      }
      if (request.method == 'HEAD') {
        await PublicNetworkClient.cancelBody(response);
      } else {
        final watch = Stopwatch()..start();
        var bytes = 0;
        await request.response.addStream(
          response.stream.timeout(const Duration(seconds: 25)).map((chunk) {
            bytes += chunk.length;
            if (bytes >= 65536) {
              StreamingPolicy.instance.observe(bytes, watch.elapsed);
              bytes = 0;
              watch.reset();
            }
            return chunk;
          }),
        );
      }
    } catch (_) {
      try {
        request.response.statusCode = 502;
      } catch (_) {}
    } finally {
      client.close();
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    cancelPreload();
    _routes.clear();
    await _server?.close(force: true);
    _server = null;
    _starting = null;
    _listening = false;
  }
}
