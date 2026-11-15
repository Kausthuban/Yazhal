import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/source_diagnostics.dart';

void main() {
  Future<List<InternetAddress>> lookup(String _) async => [
    InternetAddress('8.8.8.8'),
  ];
  test(
    'HTTP 200 Site Unavailable is distinguished from empty valid results',
    () {
      expect(
        jioResponseProblem(200, 'text/html', '<html>Site Unavailable</html>'),
        contains('site_unavailable'),
      );
      expect(
        jioResponseProblem(200, 'application/json', '{"results":[]}'),
        null,
      );
      expect(
        jioResponseProblem(
          200,
          'text/html',
          '{"results":[{"title":"Site Unavailable"}]}',
        ),
        null,
      );

      expect(
        jioResponseProblem(429, 'application/json', '{}'),
        contains('http_429'),
      );
      expect(
        jioResponseProblem(
          200,
          'application/json',
          '{"songs":[]}',
          searchResponse: false,
        ),
        null,
      );
      expect(
        jioResponseProblem(200, 'application/json', '{"songs":[]}'),
        contains('json_schema'),
      );
    },
  );
  test('API HTML failure is compared with the adapter without copying body or credentials', () async {
    var adapterCalled = false;
    final source = SourceDiagnostics(
      lookup: lookup,
      client: MockClient(
        (request) async => http.Response(
          request.url.path == '/'
              ? '<html>home</html>'
              : '<html>Site Unavailable token=private-secret</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    final report = await source.run(
      adapterVersion: '1.0.10',
      adapterProbe: () async {
        adapterCalled = true;
        return 1;
      },
    );
    expect(adapterCalled, true);
    expect(report.summary, contains('installed extension worked'));
    expect(report.checks.last.state, 'passed');
    expect(report.toText(), contains('HTTP 200; text/html'));
    expect(report.toText(), contains('site_unavailable'));
    expect(report.toText(), isNot(contains('private-secret')));
    expect(report.toText(), isNot(contains('<html>')));
  });
  test('valid direct JSON plus adapter failure identifies a settings/runtime boundary rather than global outage', () async {
    final source = SourceDiagnostics(
      lookup: lookup,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [
              {'id': 'a'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final report = await source.run(
      adapterVersion: '1',
      adapterProbe: () async => throw StateError('secret-cookie token=value'),
    );
    expect(report.summary, contains('direct API works'));
    expect(report.checks.last.state, 'failed');
    expect(report.toText(), isNot(contains('secret-cookie')));
  });
  test(
    'direct API and installed adapter success are reported separately',
    () async {
      final source = SourceDiagnostics(
        lookup: lookup,
        client: MockClient(
          (_) async => http.Response(
            '{"results":[]}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final report = await source.run(
        adapterVersion: '1',
        adapterProbe: () async => 0,
      );
      expect(report.summary, contains('responded successfully'));
      expect(report.checks.last.state, 'passed');
      expect(report.toText(), contains('0 result(s)'));
    },
  );
  test('DNS failure prevents HTTP and adapter calls and does not expose raw error paths', () async {
    var called = false;
    final source = SourceDiagnostics(
      lookup: (_) async =>
          throw const SocketException('Failed host lookup /private/path'),
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );
    final report = await source.run(adapterVersion: '1');
    expect(called, false);
    expect(report.toText(), contains('network_dns'));
    expect(report.toText(), isNot(contains('/private/path')));
  });
  test('private DNS results fail closed before a provider request', () async {
    var called = false;
    final source = SourceDiagnostics(
      lookup: (_) async => [InternetAddress('127.0.0.1')],
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );
    final report = await source.run(adapterVersion: '1');
    expect(called, false);
    expect(report.toText(), contains('network_blocked'));
  });
  test('rate limit, TLS and malformed JSON receive distinct safe diagnostic classifications', () {
    expect(
      safeNetworkFailure(const HandshakeException('secret certificate data')),
      'network_tls',
    );
    expect(
      jioResponseProblem(403, 'text/html', 'denied'),
      contains('http_403'),
    );
    expect(
      jioResponseProblem(200, 'text/plain', 'not json'),
      contains('invalid_json'),
    );
  });
  test(
    'two failed request paths are reported without assuming a global outage',
    () async {
      final source = SourceDiagnostics(
        lookup: lookup,
        client: MockClient(
          (_) async => http.Response(
            '<html>Site Unavailable</html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      final report = await source.run(
        adapterVersion: '1',
        adapterProbe: () async => throw StateError(
          'provider_unavailable:site_unavailable secret=value',
        ),
      );
      expect(
        report.summary,
        contains('Both direct API and installed extension checks failed'),
      );
      expect(report.toText(), isNot(contains('secret=value')));
    },
  );
}
