import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/dialog_stack.dart';

void main() {
  late BuildContext ctx;

  setUp(resetStackedDialogsForTest);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: Text('base'));
          },
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester,
    String label, {
    VoidCallback? onTap,
  }) async {
    showStackedDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        content: TextButton(onPressed: onTap ?? () {}, child: Text(label)),
      ),
    );
    await tester.pumpAndSettle();
  }

  int dimmingBarriers(WidgetTester tester) => tester
      .widgetList<ModalBarrier>(find.byType(ModalBarrier))
      .where((b) => b.color != null && b.color!.a > 0)
      .length;

  testWidgets('1, 2 and 3 stacked dialogs dim exactly once', (tester) async {
    await pumpHost(tester);
    await open(tester, 'A');
    expect(dimmingBarriers(tester), 1);
    await open(tester, 'B');
    expect(dimmingBarriers(tester), 1);
    await open(tester, 'C');
    expect(dimmingBarriers(tester), 1);
    expect(find.byType(AlertDialog), findsNWidgets(3));
  });

  testWidgets('closing the top dialog keeps the lower one and its dim', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester, 'A');
    await open(tester, 'B');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(dimmingBarriers(tester), 1);
    expect(openStackedDialogCount, 1);
  });

  testWidgets('closing all resets depth so a new dialog dims again', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester, 'A');
    await open(tester, 'B');
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(openStackedDialogCount, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await open(tester, 'C');
    expect(dimmingBarriers(tester), 1);
  });

  testWidgets('transparent upper barrier still blocks taps below', (
    tester,
  ) async {
    var tapped = false;
    await pumpHost(tester);
    showStackedDialog<void>(
      context: ctx,
      builder: (_) => Dialog.fullscreen(
        child: Align(
          alignment: Alignment.topLeft,
          child: TextButton(
            onPressed: () => tapped = true,
            child: const Text('lower'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester, 'B');
    expect(dimmingBarriers(tester), 1);
    // The button sits outside B's small dialog, under B's transparent barrier.
    await tester.tapAt(tester.getCenter(find.text('lower')));
    await tester.pumpAndSettle();
    expect(tapped, isFalse);
    // The tap dismissed only the top dialog.
    expect(find.text('B'), findsNothing);
    expect(find.text('lower'), findsOneWidget);
  });
}
