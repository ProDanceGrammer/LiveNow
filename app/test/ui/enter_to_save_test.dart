import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';

/// Pressing Enter in the Name field of a "new item" dialog is the same as
/// pressing its Save button.
void main() {
  late AppDatabase db;

  // The growth dialog watches live stats, whose windows need the timezone
  // database (the app initialises it at startup).
  setUpAll(initPostponeTimeZoneData);

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: home),
      ),
    );
  }

  /// A page with one button that opens [dialog] on top.
  Widget opener(Future<void> Function(BuildContext) dialog) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => dialog(context),
        child: const Text('open'),
      ),
    ),
  );

  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Types [name] into the dialog's first field and presses Enter, then waits
  /// for the database write.
  Future<void> typeAndEnter(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets any stream a dialog watched deliver before the tree is torn down.
  Future<void> settleAndUnmount(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('New action: Enter saves it and closes the dialog', (
    tester,
  ) async {
    await pumpApp(tester, opener((c) => ActionEditorDialog.show(c)));
    await tester.tap(find.text('open'));
    await animate(tester);

    await typeAndEnter(tester, 'Read a Bible');

    final saved = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(saved.map((a) => a.name), ['Read a Bible']);
    expect(find.byType(AlertDialog), findsNothing);
    await settleAndUnmount(tester);
  });

  testWidgets(
    'New action: Enter on an empty name asks for one, saves nothing',
    (tester) async {
      await pumpApp(tester, opener((c) => ActionEditorDialog.show(c)));
      await tester.tap(find.text('open'));
      await animate(tester);

      await typeAndEnter(tester, '   ');

      expect(find.text('Required'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.actionsTable).get()))!,
        isEmpty,
      );
      await settleAndUnmount(tester);
    },
  );

  testWidgets('New growth direction: Enter saves it', (tester) async {
    await pumpApp(tester, opener((c) => GrowthDirectionDialog.show(c)));
    await tester.tap(find.text('open'));
    await animate(tester);

    await typeAndEnter(tester, 'I read daily');

    final saved = (await tester.runAsync(
      () => db.select(db.metricsTable).get(),
    ))!;
    expect(saved.map((m) => m.name), ['I read daily']);
    expect(find.byType(AlertDialog), findsNothing);
    await settleAndUnmount(tester);
  });

  testWidgets('New template: Enter saves it', (tester) async {
    await pumpApp(tester, const TemplatesScreen());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('New template'));
    await animate(tester);
    await typeAndEnter(tester, 'Morning routine');

    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).get(),
    ))!;
    expect(saved.map((t) => t.name), ['Morning routine']);
    expect(find.byType(AlertDialog), findsNothing);
    await settleAndUnmount(tester);
  });
}
