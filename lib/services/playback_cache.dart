// Pinned just_audio StreamAudioSource contract; guarded by range, quota and cancellation tests.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/services/streaming_policy.dart';

typedef AudioOpener = Future<http.StreamedResponse> Function(
  http.Client client,
  Map<String, String> headers,
);

/// One network transfer per representation. Consumers read a growing disk file,
/// so neither a long track nor a slow reader accumulates the track in RAM.
class PlaybackCache {
  PlaybackCache({this.directory, http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? PublicNetworkClient.create;
  static final instance = PlaybackCache();
  final Directory? directory;
  final http.Client Function() clientFactory;
  final _jobs = <String, CachedAudioJob>{};
  String? _active, _next;
  final _retiring = <String>{};
  static bool get enabled =>
      Hive.box('settings').get('playbackCacheEnabled', defaultValue: true) ==
      true;
  int get quota =>
      ((Hive.box('settings').get('playbackCacheMiB', defaultValue: 512) as num)
          .toInt()
          .clamp(128, 1024)) *
      1024 *
      1024;
  Future<Directory> root() async =>
      (directory ??
              Directory(
                '${(await getTemporaryDirectory()).path}/yazhal_audio_buffer',
              ))
          .create(recursive: true);
  static String key(Map song, String quality) => sha256
      .convert(utf8.encode('${song['ytid']}|${song['extensionId']}|$quality'))
      .toString();
  Future<CachedAudioJob> _job(String key, AudioOpener open) async {
    final existing = _jobs[key];
    if (existing != null && existing.failure == null && !existing.cancelled)
      return existing;
    if (existing != null) {
      _jobs.remove(key);
      await existing.cancel();
    }
    final dir = await root();
    await trim(reserve: quota ~/ 2);
    return _jobs.putIfAbsent(
      key,
      () => CachedAudioJob(
        File('${dir.path}/$key.audio'),
        open,
        clientFactory,
        min(quota ~/ 2, 256 * 1024 * 1024),
      ),
    );
  }

  Future<AudioSource> source(
    String key,
    AudioOpener open, {
    dynamic tag,
  }) async {
    final previous = _active;
    _active = key;
    if (_next == key) _next = null;
    if (previous != null && previous != key && previous != _next)
      _retiring.add(previous);
    final job = await _job(key, open);
    return BufferedAudioSource(job, tag: tag);
  }

  Future<void> releaseRetired() async {
    if (_jobs.isEmpty && _retiring.isEmpty) return;
    for (final key in _retiring.toList()) {
      if (key != _active && key != _next) await _jobs.remove(key)?.cancel();
      _retiring.remove(key);
    }
    await trim();
  }

  Future<void> preload(String key, AudioOpener open) async {
    if (key == _active) return;
    if (_next != key) await cancelPreload();
    _next = key;
    final job = await _job(key, open);
    await job
        .start(); // Starts filling immediately, not at the end of the song.
  }

  Future<void> cancelPreload({String? preserveKey}) async {
    if (_next != null && _next == preserveKey) return;
    final key = _next;
    _next = null;
    if (key != null && key != _active) await _jobs.remove(key)?.cancel();
  }

  Future<int> bytes() async {
    var total = 0;
    await for (final f in (await root()).list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  Future<void> trim({int reserve = 0}) async {
    final files = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entity in (await root()).list()) {
      if (entity is File) {
        final stat = await entity.stat();
        total += stat.size;
        files.add((file: entity, stat: stat));
      }
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in files) {
      final f = entry.file;
      if (total <= quota - reserve) break;
      if ((_active != null && f.path.contains(_active!)) ||
          (_next != null && f.path.contains(_next!)) ||
          _retiring.any(f.path.contains))
        continue;
      final length = entry.stat.size;
      await f.delete();
      total -= length;
    }
  }

  /// The active reader retains its file until the track is changed.
  Future<void> clear() async {
    await cancelPreload();
    for (final key in _jobs.keys.toList()) {
      if (key != _active && !_retiring.contains(key))
        await _jobs.remove(key)?.cancel();
    }
    await for (final entity in (await root()).list()) {
      if (entity is File &&
          (_active == null || !entity.path.contains(_active!)) &&
          !_retiring.any(entity.path.contains))
        await entity.delete();
    }
  }
}

class CachedAudioJob {
  CachedAudioJob(this.file, this.open, this.clientFactory, this.limit);
  final File file;
  final AudioOpener open;
  final http.Client Function() clientFactory;
  final int limit;
  http.Client? _client;
  Future<void>? _starting;
  Future<void>? _transfer;
  http.StreamedResponse? _pendingDirectResponse;
  Completer<void> _changed = Completer<void>();
  int available = 0;
  int? total;
  String contentType = 'audio/mpeg';
  String? validator;
  bool complete = false, cancelled = false, ranges = false, bypass = false;
  Object? failure;
  File get partial => File('${file.path}.part');
  File get meta => File('${file.path}.json');
  void _notify() {
    final old = _changed;
    _changed = Completer<void>();
    if (!old.isCompleted) old.complete();
  }

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (await file.exists() && await meta.exists()) {
      try {
        final m = jsonDecode(await meta.readAsString()) as Map;
        total = m['length'] as int;
        contentType = m['type'] as String;
        if (await file.length() == total) {
          available = total!;
          complete = true;
          await file.setLastModified(DateTime.now());
          return;
        }
      } catch (_) {
        /* A partial or corrupt file is fetched again. */
      }
    }
    final client = _client = clientFactory();
    try {
      final response = await open(client, {});
      if (response.statusCode != 200) {
        await PublicNetworkClient.cancelBody(response);
        throw HttpException('Audio source returned ${response.statusCode}');
      }
      total = response.contentLength;
      contentType =
          response.headers['content-type']?.split(';').first ?? 'audio/mpeg';
      if (contentType.startsWith('text/') || contentType.contains('json')) {
        await PublicNetworkClient.cancelBody(response);
        throw const FormatException(
          'Provider returned a page instead of audio',
        );
      }
      // Without Content-Length a transfer cannot safely reserve a disk budget.
      // Stream it directly rather than fail mid-song when the quota is reached.
      if (total == null || total! > limit) {
        bypass = true;
        // Keep this first response: reopening it doubles connection setup and
        // discards the exact initial bytes needed for fast startup.
        _pendingDirectResponse = response;
        return;
      }
      validator = response.headers['etag'] ?? response.headers['last-modified'];
      ranges = response.headers['accept-ranges'] == 'bytes';
      if (cancelled) {
        client.close();
        return;
      }
      final output = await partial.open(mode: FileMode.write);
      final watch = Stopwatch()..start();
      var observed = 0;
      _transfer = () async {
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            if (cancelled) break;
            if (available + chunk.length > limit)
              throw const FormatException('Playback cache quota exceeded');
            await output.writeFrom(chunk);
            available += chunk.length;
            observed += chunk.length;
            if (observed >= 65536) {
              StreamingPolicy.instance.observe(observed, watch.elapsed);
              observed = 0;
              watch.reset();
            }
            _notify();
          }
          if (cancelled) return;
          if (total != null && available != total)
            throw const HttpException('Audio transfer interrupted');
          total ??= available;
          await output.flush();
          await output.close();
          await partial.rename(file.path);
          await meta.writeAsString(
            jsonEncode({'length': total, 'type': contentType}),
            flush: true,
          );
          complete = true;
        } catch (error) {
          failure = error;
          try {
            await output.close();
          } catch (_) {}
        } finally {
          try {
            await output.close();
          } catch (_) {}
          client.close();
          _notify();
        }
      }();
    } catch (error) {
      failure = error;
      client.close();
      _notify();
      rethrow;
    }
  }

