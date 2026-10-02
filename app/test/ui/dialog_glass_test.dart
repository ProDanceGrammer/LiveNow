import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/widgets/glass_pill_selector.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  test('dialog and menu fills are fully opaque in both themes', () {
    for (final b in Brightness.values) {
      final t = buildAppTheme(b);
      expect(t.dialogTheme.backgroundColor!.a, 1.0);
      expect(t.popupMenuTheme.color!.a, 1.0);
      expect(t.menuTheme.style!.backgroundColor!.resolve({})!.a, 1.0);
    }
  });

  testWidgets('a dialog stacked on another is opaque', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showStackedDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('Below'),
                content: Text('text underneath'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    final below = tester.element(find.text('Below'));
    // Open a second one on top.
    showStackedDialog<void>(
      context: below,
      builder: (_) =>
          const AlertDialog(title: Text('Above'), content: Text('text on top')),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color!.a, 1.0);
    expect(material.shape, isA<GlassDialogBorder>());
  });

  testWidgets('GlassPillSelector selects a pill', (tester) async {
    var value = 'a';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => GlassPillSelector<String>(
              label: 'Type',
              options: const {'a': 'Alpha', 'b': 'Beta'},
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(value, 'b');
  });

  testWidgets('growth dialog: Type and Per are pills, Per hidden for Boolean', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(resetStackedDialogsForTest);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => GrowthDirectionDialog.show(c),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DropdownButtonFormField<MetricKind>), findsNothing);
    expect(find.byType(GlassPillSelector<MetricKind>), findsOneWidget);
    expect(find.byType(GlassPillSelector<MetricWindow>), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pump();
    await tester.tap(find.text('Boolean'));
    await tester.pump();
    expect(find.byType(GlassPillSelector<MetricWindow>), findsNothing);
    await tester.tap(find.text('Hours spent'));
    await tester.pump();
    expect(find.byType(GlassPillSelector<MetricWindow>), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
