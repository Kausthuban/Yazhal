import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yazhal/constants/version.dart';
import 'package:yazhal/services/public_network_client.dart';

String safeNetworkFailure(Object error) {
  final text = error.toString().toLowerCase();
  for (final code in [
    'network_timeout',
    'network_tls',
    'network_dns',
    'network_blocked',
  ]) {
    if (text.contains(code)) return code;
  }
  if (error is TimeoutException || text.contains('timed out'))
    return 'network_timeout';
  if (error is HandshakeException ||
      text.contains('handshakeexception') ||
      text.contains('certificate_verify'))
    return 'network_tls';
  if (text.contains('failed host lookup') ||
      text.contains('name or service not known'))
    return 'network_dns';
  if (text.contains('private or reserved') ||
      text.contains('only public https'))
    return 'network_blocked';
  return 'network_unreachable';
}

/// Shared by the actual extension host and diagnostic probe. Never treats a
/// successful HTTP status as proof that song data was returned.
String? jioResponseProblem(
  int status,
  String? mime,
  String body, {
  bool searchResponse = true,
}) {
  if (status != 200) return 'provider_unavailable:http_$status';
  // PHP/edge responses may label valid JSON as text/html. Validate payload
  // first; a MIME label or a song title must never create a false outage.
  try {
    final value = jsonDecode(body);
    if ((searchResponse && (value is! Map || value['results'] is! List)) ||
        (!searchResponse && value is! Map && value is! List)) {
      return 'provider_unavailable:json_schema:http_200';
    }
  } catch (_) {
    if (body.toLowerCase().contains('site unavailable'))
      return 'provider_unavailable:site_unavailable:http_200';
    if ((mime ?? '').toLowerCase().contains('text/html') ||
        body.trimLeft().startsWith('<'))
      return 'provider_unavailable:html:http_200';
    return 'provider_unavailable:invalid_json:http_200';
  }
  return null;
}

String diagnosisExplanation(String code) {
  if (code.contains('site_unavailable'))
    return 'The API returned a Site Unavailable page, not song data. This confirms a provider/edge response problem on this connection, not an empty search.';
  if (code.contains('http_429'))
    return 'The provider is rate-limiting requests. Wait before retrying.';
  if (code.contains('http_403') || code.contains('http_451'))
    return 'The provider refused this request. This may be a service, regional or network restriction; the status alone cannot identify which.';
  if (code.contains('html'))
    return 'The API returned an HTML page instead of JSON song data.';
  if (code.contains('json'))
    return 'The API response is not the expected song-search JSON. The service or API contract may have changed.';
  if (code.contains('network_dns'))
    return 'DNS could not resolve the provider on this device.';
  if (code.contains('network_blocked'))
    return 'DNS returned a private/reserved destination. Yazhal refused it to protect local services.';
  if (code.contains('network_tls'))
    return 'A secure TLS connection failed. Check the device clock, network and provider certificate; certificate validation remains enabled.';
  if (code.contains('network_timeout'))
    return 'The connection or provider response timed out.';
  if (code.contains('network'))
    return 'The provider could not be reached on this connection.';
  return 'The installed extension failed despite the direct API check. Its saved settings, request handling or runtime need investigation.';
}

class SourceCheck {
  const SourceCheck(this.name, this.state, this.detail);
  final String name, state, detail;
}

class SourceDiagnosticReport {
  SourceDiagnosticReport(
    this.summary,
    this.checks,
    this.adapterVersion, {
    DateTime? checkedAt,
  }) : checkedAt = checkedAt ?? DateTime.now().toUtc();
  final String summary, adapterVersion;
  final List<SourceCheck> checks;
  final DateTime checkedAt;
  String toText() => [
    'Yazhal $appVersion · JioSaavn diagnostics',
    'Checked: ${checkedAt.toUtc().toIso8601String()}',
    'Installed adapter: $adapterVersion',
    summary,
    for (final check in checks)
      '${check.name} [${check.state}]: ${check.detail}',
    'No credentials, search history, response bodies or device file paths included.',
  ].join('\n');
}

