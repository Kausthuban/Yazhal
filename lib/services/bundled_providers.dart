import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';

/// Pinned, attributed open-source adapter; never replace the user's installed
/// provider or re-enable one they disabled.
class BundledProviders {
  static const digest =
      '78e5c97b6aabc78833654080e1b6573d0972526b37a19e151c831d51e90816bc';
  static Future<void> ensure() async {
    if (!NativeExtensionService.installed.any((p) => p['id'] == 'jiosaavn') &&
        Hive.box('settings').get('bundledProvidersInstalled') != true) {
      final bytes = (await rootBundle.load('assets/providers/jiosaavn.sflx'))
          .buffer
          .asUint8List();
      final package = ExtensionPackage.decode('jiosaavn', bytes, digest);
      await NativeExtensionService.instance.install(
        package,
        bytes,
        repository: 'https://github.com/mornyeapp/Mornye-Extension',
        downloadUrl: 'https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/extensions/jiosaavn.sflx',
      );
      await NativeExtensionService.enable('jiosaavn', true);
      await Hive.box('settings').put('bundledProvidersInstalled', true);
    }
    if (!Hive.box('settings').containsKey('selectedJavascriptSearch')) {
      await Hive.box('settings').put('selectedJavascriptSearch', 'jiosaavn');
    }
  }
}
