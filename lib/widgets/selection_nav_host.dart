import 'package:material_ui/material_ui.dart';

final selectionNavigationBar = ValueNotifier<Widget?>(null);
Object? _owner;
void publishSelectionNavigation(Object owner, Widget? bar) {
  if (bar == null && _owner != owner) return;
  _owner = bar == null ? null : owner;
  selectionNavigationBar.value = bar;
}

class SelectionNavHost extends InheritedWidget {
  const SelectionNavHost({
    required this.enabled,
    required super.child,
    super.key,
  });
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionNavHost>()?.enabled ??
      false;
  @override
  bool updateShouldNotify(SelectionNavHost oldWidget) =>
      enabled != oldWidget.enabled;
}
