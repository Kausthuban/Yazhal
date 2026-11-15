import 'package:material_ui/material_ui.dart';

/// Paint the brand before starting storage, audio service or other plugins.
class StartupGate extends StatefulWidget {
  const StartupGate({required this.initialize, required this.child, super.key});
  final Future<void> Function() initialize;
  final Widget child;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool ready = false;
  Object? failure;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  Future<void> start() async {
    try {
      await widget.initialize();
      if (mounted)
        setState(() {
          ready = true;
          failure = null;
        });
    } catch (error) {
      if (mounted) setState(() => failure = error);
    }
  }

  @override
  Widget build(BuildContext context) => ready
      ? widget.child
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xff17616b)),
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/yazhal_icon.png',
                        width: 112,
                        height: 112,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Yazhal',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (failure == null)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(),
                        )
                      else ...[
                        const Text(
                          'Could not start. Your library is still on this device.',
                        ),
                        TextButton(
                          onPressed: start,
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
}
