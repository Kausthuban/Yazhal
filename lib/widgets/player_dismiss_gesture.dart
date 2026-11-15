import 'package:material_ui/material_ui.dart';

class PlayerDismissGesture extends StatefulWidget {
  const PlayerDismissGesture({required this.child, super.key});
  final Widget child;
  @override
  State<PlayerDismissGesture> createState() => _PlayerDismissGestureState();
}

class _PlayerDismissGestureState extends State<PlayerDismissGesture> {
  double distance = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onVerticalDragStart: (_) => distance = 0,
    onVerticalDragUpdate: (details) => distance += details.delta.dy,
    onVerticalDragEnd: (details) {
      if (distance > 100 || (details.primaryVelocity ?? 0) > 700)
        Navigator.of(context).maybePop();
      distance = 0;
    },
    child: widget.child,
  );
}
