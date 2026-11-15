import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/source_diagnostics.dart';
import 'package:yazhal/services/youtube_search_provider.dart';

/// The selected source is explicit; failure never silently changes catalogues.
class ProviderRouter {
  static final changes = ValueNotifier<int>(0);
  static const youtubeId = 'builtin:youtube';
  static bool get youtubeEnabled => selected == youtubeId;
  static bool get youtubeAllowed =>
      Hive.box('settings').get('youtubeSearchEnabled', defaultValue: false) ==
      true;
  static List<Map> get available => [
    {
      'id': youtubeId,
      'name': 'YouTube (Musify)',
      'kind': 'builtin',
      'enabled': youtubeAllowed,
      'description': 'Original Musify search. Use classic search for artists, albums and playlists.',
      'manifest': {
        'type': ['metadata_provider', 'download_provider'],
      },
    },
    ...NativeExtensionService.installed.where(
      (p) =>
          NativeExtensionService.unsupportedFeatures(p).isEmpty &&
          ((p['manifest'] as Map?)?['type'] as List? ?? []).contains(
            'metadata_provider',
          ),
    ),
    for (final catalog in FlacExtensionService.extensions)
      if (catalog.enabled || catalog.builtIn)
        {
          'id': 'catalog:${catalog.id}',
          'name': catalog.name,
          'enabled': catalog.enabled,
          'kind': 'catalog',
          'description': catalog.builtIn
              ? 'Live concert recordings · original FLAC. A different catalogue from JioSaavn.'
              : 'FLAC audio catalogue',
          'manifest': {
            'type': ['metadata_provider', 'download_provider'],
          },
        },
  ];
  static List<Map> get searchable =>
      available.where((p) => p['enabled'] == true).toList();
  static String? get selected {
    final requested = Hive.box('settings')
        .get('selectedJavascriptSearch')
        ?.toString();
    final providers = searchable;
    if (providers.any((p) => p['id'] == requested)) return requested;
    return providers
            .where((p) => p['id'] == 'jiosaavn')
            .firstOrNull?['id']
            ?.toString() ??
        providers.firstOrNull?['id']?.toString();
  }

  static Future<void> select(String id) async {
    final provider = available.where((p) => p['id'] == id).firstOrNull;
    if (provider == null) throw StateError('Provider is not available');
    if (provider['enabled'] != true) {
      if (id == youtubeId) {
        await Hive.box('settings').put('youtubeSearchEnabled', true);
      } else if (id.startsWith('catalog:')) {
        final catalog = FlacExtensionService.extensions.firstWhere(
          (e) => 'catalog:${e.id}' == id,
        );
        await FlacExtensionService.enable(catalog, true);
      } else {
        await NativeExtensionService.enable(id, true);
      }
    }
    await Hive.box('settings').put('selectedJavascriptSearch', id);
    changes.value++;
  }

  static Future<List<Map<String, dynamic>>> searchFrom(
    String id,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];
    if (!searchable.any((p) => p['id'] == id))
      throw StateError('Provider is disabled');
    if (id == youtubeId) return YouTubeSearchProvider().search(query);
    if (id.startsWith('catalog:')) {
      final catalog = FlacExtensionService.extensions.firstWhere(
        (e) => 'catalog:${e.id}' == id,
      );
      return FlacExtensionService.instance
          .search(catalog, query)
          .timeout(const Duration(seconds: 30));
    }
    return NativeExtensionService.instance
        .search(id, query)
        .timeout(const Duration(seconds: 25));
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final id = selected;
    return id == null ? [] : searchFrom(id, query);
  }

  static String searchProblem(Object error, String provider) {
    final text = error.toString();
    if (text.contains('site_unavailable'))
      return '$provider returned a Site Unavailable page instead of song data (HTTP 200). Check source diagnostics or choose another provider.';
    if (text.contains('http_429'))
      return '$provider is rate-limiting requests. Wait before retrying or choose another provider.';
    if (text.contains('http_403') || text.contains('http_451'))
      return '$provider refused this request. Check source diagnostics; service, regional or network restrictions are possible.';
    if (text.contains('network_dns'))
      return 'Could not resolve $provider. Check DNS/network settings or run source diagnostics.';
    if (text.contains('network_blocked') || text.contains('network_tls'))
      return diagnosisExplanation(text);
    if (text.contains('network_timeout') || text.contains('TimeoutException')) {
      return '$provider took too long to respond. Retry or choose another provider.';
    }
    if (text.contains('network_unreachable') || text.contains('network_tls')) {
      return 'Could not connect to $provider. Check your connection, retry or choose another provider.';
    }
    return '$provider is unavailable right now. Retry or choose another provider.';
  }
}
