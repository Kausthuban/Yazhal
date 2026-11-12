import 'package:material_ui/material_ui.dart';
import 'package:yazhal/extensions/l10n.dart';
import 'package:yazhal/main.dart';
import 'package:yazhal/utilities/playlist_dialogs.dart';

/// Keys are canonical row objects, not IDs or filtered row positions. This
/// preserves distinct occurrences of a recording through sorting and filtering.
class SongSelectionController extends ChangeNotifier {
  bool active = false;
  bool busy = false;
  final Set<Map> selected = Set<Map>.identity();
  void enter() {
    active = true;
    notifyListeners();
  }

  void toggle(Map song) {
    if (busy) return;
    active = true;
    if (!selected.remove(song)) selected.add(song);
    notifyListeners();
  }

  void selectAll(Iterable<Map> songs) {
    if (busy) return;
    selected.addAll(songs);
    notifyListeners();
  }

  void clear() {
    if (busy) return;
    active = false;
    selected.clear();
    notifyListeners();
  }
}

class SongSelectionScope extends InheritedWidget {
  const SongSelectionScope({
    super.key,
    required this.controller,
    required this.available,
    required super.child,
  });
  final SongSelectionController controller;
  final Set<Map> available;
  static SongSelectionController? maybeOf(BuildContext context, Map song) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SongSelectionScope>();
    return scope != null && scope.available.contains(song)
        ? scope.controller
        : null;
  }

  @override
  bool updateShouldNotify(SongSelectionScope oldWidget) => true;
}

class SongSelectionRegion extends StatefulWidget {
  const SongSelectionRegion({
    super.key,
    required this.songs,
    required this.child,
    this.onRemove,
    this.filter = '',
  });
  final List<dynamic> songs;
  final String filter;
  final Widget child;
  final Future<void> Function(List<Map>)? onRemove;
  @override
  State<SongSelectionRegion> createState() => _SongSelectionRegionState();
}

class _SongSelectionRegionState extends State<SongSelectionRegion> {
  final _selection = SongSelectionController();
  @override
  void initState() {
    super.initState();
    _selection.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SongSelectionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filter != oldWidget.filter) {
      _selection.active = false;
      _selection.selected.clear();
    }
    final visible = Set<Map>.identity()..addAll(widget.songs.whereType<Map>());
    _selection.selected.removeWhere((s) => !visible.contains(s));
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    _selection.dispose();
    super.dispose();
  }

  List<Map> get _ordered => widget.songs
      .whereType<Map>()
      .where(_selection.selected.contains)
      .toList();
  Future<void> _queue() async {
    if (_selection.busy) return;
    setState(() => _selection.busy = true);
    try {
      await audioHandler.addPlaylistToQueue(_ordered);
    } finally {
      if (mounted) {
        setState(() => _selection.busy = false);
        _selection.clear();
      }
    }
  }

  Future<void> _remove() async {
    final songs = _ordered;
    final l = context.l10n!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.removeSelectedQuestion(songs.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.removeFromPlaylist),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _selection.busy = true);
    try {
      await widget.onRemove!(songs);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _selection.busy = false);
        _selection.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n!;
    final enabled = !_selection.busy && _selection.selected.isNotEmpty;
    return PopScope(
      canPop: !_selection.active && !_selection.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selection.clear();
      },
      child: SongSelectionScope(
        controller: _selection,
        available: Set<Map>.identity()..addAll(widget.songs.whereType<Map>()),
        child: Column(
          children: [
            if (widget.songs.isNotEmpty)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        if (!_selection.active)
                          TextButton.icon(
                            onPressed: _selection.enter,
                            icon: const Icon(Icons.checklist),
                            label: Text(l.selectSongs),
                          )
                        else ...[
                          IconButton(
                            onPressed: _selection.busy
                                ? null
                                : _selection.clear,
                            icon: const Icon(Icons.close),
                            tooltip: l.clearSelection,
                          ),
                          Text(l.selectedSongs(_selection.selected.length)),
                          IconButton(
                            onPressed: _selection.busy
                                ? null
                                : () {
                                    _selection.selectAll(
                                      widget.songs.whereType<Map>(),
                                    );
                                  },
                            icon: const Icon(Icons.select_all),
                            tooltip: l.selectAllVisible,
                          ),
                          IconButton(
                            onPressed: enabled
                                ? () => showAddToPlaylistDialog(
                                    context,
                                    songs: _ordered,
                                  )
                                : null,
                            icon: const Icon(Icons.playlist_add),
                            tooltip: l.addToPlaylist,
                          ),
                          IconButton(
                            onPressed: enabled ? _queue : null,
                            icon: const Icon(Icons.queue_music),
                            tooltip: l.addToQueue,
                          ),
                          if (widget.onRemove != null)
                            IconButton(
                              onPressed: enabled ? _remove : null,
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l.removeFromPlaylist,
                            ),
                          if (_selection.busy)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
