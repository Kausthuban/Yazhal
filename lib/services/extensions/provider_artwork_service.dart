import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/audio_relay_service.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/utilities/provider_artwork.dart';

/// Covers from JavaScript providers never enter a generic network-image loader.
class ProviderArtworkService {
  static final instance = ProviderArtworkService();
  final _pending = <String, Future<File?>>{};
  File? cached(String token) {
    try {
      final f = File(
        '$applicationDirPath/${FilePaths.artworksDir}/provider_${sha256.convert(utf8.encode(token))}.img',
      );
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }

  Future<File?> load(String token) => _pending.putIfAbsent(
    token,
    () => _load(token).whenComplete(() {
      _pending.remove(token);
    }),
  );
  Future<File?> _load(String token) async {
    final existing = cached(token);
    if (existing != null) return existing;
    if (Hive.isBoxOpen('settings') &&
        (Hive.box('settings').get('streamingDataSaver', defaultValue: false) ==
                true ||
            Hive.box('settings').get('offlineMode', defaultValue: false) ==
                true))
      return null;
    final encoded = Uri.tryParse(token);
    if (encoded?.scheme != providerArtworkScheme ||
        encoded!.pathSegments.length != 1)
      return null;
    final package = await NativeExtensionService.instance.load(encoded.host);
    final uri = Uri.parse(
      utf8.decode(base64Url.decode(encoded.pathSegments.single)),
    );
    bool allows(Uri u) =>
        package.allows(u) ||
        (PublicNetworkClient.publicHttps(u) &&
            package.hosts.contains('aac.saavncdn.com') &&
            u.host == 'c.saavncdn.com');
    if (!allows(uri)) return null;
    final client = PublicNetworkClient.create();
    try {
      final response = await AudioRelayService.instance.open(
        client,
        uri,
        allows: allows,
      );
      if (response.statusCode != 200) {
        await PublicNetworkClient.cancelBody(response);
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 12),
      )) {
        if (bytes.length + chunk.length > 6 * 1024 * 1024)
          throw const FormatException('Cover art exceeds 6 MiB');
        bytes.addAll(chunk);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        Uint8List.fromList(bytes),
      );
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width * descriptor.height > 16000000)
            throw const FormatException('Cover art dimensions exceed limit');
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      await FilePaths.ensureDirectoriesExist();
      final file = File(
        '$applicationDirPath/${FilePaths.artworksDir}/provider_${sha256.convert(utf8.encode(token))}.img',
      );
      await file.writeAsBytes(bytes, flush: true);
      final cachedFiles =
          await Directory('$applicationDirPath/${FilePaths.artworksDir}')
              .list()
              .where(
                (f) =>
                    f is File &&
                    f.path
                        .split(Platform.pathSeparator)
                        .last
                        .startsWith('provider_'),
              )
              .cast<File>()
              .toList();
      if (cachedFiles.length > 80) {
        cachedFiles.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );
        for (final old in cachedFiles.take(cachedFiles.length - 80)) {
          if (old.path != file.path) await old.delete();
        }
      }
      return file;
    } finally {
      client.close();
    }
  }
}
