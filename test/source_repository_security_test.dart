import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/audio_relay_service.dart';
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/services/source_repository_service.dart';

void main() {
  test('catalog requests reject local and reserved addresses', () {
    for (final ip in [
      '127.0.0.1',
      '10.1.2.3',
      '169.254.169.254',
      '172.16.0.1',
      '192.168.1.1',
      '100.64.0.1',
      '::1',
      'fc00::1',
      'fe80::1',
      '::ffff:127.0.0.1',
      '2001:db8::1',
    ]) {
      expect(
        PublicNetworkClient.publicAddress(InternetAddress(ip)),
        false,
        reason: ip,
      );
    }
    expect(PublicNetworkClient.publicAddress(InternetAddress('8.8.8.8')), true);
    expect(
      PublicNetworkClient.publicAddress(
        InternetAddress('2606:4700:4700::1111'),
      ),
      true,
    );
  });
  test(
    'rejects credentials, cleartext, local names, fragments and custom ports',
    () {
      for (final url in [
        'http://example.org/a',
        'https://localhost/a',
        'https://a.local/a',
        'https://user:password@example.org/a',
        'https://example.org:8443/a',
        'https://example.org/a#fragment',
      ]) {
        expect(
          PublicNetworkClient.publicHttps(Uri.parse(url)),
          false,
          reason: url,
        );
      }
    },
  );
  test('normalizes GitHub repository and explicit blob indexes', () {
    expect(
      SourceRepositoryService.indexUri('https://github.com/owner/repo.git')
          .toString(),
      'https://api.github.com/repos/owner/repo/contents/registry.json',
    );
    expect(
      SourceRepositoryService.indexUri(
        'https://github.com/owner/repo/blob/main/index.json',
      ).toString(),
      'https://raw.githubusercontent.com/owner/repo/main/index.json',
    );
  });
  test(
    'reads Mornye registry aliases but does not treat JavaScript as executable',
    () {
      final entries = SourceRepositoryService.parse(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'extensions': [
              {
                'id': 'mornye-test',
                'displayName': 'Source',
                'downloadUrl': 'https://example.org/a.js',
              },
              {
                'id': 'catalog-test',
                'name': 'Catalog',
                'runtime': 'yazhal-catalog-v1',
              },
            ],
          }),
        ),
      );
      expect(entries.first.name, 'Source');
      expect(entries.first.compatible, false);
      expect(entries.last.compatible, true);
    },
  );
  test('rejects oversized or malformed registries', () {
    expect(
      () => SourceRepositoryService.parse(utf8.encode('{}')),
      throwsFormatException,
    );
    expect(
      () => SourceRepositoryService.parse(List.filled(4 * 1024 * 1024 + 1, 0)),
      throwsFormatException,
    );
  });
  final manifest = {
    'schemaVersion': 1,
    'id': 'catalog-test',
    'name': 'Catalog',
    'searchUrl': 'https://example.org/search?q={query}',
    'allowedHosts': ['example.org'],
  };
  test(
    'verifies package checksum and identity before allowing installation',
    () async {
      final bytes = utf8.encode(jsonEncode(manifest));
      final service = SourceRepositoryService(
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      final entry = SourceRepositoryEntry({
        'id': 'catalog-test',
        'runtime': 'yazhal-catalog-v1',
        'manifestUrl': 'https://example.org/catalog.json',
        'sha256': sha256.convert(bytes).toString(),
      });
      final extension = await service.resolve(entry);
      expect(extension.enabled, false);
      expect(extension.id, 'catalog-test');
      final tampered = SourceRepositoryEntry({
        ...entry.data,
        'sha256': '0' * 64,
      });
      await expectLater(service.resolve(tampered), throwsFormatException);
      service.close();
    },
  );
  test('JavaScript packages are rejected before a network request', () async {
    final service = SourceRepositoryService(
      client: MockClient((_) async => throw StateError('must not fetch')),
    );
    await expectLater(
      service.resolve(SourceRepositoryEntry({'id': 'js'})),
      throwsFormatException,
    );
    service.close();
  });
  test('redirect to private address is rejected before following it', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://127.0.0.1/secret'},
      );
    });
    await expectLater(
      AudioRelayService.instance.open(
        client,
        Uri.parse('https://example.org/a'),
        allows: (_) => true,
      ),
      throwsFormatException,
    );
    expect(calls, 1);
    client.close();
  });
}
