import 'package:yazhal/utilities/local_tracks.dart';

String downloadSourceKey(Map song) => song['source'] == 'js-extension'
    ? 'js:${song['extensionId']}'
    : isExtensionTrack(song)
    ? 'catalog:${song['extensionId']}'
    : isLocalTrack(song)
    ? 'local'
    : 'youtube';
