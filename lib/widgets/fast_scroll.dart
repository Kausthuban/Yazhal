import 'package:material_ui/material_ui.dart';

/// Owns the same controller used by the scrollable and its draggable thumb.
class FastScroll extends StatefulWidget {
  const FastScroll({required this.builder, super.key});
  final Widget Function(ScrollController controller) builder;
  @override
  State<FastScroll> createState() => _FastScrollState();
}

class _FastScrollState extends State<FastScroll> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    interactive: true,
    thumbVisibility: true,
    trackVisibility: true,
    thickness: 8,
    radius: const Radius.circular(8),
    child: widget.builder(controller),
  );
}
