/// Local tracks retain a namespaced `ytid` for compatibility with existing
/// queues and playlists. Never pass that identifier to an online provider.
bool isLocalTrackId(Object? id) => id?.toString().startsWith('local:') ?? false;
bool isLocalTrack(Map song) =>
    song['source'] == 'local' || isLocalTrackId(song['ytid']);

const supportedAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'ogg',
  'opus',
  'wav',
  'webm',
  '3gpp',
};
String fileExtension(String name) => name.split('.').last.toLowerCase();
bool isAudioFilename(String name) =>
    supportedAudioExtensions.contains(fileExtension(name));
bool isPlaylistFilename(String name) =>
    {'m3u', 'm3u8'}.contains(fileExtension(name));

String safeAudioFilename(String title, String id, String extension) {
  var stem = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (stem.length > 80) stem = stem.substring(0, 80);
  stem = stem.replaceAll(RegExp(r'[. ]+$'), '');
  if (stem.isEmpty) stem = 'Track';
  final safeId = id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
  final ext = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return '$stem [$safeId].${ext.isEmpty ? 'm4a' : ext}';
}

bool isExtensionTrack(Map song) =>
    song['source'] == 'extension' || isExtensionTrackId(song['ytid']);
bool isExtensionTrackId(Object? id) =>
    id?.toString().startsWith('ext:') ?? false;
bool isNonYoutubeId(Object? id) => isLocalTrackId(id) || isExtensionTrackId(id);