class SourceDiagnostics {
  SourceDiagnostics({
    this.client,
    Future<List<InternetAddress>> Function(String)? lookup,
  }) : _lookup = lookup ?? InternetAddress.lookup;
  final http.Client? client;
  final Future<List<InternetAddress>> Function(String) _lookup;
  static final endpoint = Uri.https('www.jiosaavn.com', '/api.php', {
    '__call': 'search.getResults',
    '_format': 'json',
    '_marker': '0',
    'api_version': '4',
    'ctx': 'web6dot0',
    'q': 'music',
    'p': '1',
    'n': '1',
  });
  Future<SourceDiagnosticReport> run({
    required String adapterVersion,
    Future<int> Function()? adapterProbe,
  }) async {
    final checks = <SourceCheck>[];
    SourceDiagnosticReport finish(String summary) => SourceDiagnosticReport(
      summary,
      List.unmodifiable(checks),
      adapterVersion,
    );
    try {
      final addresses = await _lookup(endpoint.host)
          .timeout(const Duration(seconds: 10));
      if (addresses.isEmpty) throw const SocketException('Failed host lookup');
      if (addresses.any((a) => !PublicNetworkClient.publicAddress(a)))
        throw const SocketException('Private or reserved destination');
      checks.add(
        SourceCheck(
          'DNS',
          'passed',
          '${addresses.where((a) => a.type == InternetAddressType.IPv4).length} public IPv4 and ${addresses.where((a) => a.type == InternetAddressType.IPv6).length} public IPv6 answers. Addresses are not recorded.',
        ),
      );
    } catch (error) {
      final code = safeNetworkFailure(error);
      checks.add(
        SourceCheck('DNS', 'failed', '$code · ${diagnosisExplanation(code)}'),
      );
      return finish('Network/DNS failure before the provider request.');
    }
    final activeClient = client ?? PublicNetworkClient.create();
    try {
      try {
        final response = await activeClient
            .send(
              http.Request('GET', Uri.https(endpoint.host, '/'))
                ..followRedirects = false,
            )
            .timeout(const Duration(seconds: 15));
        checks.add(
          SourceCheck(
            'Website HTTPS',
            response.statusCode < 400 ? 'passed' : 'warning',
            'HTTP ${response.statusCode}; ${response.headers['content-type']?.split(';').first ?? 'unknown content type'}. This does not prove the API is available.',
          ),
        );
        await PublicNetworkClient.cancelBody(response);
      } catch (error) {
        final code = safeNetworkFailure(error);
        checks.add(
          SourceCheck(
            'Website HTTPS',
            'failed',
            '$code · ${diagnosisExplanation(code)}',
          ),
        );
      }
      var directWorks = false;
      try {
        final watch = Stopwatch()..start();
        final request = http.Request('GET', endpoint)..followRedirects = false;
        request.headers.addAll({
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://www.jiosaavn.com/',
        });
        final response = await activeClient
            .send(request)
            .timeout(const Duration(seconds: 15));
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 15),
        )) {
          if (bytes.length + chunk.length > 512 * 1024)
            throw const FormatException('response_size');
          bytes.addAll(chunk);
        }
        final body = utf8.decode(bytes, allowMalformed: true);
        final problem = jioResponseProblem(
          response.statusCode,
          response.headers['content-type'],
          body,
        );
        final prefix =
            'HTTP ${response.statusCode}; ${response.headers['content-type']?.split(';').first ?? 'unknown content type'}; ${watch.elapsedMilliseconds} ms.';
        if (problem != null) {
          checks.add(
            SourceCheck(
              'Direct search API',
              'failed',
              '$prefix $problem · ${diagnosisExplanation(problem)}',
            ),
          );
        } else {
          directWorks = true;
          final count = ((jsonDecode(body) as Map)['results'] as List).length;
          checks.add(
            SourceCheck(
              'Direct search API',
              'passed',
              '$prefix Valid song-search JSON; $count result(s). The probe uses a fixed query, not listening history.',
            ),
          );
        }
      } catch (error) {
        final code = error is FormatException
            ? 'provider_unavailable:invalid_json'
            : safeNetworkFailure(error);
        checks.add(
          SourceCheck(
            'Direct search API',
            'failed',
            '$code · ${diagnosisExplanation(code)}',
          ),
        );
      }
      if (adapterProbe == null) {
        checks.add(
          const SourceCheck(
            'Installed adapter',
            'skipped',
            'No enabled JioSaavn adapter is installed.',
          ),
        );
        return finish(
          directWorks
              ? 'The direct API works, but the installed adapter is unavailable.'
              : 'The direct API check failed and no enabled adapter is available to compare.',
        );
      }
      try {
        final count = await adapterProbe().timeout(const Duration(seconds: 30));
        checks.add(
          SourceCheck(
            'Installed adapter',
            'passed',
            '$count result(s) through the installed extension and its current settings.',
          ),
        );
        return finish(
          directWorks
              ? 'The API and installed extension responded successfully on this device. Song playback/download availability is a separate check.'
              : 'The installed extension worked while the direct anonymous probe failed. Request headers/settings or connection paths differ; this is not proof of a global outage.',
        );
      } catch (error) {
        final text = error.toString();
        final code = text.contains('site_unavailable')
            ? 'provider_unavailable:site_unavailable'
            : text.contains('provider_unavailable')
            ? 'provider_unavailable'
            : text.contains('network_')
            ? safeNetworkFailure(error)
            : 'adapter_failure';
        checks.add(
          SourceCheck(
            'Installed adapter',
            'failed',
            '$code · ${diagnosisExplanation(code)}',
          ),
        );
        return finish(
          directWorks
              ? 'The direct API works, but the installed extension failed. Its settings/headers or runtime need investigation; the service is not globally unavailable.'
              : 'Both direct API and installed extension checks failed on this connection. Compare their failure codes. This alone cannot prove a global outage or a regional restriction.',
        );
      }
    } finally {
      if (client == null) activeClient.close();
    }
  }
}
