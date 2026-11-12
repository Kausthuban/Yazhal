/// Parses standard M3U/M3U8 without performing I/O or network requests.
class M3uEntry {
  const M3uEntry(this.location, {this.title, this.duration});
  final String location;
  final String? title;
  final int? duration;
}

List<M3uEntry> parseM3u(String text) {
  if (text.length > 4 * 1024 * 1024)
    throw const FormatException('Playlist exceeds 4 MiB');
  final entries = <M3uEntry>[];
  String? title;
  int? duration;
  for (var line
      in text.replaceFirst('\uFEFF', '').split(RegExp(r'\r\n|\n|\r'))) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.toUpperCase().startsWith('#EXTINF:')) {
      final comma = line.indexOf(',');
      if (comma != -1) {
        duration = int.tryParse(line.substring(8, comma).trim());
        title = line.substring(comma + 1).trim();
      }
      continue;
    }
    if (line.startsWith('#')) continue;
    entries.add(M3uEntry(line, title: title, duration: duration));
    title = null;
    duration = null;
    if (entries.length > 20000)
      throw const FormatException('Too many playlist entries');
  }
  return entries;
}

/// Resolve only within the selected music tree. Absolute exports can be
/// remapped by explicitly selecting their original root in the import UI.
String? resolvePlaylistEntry(
  String playlistRelativePath,
  String location, {
  String? originalRoot,
}) {
  var path = location.replaceAll('\\', '/');
  if (path.startsWith('file:')) {
    try {
      path = Uri.parse(path).toFilePath(windows: false);
    } catch (_) {
      return null;
    }
  } else if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(path) &&
      !RegExp('^[A-Za-z]:/').hasMatch(path)) {
    return null;
  }
  var remapped = false;
  if (originalRoot != null && originalRoot.trim().isNotEmpty) {
    final root = originalRoot
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    if (path.startsWith('$root/')) {
      remapped = true;
      path = path.substring(root.length + 1);
    }
  }
  if (path.startsWith('/') || RegExp('^[A-Za-z]:').hasMatch(path)) return null;
  final parent = playlistRelativePath.replaceAll('\\', '/').split('/')
    ..removeLast();
  // A remapped absolute entry is rooted at the selected tree, not the M3U's parent.
  final parts = <String>[if (!remapped) ...parent];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}