  Stream<List<int>> read(int start, int? end) async* {
    var cursor = start;
    while (end == null || cursor < end) {
      if (cancelled) throw const HttpException('Buffer cancelled');
      if (failure != null) throw failure!;
      final ready = min(available, end ?? available);
      if (cursor < ready) {
        final target = complete ? file : partial;
        // Limit each read to 64 KiB even when the entire FLAC is cached.
        final stop = min(ready, cursor + 65536);
        try {
          await for (final chunk in target.openRead(cursor, stop)) {
            yield chunk;
          }
        } on FileSystemException {
          if (!await file.exists() && total == available) await _transfer;
          if (!await file.exists()) rethrow;
          await for (final chunk in file.openRead(cursor, stop)) {
            yield chunk;
          }
        }
        cursor = stop;
      } else if (complete) {
        break;
      } else {
        final changed = _changed.future;
        if (cursor >= available && !complete && failure == null)
          await changed.timeout(const Duration(seconds: 35));
      }
    }
  }

  Future<StreamAudioResponse> request([int? start, int? end]) async {
    await this.start();
    if (bypass) {
      final pending = _pendingDirectResponse;
      _pendingDirectResponse = null;
      final usePending = pending != null && (start ?? 0) == 0 && end == null;
      if (pending != null && !usePending) {
        await PublicNetworkClient.cancelBody(pending);
        _client?.close();
      }
      final client = usePending ? _client! : clientFactory();
      final response = usePending
          ? pending
          : await open(client, {
              if (start != null || end != null)
                'Range': 'bytes=${start ?? 0}-${end == null ? '' : end - 1}',
            });
      if (response.statusCode != 200 && response.statusCode != 206) {
        await PublicNetworkClient.cancelBody(response);
        client.close();
        throw HttpException('Audio source returned ${response.statusCode}');
      }
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      return StreamAudioResponse(
        sourceLength: match == null
            ? response.contentLength
            : int.parse(match[3]!),
        contentLength: response.contentLength,
        offset: match == null ? 0 : int.parse(match[1]!),
        contentType: response.headers['content-type'] ?? contentType,
        stream: () async* {
          try {
            yield* response.stream.timeout(const Duration(seconds: 30));
          } finally {
            client.close();
          }
        }(),
      );
    }
    final offset = start ?? 0;
    if (offset < 0 || (end != null && end < offset))
      throw const FormatException('Invalid audio range');
    final stop = total == null ? end : min(end ?? total!, total!);
    // MP4/AAC metadata may be at the tail, even in a sub-megabyte song.
    // Fetch any uncached nonzero seek directly; never wait for the full file
    // just to let the decoder inspect its duration/seek table.
    if (ranges && total != null && offset > available) {
      final client = clientFactory();
      final response = await open(client, {
        'Range': 'bytes=$offset-${stop == null ? '' : stop - 1}',
        if (validator != null) 'If-Range': validator!,
      });
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      if (response.statusCode != 206 ||
          match == null ||
          int.parse(match[1]!) != offset ||
          int.parse(match[3]!) != total ||
          (validator != null &&
              (response.headers['etag'] ?? response.headers['last-modified']) !=
                  validator)) {
        await PublicNetworkClient.cancelBody(response);
        client.close();
        throw const HttpException('Audio changed while seeking');
      }
      return StreamAudioResponse(
        sourceLength: total,
        contentLength: response.contentLength,
        offset: offset,
        contentType: contentType,
        stream: () async* {
          try {
            yield* response.stream;
          } finally {
            client.close();
          }
        }(),
      );
    }
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: stop == null ? null : max(0, stop - offset),
      offset: offset,
      contentType: contentType,
      stream: read(offset, stop),
    );
  }

  Future<void> get finished async {
    await start();
    await _transfer;
    if (failure != null) throw failure!;
  }

  Future<void> cancel() async {
    cancelled = true;
    final pending = _pendingDirectResponse;
    _pendingDirectResponse = null;
    if (pending != null) await PublicNetworkClient.cancelBody(pending);
    _client?.close();
    _notify();
    try {
      await _transfer;
    } catch (_) {}
    if (await partial.exists()) {
      try {
        await partial.delete();
      } catch (_) {}
    }
  }
}

class BufferedAudioSource extends StreamAudioSource {
  BufferedAudioSource(this.job, {super.tag});
  final CachedAudioJob job;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) =>
      job.request(start, end);
}
