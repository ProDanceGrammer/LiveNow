// The whole screen-recording demo in one window: Windows layout first, then the
// phone layout (375x812, then sideways). Start it with claude_dev/run_demo.ps1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'demo_desktop.dart';
import 'demo_phone.dart';
import 'demo_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LiveNow demo - Windows, then phone', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

    // ---- Windows
    await sizeWindow(tester, 40, 20, 1400, 860);
    var demo = await startDemo(tester, touch: false);
    await countdown(demo, seconds: 6);
    await demo.scene('LiveNow on Windows', 2500);
    await desktopDemo(tester, demo);
    final skippedDesktop = [...demo.skipped];

    // ---- the same app on a phone
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    await sizeWindow(tester, 300, 10, 375, 812);
    demo = await startDemo(tester, touch: true);
    await demo.scene('Now the same app in a phone-sized window', 2500);
    await phoneDemo(
      tester,
      demo,
      landscape: () => sizeWindow(tester, 150, 120, 812, 375),
      portrait: () => sizeWindow(tester, 300, 10, 375, 812),
    );
    demo.skipped.insertAll(0, skippedDesktop);
    demo.report();
  });
}
