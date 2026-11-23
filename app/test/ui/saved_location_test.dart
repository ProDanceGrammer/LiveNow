import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/saved_location.dart';
import 'package:livenow/ui/widgets/app_toast.dart';

void main() {
  Future<OverlayState> mount(WidgetTester tester) async {
    late OverlayState overlay;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            overlay = rootOverlayOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return overlay;
  }

  const path = r'C:\exports\livenow-backup-2026-01-02.livenow';

  testWidgets('desktop: tapping the saved path opens its folder', (
    tester,
  ) async {
    final overlay = await mount(tester);
    final opened = <String>[];
    showSavedToast(
      overlay,
      'Backup saved: ',
      path,
      open: (p) async => opened.add(p),
      linkable: true,
    );
    await tester.pump();
    expect(find.textContaining(path), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring(path));
    expect(opened, [path]);
    dismissActiveToast();
    await tester.pump();
  });

  testWidgets('phone: the path is plain text', (tester) async {
    final overlay = await mount(tester);
    final opened = <String>[];
    showSavedToast(
      overlay,
      'Backup saved: ',
      path,
      open: (p) async => opened.add(p),
      linkable: false,
    );
    await tester.pump();
    await tester.tapOnText(find.textRange.ofSubstring(path));
    expect(opened, isEmpty);
    dismissActiveToast();
    await tester.pump();
  });
}
