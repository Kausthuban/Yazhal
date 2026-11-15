import 'dart:convert';

import 'package:yazhal/services/public_network_client.dart';

const providerArtworkScheme = 'yazhal-artwork';
bool hasUrlCredentials(Uri uri) =>
    uri.userInfo.isNotEmpty ||
    uri.queryParameters.keys.any(
      (k) => RegExp(
        r'token|auth|password|secret|signature|api.?key|^key$|x-amz',
        caseSensitive: false,
      ).hasMatch(k),
    );
String providerArtworkToken(String provider, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !PublicNetworkClient.publicHttps(uri) ||
      hasUrlCredentials(uri))
    return '';
  return Uri(
    scheme: providerArtworkScheme,
    host: provider,
    pathSegments: [base64Url.encode(utf8.encode(uri.toString()))],
  ).toString();
}

Map<String, dynamic> publicProviderMetadata(Map raw) {
  dynamic clean(dynamic value) {
    if (value is Map)
      return {
        for (final entry in value.entries)
          if (!RegExp(
            'token|password|secret|cookie|authorization|api.?key',
            caseSensitive: false,
          ).hasMatch(entry.key.toString()))
            entry.key.toString(): clean(entry.value),
      };
    if (value is List) return value.map(clean).toList();
    if (value is String && value.startsWith('http')) {
      final uri = Uri.tryParse(value);
      if (uri != null && hasUrlCredentials(uri)) return '';
    }
    return value;
  }

  return Map<String, dynamic>.from(clean(raw) as Map);
}
