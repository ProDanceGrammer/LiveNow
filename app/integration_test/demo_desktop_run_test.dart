import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'demo_desktop.dart';
import 'demo_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('LiveNow demo - Windows only', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await sizeWindow(tester, 60, 30, 1400, 900);
    final demo = await startDemo(tester, touch: false);
    await countdown(demo, seconds: 2);
    await desktopDemo(tester, demo);
    demo.report();
  });
}
