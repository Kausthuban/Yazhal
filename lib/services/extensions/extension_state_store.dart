import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configuration, tokens and extension storage never enter unencrypted Hive or exports.
class ExtensionStateStore {
  static const _secure = FlutterSecureStorage();
  Future<Map<String, dynamic>> read(String id) async {
    final value = await _secure.read(key: 'yazhal.extension.$id');
    return value == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> write(String id, Map value) async {
    final json = jsonEncode(value);
    if (utf8.encode(json).length > 512 * 1024)
      throw const FormatException('Extension storage quota exceeded');
    await _secure.write(key: 'yazhal.extension.$id', value: json);
  }

  Future<void> remove(String id) => _secure.delete(key: 'yazhal.extension.$id');
}
