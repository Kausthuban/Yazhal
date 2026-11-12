/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Yazhal is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Yazhal is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Yazhal, including how to contribute,
 *     please visit: https://github.com/Kausthuban/Yazhal
 */

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/constants/app_constants.dart';
import 'package:yazhal/extensions/l10n.dart';
import 'package:yazhal/main.dart';
import 'package:yazhal/utilities/app_utils.dart';
import 'package:yazhal/widgets/section_header.dart';
import 'package:yazhal/widgets/song_bar.dart';

/// Shared titled list of recommended songs with an optional "play all" button.
class RecommendedSongsSection extends StatelessWidget {
  const RecommendedSongsSection({
    super.key,
    required this.title,
    required this.songs,
    required this.listKeyPrefix,
    this.showPlayButton = true,
    this.onAddSong,
    this.onRefresh,
    this.refreshing = false,
  });

  final VoidCallback? onRefresh;
  final bool refreshing;
  final String title;
  final List<dynamic> songs;

  /// Scope passed to [listItemKey] so each usage keeps stable, distinct keys.
  final String listKeyPrefix;
  final bool showPlayButton;

  /// When set, each row shows an add button instead of the overflow menu.
  final void Function(Map song)? onAddSong;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          title: title,
          icon: FluentIcons.sparkle_24_filled,
          actionButton: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onRefresh,
                tooltip: context.l10n!.refreshRecommendations,
                icon: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              if (showPlayButton && songs.isNotEmpty)
                IconButton(
                  onPressed: () async {
                    await audioHandler.playPlaylistSong(
                      playlist: {'title': title, 'list': songs},
                      songIndex: 0,
                      shuffle: false,
                    );
                  },
                  icon: Icon(
                    FluentIcons.play_circle_24_filled,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: songs.length,
          padding: commonListViewBottomPadding,
          itemBuilder: (context, index) {
            final song = songs[index];
            final borderRadius = getItemBorderRadius(index, songs.length);
            return RepaintBoundary(
              key: listItemKey(listKeyPrefix, index, song),
              child: SongBar(
                song,
                true,
                barPadding: const EdgeInsetsDirectional.only(
                  top: 10,
                  bottom: 10,
                  start: 12,
                ),
                borderRadius: borderRadius,
                onAdd: onAddSong != null && song is Map
                    ? () => onAddSong!(song)
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }
}
