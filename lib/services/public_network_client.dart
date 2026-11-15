import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Public HTTPS requests from untrusted catalogs must never reach local services.
/// DNS is checked and pinned at socket creation, including redirected requests.
class PublicNetworkClient {
  static bool publicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && (b[1] == 168 || b[1] == 0 || (b[1] == 2))) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19 || b[1] == 51)) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113));
    }
    // RFC 6052 well-known DNS64 translation prefix. Its embedded IPv4 address
    // must also be public: never permit private targets through a NAT64 alias.
    if (b.length == 16 &&
        b[0] == 0 &&
        b[1] == 0x64 &&
        b[2] == 0xff &&
        b[3] == 0x9b &&
        b.sublist(4, 12).every((v) => v == 0)) {
      return publicAddress(InternetAddress.fromRawAddress(b.sublist(12)));
    }
    // Accept globally routable unicast only; reject mapped IPv4 and local ranges.
    return b.length == 16 &&
        (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8);
  }

  static bool publicHttps(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443))
      return false;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal'))
      return false;
    final literal = InternetAddress.tryParse(host);
    return literal == null || publicAddress(literal);
  }

  /// Race only validated, pinned DNS answers. One broken IPv6/IPv4 route must
  /// not make the entire provider unavailable. Late and cancelled sockets close.
  static Future<ConnectionTask<Socket>> connectPublic(
    Uri uri, {
    Future<List<InternetAddress>> Function(String)? lookup,
    Future<ConnectionTask<Socket>> Function(InternetAddress, int)? dial,
    Duration stagger = const Duration(milliseconds: 250),
    Duration attemptTimeout = const Duration(seconds: 8),
  }) async {
    if (!publicHttps(uri)) {
      throw const SocketException('Only public HTTPS endpoints are permitted');
    }
    final addresses = await (lookup ?? InternetAddress.lookup)(uri.host)
        .timeout(const Duration(seconds: 10));
    if (addresses.isEmpty || addresses.any((a) => !publicAddress(a))) {
      throw const SocketException(
        'Private or reserved network destination refused',
      );
    }
    final unique = <String>{};
    final primary = addresses
        .where((a) => a.type == addresses.first.type)
        .toList();
    final secondary = addresses
        .where((a) => a.type != addresses.first.type)
        .toList();
    final ordered = <InternetAddress>[];
    for (var i = 0; i < addresses.length; i++) {
      if (i < primary.length && unique.add(primary[i].address))
        ordered.add(primary[i]);
      if (i < secondary.length && unique.add(secondary[i].address))
        ordered.add(secondary[i]);
    }
    final candidates = ordered.take(16).toList();
    final result = Completer<Socket>();
    final timers = <Timer>[];
    final tasks = <ConnectionTask<Socket>>[];
    var stopped = false, remaining = candidates.length;
    Socket? winner;
    void stopAttempts({ConnectionTask<Socket>? keep}) {
      for (final timer in timers) {
        timer.cancel();
      }
      for (final task in tasks) {
        if (!identical(task, keep)) task.cancel();
      }
    }

    Future<void> attempt(InternetAddress address) async {
      if (stopped) return;
      try {
        final task = await (dial ?? Socket.startConnect)(address, uri.port);
        tasks.add(task);
        if (stopped) {
          task.cancel();
          return;
        }
        final socket = await task.socket.timeout(
          attemptTimeout,
          onTimeout: () {
            task.cancel();
            throw const SocketException('Public endpoint connection timed out');
          },
        );
        if (stopped || result.isCompleted) {
          socket.destroy();
          return;
        }
        winner = socket;
        result.complete(socket);
        stopAttempts(keep: task);
      } catch (_) {
        remaining--;
        if (!stopped && !result.isCompleted && remaining == 0) {
          result.completeError(
            const SocketException(
              'No public endpoint address could be reached',
            ),
          );
        }
      }
    }

    for (var i = 0; i < candidates.length; i++) {
      timers.add(Timer(stagger * i, () => unawaited(attempt(candidates[i]))));
    }
    return ConnectionTask.fromSocket(result.future, () {
      stopped = true;
      stopAttempts();
      winner?.destroy();
      if (!result.isCompleted)
        result.completeError(const SocketException('Connection cancelled'));
    });
  }

  /// HttpClient does not add TLS when a custom connectionFactory is supplied.
  /// Pin TCP to the validated address, then authenticate the original DNS name
  /// (SNI and certificate verification) before exposing the socket to HTTP.
  static Future<ConnectionTask<Socket>> connectSecurePublic(
    Uri uri, {
    Future<List<InternetAddress>> Function(String)? lookup,
    Future<ConnectionTask<Socket>> Function(InternetAddress, int)? dial,
    SecurityContext? context,
  }) async {
    final tcp = await connectPublic(uri, lookup: lookup, dial: dial);
    var cancelled = false;
    SecureSocket? secure;
    final future = () async {
      final socket = await tcp.socket;
      try {
        final tls = await SecureSocket.secure(
          socket,
          host: uri.host,
          context: context,
        ).timeout(const Duration(seconds: 15));
        secure = tls;
        if (cancelled) {
          tls.destroy();
          throw const SocketException('Connection cancelled');
        }
        return tls;
      } catch (_) {
        socket.destroy();
        rethrow;
      }
    }();
    return ConnectionTask.fromSocket(future, () {
      cancelled = true;
      tcp.cancel();
      secure?.destroy();
    });
  }

  static http.Client create({
    Future<List<InternetAddress>> Function(String)? lookup,
    Future<ConnectionTask<Socket>> Function(InternetAddress, int)? dial,
    SecurityContext? context,
  }) {
    final client = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, proxyHost, proxyPort) => connectSecurePublic(
        uri,
        lookup: lookup,
        dial: dial,
        context: context,
      );
    return IOClient(client);
  }

  static Future<void> cancelBody(http.StreamedResponse response) =>
      response.stream.listen((_) {}).cancel();
}
