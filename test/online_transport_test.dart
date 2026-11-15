import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/bundled_providers.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/extension_runtime.dart';
import 'package:yazhal/services/public_network_client.dart';

class TestSocket extends Fake implements Socket {
  bool destroyed = false;
  @override
  void destroy() => destroyed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final endpoint = Uri.https('audio.example.org', '/search');
  test(
    'NAT64 accepts public IPv4 translation and rejects private translation',
    () {
      for (final address in ['64:ff9b::808:808', '64:ff9b::101:101']) {
        expect(
          PublicNetworkClient.publicAddress(InternetAddress(address)),
          true,
        );
      }
      for (final address in [
        '64:ff9b::a00:1',
        '64:ff9b::7f00:1',
        '64:ff9b::a9fe:a9fe',
        '::ffff:8.8.8.8',
      ]) {
        expect(
          PublicNetworkClient.publicAddress(InternetAddress(address)),
          false,
        );
      }
    },
  );
  test(
    'unreachable first DNS address falls back to another pinned public address',
    () async {
      final attempted = <String>[];
      final good = TestSocket();
      final task = await PublicNetworkClient.connectPublic(
        endpoint,
        lookup: (_) async => [
          InternetAddress('2606:4700:4700::1111'),
          InternetAddress('8.8.8.8'),
        ],
        stagger: const Duration(milliseconds: 5),
        dial: (address, port) async {
          attempted.add(address.address);
          return ConnectionTask.fromSocket(
            address.type == InternetAddressType.IPv6
                ? Future<Socket>.delayed(
                    Duration.zero,
                    () => throw const SocketException('No IPv6 route'),
                  )
                : Future<Socket>.value(good),
            () {},
          );
        },
      );
      expect(await task.socket, same(good));
      expect(attempted, ['2606:4700:4700::1111', '8.8.8.8']);
      task.cancel();
      expect(good.destroyed, true);
    },
  );
  test(
    'a stalled first connection does not block the other address family',
    () async {
      final slow = Completer<Socket>();
      var cancelled = false;
      final good = TestSocket();
      final task = await PublicNetworkClient.connectPublic(
        endpoint,
        lookup: (_) async => [
          InternetAddress('2606:4700:4700::1111'),
          InternetAddress('8.8.8.8'),
        ],
        stagger: const Duration(milliseconds: 5),
        dial: (address, port) async => address.type == InternetAddressType.IPv6
            ? ConnectionTask.fromSocket(slow.future, () {
                cancelled = true;
                if (!slow.isCompleted)
                  slow.completeError(const SocketException('cancelled'));
              })
            : ConnectionTask.fromSocket(Future<Socket>.value(good), () {}),
      );
      expect(await task.socket.timeout(const Duration(seconds: 1)), same(good));
      expect(cancelled, true);
      task.cancel();
    },
  );
  test(
    'mixed public/private DNS refuses all attempts before dialing',
    () async {
      var dialed = false;
      await expectLater(
        PublicNetworkClient.connectPublic(
          endpoint,
          lookup: (_) async => [
            InternetAddress('8.8.8.8'),
            InternetAddress('127.0.0.1'),
          ],
          dial: (_, __) async {
            dialed = true;
            throw StateError('must not dial');
          },
        ),
        throwsA(isA<SocketException>()),
      );
      expect(dialed, false);
    },
  );
  test(
    'cancelling connection before the stagger closes it without dialing',
    () async {
      var dialed = false;
      final task = await PublicNetworkClient.connectPublic(
        endpoint,
        lookup: (_) async => [InternetAddress('8.8.8.8')],
        dial: (_, __) async {
          dialed = true;
          throw StateError('cancelled');
        },
      );
      final failed = expectLater(task.socket, throwsA(isA<SocketException>()));
      task.cancel();
      await failed;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(dialed, false);
    },
  );
  for (final status in [200, 503]) {
    test(
      'JioSaavn HTML outage ($status) becomes provider unavailable instead of empty hits',
      () async {
        final package = ExtensionPackage.decode(
          'jiosaavn',
          File('assets/providers/jiosaavn.sflx').readAsBytesSync(),
          BundledProviders.digest,
        );
        final runtime = ExtensionRuntime(
          client: MockClient(
            (_) async => http.Response(
              '<html>Site Unavailable</html>',
              status,
              headers: {'content-type': 'text/html'},
            ),
          ),
        );
        try {
          await expectLater(
            runtime.call(package, 'searchTracks', ['magale', 5]),
            throwsA(
              predicate((e) => e.toString().contains('provider_unavailable')),
            ),
          );
        } finally {
          runtime.close();
        }
      },
      skip: Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] == null
          ? 'Native QuickJS library required'
          : false,
    );
  }
  test(
    'actual JioSaavn adapter accepts valid search JSON labelled text/html',
    () async {
      final package = ExtensionPackage.decode(
        'jiosaavn',
        File('assets/providers/jiosaavn.sflx').readAsBytesSync(),
        BundledProviders.digest,
      );
      final runtime = ExtensionRuntime(
        client: MockClient(
          (_) async => http.Response(
            '{"results":[{"id":"abcd1234","type":"song","title":"Tamil song","primary_artists":"Artist","more_info":{"language":"tamil","duration":"180"}}]}',
            200,
            headers: {'content-type': 'text/html; charset=UTF-8'},
          ),
        ),
      );
      try {
        final result = await runtime.call(package, 'searchTracks', [
          'magale',
          5,
        ]);
        expect((result.value as List).single['id'], 'abcd1234');
        expect((result.value as List).single['language'], 'tamil');
      } finally {
        runtime.close();
      }
    },
    skip: Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] == null
        ? 'Native QuickJS test library required'
        : false,
  );
}
