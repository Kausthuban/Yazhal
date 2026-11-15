import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/provider_artwork_service.dart';
import 'package:yazhal/widgets/no_artwork_cube.dart';

class ProviderArtwork extends StatefulWidget {
  const ProviderArtwork({
    required this.token,
    required this.size,
    this.radius = 10,
    super.key,
  });
  final String token;
  final double size, radius;
  @override
  State<ProviderArtwork> createState() => _ProviderArtworkState();
}

class _ProviderArtworkState extends State<ProviderArtwork> {
  late Future<File?> image = ProviderArtworkService.instance.load(widget.token);
  @override
  void didUpdateWidget(ProviderArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token)
      image = ProviderArtworkService.instance.load(widget.token);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: image,
    builder: (context, snapshot) => SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: snapshot.data == null
            ? NullArtworkWidget(iconSize: widget.size / 3, size: widget.size)
            : Image.file(
                snapshot.data!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                cacheWidth: 1024,
                errorBuilder: (_, __, ___) => NullArtworkWidget(
                  iconSize: widget.size / 3,
                  size: widget.size,
                ),
              ),
      ),
    ),
  );
}
