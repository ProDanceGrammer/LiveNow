import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart' show MetricKind;
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/saved_view_service.dart';
import 'package:livenow/domain/saved_views.dart';
import 'package:livenow/domain/template_filters.dart';
import 'package:livenow/ui/data_imports.dart' show importTemplatesCsv;
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/actions_section.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/action_import_summary_dialog.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

import 'import_harness.dart';

const _csv = '''
Name,Datetime,Next actions and time,Previous actions and time,Growth Direction
😴 Сон,03/10/2026 23:00 → 04/10/2026 8:00,,,Невідомий
💧 Вода,03/10/2026,,,
''';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> pump(
    WidgetTester tester, {
    String? csv,
    Future<void> Function(AppDatabase db)? seed,
    Size size = const Size(1400, 900),
  }) async {
    // Wide window: below 900 px the app switches to the phone layout, which
    // hides the Import CSV button (Settings has it there).
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Seed BEFORE mounting: writing while drift streams are live deadlocks.
    if (seed != null) await tester.runAsync(() => seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionsCsvPickerProvider.overrideWithValue(() async => csv),
        ],
        child: MaterialApp(
          home: ImportHarness(
            // The Import CSV button lives in Settings now.
            actions: {'import-templates-csv': importTemplatesCsv},
            child: const TemplatesScreen(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> settleAndUnmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Import CSV button creates templates and shows the summary', (
    tester,
  ) async {
    await pump(tester, csv: _csv);
    await tester.tap(find.byKey(const ValueKey('import-templates-csv')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TemplateImportSummaryDialog), findsOneWidget);
    expect(find.text('2 templates created'), findsOneWidget);
    expect(find.text('Невідомий'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('9 h'), findsOneWidget); // tile shows the duration
    await settleAndUnmount(tester);
  });

  testWidgets('the sort panel reorders templates by manual time', (
    tester,
  ) async {
    await pump(
      tester,
      seed: (db) async {
        for (final (n, m) in [('Alpha', 90), ('Beta', 15), ('Gamma', 45)]) {
          await db
              .into(db.actionTemplatesTable)
              .insert(
                ActionTemplatesTableCompanion.insert(
                  id: newId(),
                  name: n,
                  payload: jsonEncode({'name': n, 'estimatedMinutes': m}),
                ),
              );
        }
      },
    );
    double top(String t) => tester.getTopLeft(find.text(t)).dy;
    // Default order = name A-Z.
    expect(top('Alpha') < top('Beta') && top('Beta') < top('Gamma'), isTrue);

    await tester.tap(find.byKey(const ValueKey('templates-options-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tpl-sort-chip-name')));
    await tester.pump(); // Name descending
    expect(top('Gamma') < top('Beta') && top('Beta') < top('Alpha'), isTrue);

    await tester.tap(find.byKey(const ValueKey('tpl-sort-chip-name')));
    await tester.pump(); // back to ascending, then manual time first
    await tester.tap(find.byKey(const ValueKey('tpl-sort-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Manual time').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Name is still the FIRST level, so the order is unchanged; drop it.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tpl-sort-chip-name')),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.cancel ||
                w.icon == Icons.clear ||
                w.icon == Icons.close),
      ),
    ));
    await tester.pump();
    expect(top('Beta') < top('Gamma') && top('Gamma') < top('Alpha'), isTrue);
    await settleAndUnmount(tester);
  });

  testWidgets('template editor saves the Duration field', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('New template'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField).first, 'Walk');
    await tester.enterText(
      find.byKey(const ValueKey('template-duration')),
      '45',
    );
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).get(),
    ))!;
    expect(jsonDecode(saved.single.payload)['estimatedMinutes'], 45);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('45 min'), findsOneWidget);
    await settleAndUnmount(tester);
  });

  testWidgets('Start now shows a toast whose name opens the created action', (
    tester,
  ) async {
    await pump(tester, csv: _csv);
    await tester.tap(find.byKey(const ValueKey('import-templates-csv')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Start now').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final toast = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('Started "'),
    );
    expect(toast, findsOneWidget);
    final plain = (tester.widget(toast) as RichText).text.toPlainText();
    final name = plain.substring(9, plain.length - 1);
    expect(
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!
          .where((a) => a.name == name),
      hasLength(1),
    );

    // Tap the name span (inside the toast's text) -> editor opens.
    final paragraph = tester.renderObject<RenderParagraph>(toast);
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 9, extentOffset: 9 + name.length),
        )
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    await settleAndUnmount(tester);
  });

  Future<void> seedTemplate(
    WidgetTester tester,
    String name, {
    Map<String, dynamic> extra = const {},
  }) async {
    await tester.runAsync(
      () => db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: newId(),
              name: name,
              payload: jsonEncode({'name': name, ...extra}),
            ),
          ),
    );
  }

  Future<void> refresh(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('templates are ordered by name ignoring leading emoji', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(tester, '🙂 Banana');
    await seedTemplate(tester, 'cherry');
    await seedTemplate(tester, '↗️ Apple');
    await refresh(tester);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['↗️ Apple', '🙂 Banana', 'cherry']);
    await settleAndUnmount(tester);
  });

  testWidgets('search filters by name; No matches vs No templates yet.', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No templates yet.'), findsOneWidget);
    await seedTemplate(tester, 'Заняття СПОРТОМ');
    await seedTemplate(tester, 'Walk');
    await refresh(tester);
    // The search is hidden behind its icon, like the Current board's.
    expect(find.byKey(const ValueKey('templates-search')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('templates-search-toggle')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('templates-search')),
      'спортом',
    );
    await tester.pump();
    expect(find.text('Заняття СПОРТОМ'), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('templates-search')),
      'zzz',
    );
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('No templates yet.'), findsNothing);
    // The X clears the filter and closes the search.
    await tester.tap(find.byKey(const ValueKey('templates-search-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('templates-search')), findsNothing);
    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Заняття СПОРТОМ'), findsOneWidget);
    await settleAndUnmount(tester);
  });

  testWidgets('Duplicate in the editor copies the template and opens the copy', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(tester, 'Walk', extra: {'isAllDay': true});
    await refresh(tester);
    await tester.tap(find.text('Walk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('template-duplicate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-duplicate')));
    await refresh(tester);
    await tester.pumpAndSettle();

    final rows = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).get(),
    ))!;
    expect(rows.map((r) => r.name).toSet(), {'Walk', 'Walk (copy)'});
    final copy = rows.firstWhere((r) => r.name == 'Walk (copy)');
    final payload = jsonDecode(copy.payload) as Map<String, dynamic>;
    expect(payload['name'], 'Walk (copy)');
    expect(payload['isAllDay'], isTrue);
    // The copy's editor is open now (its name in the field).
    expect(
      find.byWidgetPredicate((w) => w is EditableText && w.controller.text == 'Walk (copy)'),
      findsOneWidget,
    );
    await settleAndUnmount(tester);
  });

  testWidgets('Delete asks first: Cancel keeps it, Delete removes it', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(tester, 'Walk');
    await refresh(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete template?'), findsOneWidget);
    expect(
      find.text('"Walk" will be deleted and cannot be restored.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      (await tester.runAsync(() => db.select(db.actionTemplatesTable).get()))!,
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('confirm-delete-template')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      (await tester.runAsync(() => db.select(db.actionTemplatesTable).get()))!,
      isEmpty,
    );
    await settleAndUnmount(tester);
  });

  testWidgets(
    'All day is compact and gaps separate Name / All day / Duration',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('New template'));
      await tester.pump(const Duration(milliseconds: 400));
      final name = tester.getRect(find.byType(TextFormField).first);
      final duration = tester.getRect(
        find.byKey(const ValueKey('template-duration')),
      );
      final sw = tester.getRect(find.byKey(const ValueKey('template-all-day')));
      expect(sw.top - name.bottom, greaterThanOrEqualTo(12));
      expect(duration.top - sw.bottom, greaterThanOrEqualTo(12));
      await settleAndUnmount(tester);
    },
  );

  testWidgets('template notes are saved, shown again and copied by Start now', (
    tester,
  ) async {
    const notes =
        '{"document":{"type":"page","children":[{"type":"paragraph","data":'
        '{"delta":[{"insert":"Buy Milk"}]}}]}}';
    await pump(tester);
    await seedTemplate(tester, 'Shop', extra: {'notes': notes});
    await refresh(tester);

    // Opening the editor expands Notes (it has text); saving keeps them.
    await tester.tap(find.text('Shop'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NotesEditor), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).getSingle(),
    ))!;
    expect(jsonDecode(saved.payload)['notes'], isNotNull);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Start now'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    final action = (await tester.runAsync(
      () => db.select(db.actionsTable).getSingle(),
    ))!;
    expect(action.notes, isNotNull);
    expect(action.notesText, contains('buy milk'));
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('the template editor has an Expand button: full screen, only the '
      'notes, Save inside the notes toolbar, Collapse brings it all back', (
    tester,
  ) async {
    const notes =
        '{"document":{"type":"page","children":[{"type":"paragraph","data":'
        '{"delta":[{"insert":"Buy Milk"}]}}]}}';
    await pump(tester);
    await seedTemplate(tester, 'Shop', extra: {'notes': notes});
    await refresh(tester);
    await tester.tap(find.text('Shop'));
    await tester.pump(const Duration(milliseconds: 400));

    NotesEditor editor() => tester.widget<NotesEditor>(find.byType(NotesEditor));
    expect(editor().onToggleExpand, isNotNull);
    expect(find.text('Edit template'), findsOneWidget);
    expect(find.byKey(const ValueKey('template-duration')), findsOneWidget);
    final stateBefore = tester.state(find.byType(NotesEditor));

    editor().onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor().expanded, isTrue);
    expect(find.text('Edit template'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const ValueKey('template-duration')), findsNothing);
    expect(find.byKey(const ValueKey('notes-save')), findsOneWidget);
    final box = tester.getSize(find.byType(NotesEditor));
    expect(box.height, greaterThan(tester.view.physicalSize.height * 0.6));
    expect(tester.state(find.byType(NotesEditor)), same(stateBefore));

    editor().onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor().expanded, isFalse);
    expect(find.text('Edit template'), findsOneWidget);
    expect(find.byKey(const ValueKey('template-duration')), findsOneWidget);

    // Expanded again: the editor's own Save writes the template and closes.
    editor().onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('notes-save')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NotesEditor), findsNothing);
    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).getSingle(),
    ))!;
    expect(jsonDecode(saved.payload)['notes'], isNotNull);
    await settleAndUnmount(tester);
  });

  Future<List<ActionRow>> allActions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!;

  Future<void> tapAndWait(WidgetTester tester, Finder f) async {
    await tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('Finish now creates a done action; toast says Finished "..." '
      'and Undo deletes it', (tester) async {
    await pump(tester);
    await seedTemplate(tester, 'Walk', extra: {'estimatedMinutes': 30});
    await refresh(tester);
    expect(find.text('Use'), findsNothing);
    expect(find.byTooltip('Start now'), findsOneWidget);

    await tapAndWait(tester, find.byTooltip('Finish now'));
    final toast = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('Finished "'),
    );
    expect(toast, findsOneWidget);
    final plain = (tester.widget(toast) as RichText).text.toPlainText();
    expect(plain.substring(10, plain.length - 1), 'Walk');
    final created = await allActions(tester);
    expect(created, hasLength(1));
    expect(created.single.done, isTrue);
    final occ = (await tester.runAsync(
      () => db.select(db.actionOccurrencesTable).get(),
    ))!;
    expect(occ.single.outcome, 'done');

    await tapAndWait(tester, find.text('Undo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(await allActions(tester), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('Start now on an all-day template makes an undone all-day '
      'action; Finish now a done one', (tester) async {
    await pump(tester);
    await seedTemplate(tester, 'Water', extra: {'isAllDay': true});
    await refresh(tester);

    await tapAndWait(tester, find.byTooltip('Start now'));
    var rows = await allActions(tester);
    expect(rows.single.isAllDay, isTrue);
    expect(rows.single.done, isFalse);
    expect(rows.single.endAt, isNull);

    await tapAndWait(tester, find.byTooltip('Finish now'));
    rows = await allActions(tester);
    expect(rows, hasLength(2));
    expect(rows.where((r) => r.done), hasLength(1));
    expect(rows.every((r) => r.isAllDay), isTrue);
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('a started template with a deleted direction still starts', (
    tester,
  ) async {
    await pump(tester);
    await seedTemplate(
      tester,
      'Walk',
      extra: {
        'metricIds': ['gone'],
      },
    );
    await refresh(tester);
    await tapAndWait(tester, find.byTooltip('Start now'));
    expect(await allActions(tester), hasLength(1));
    await tester.pump(const Duration(seconds: 6));
    await settleAndUnmount(tester);
  });

  testWidgets('a template without notes has no notes in its payload', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('New template'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField).first, 'Plain');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final saved = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).getSingle(),
    ))!;
    expect(jsonDecode(saved.payload).containsKey('notes'), isFalse);
    await settleAndUnmount(tester);
  });

  testWidgets('a direction chip in the template editor opens the direction', (
    tester,
  ) async {
    await pump(
      tester,
      seed: (db) async {
        final id = await MetricService(
          db,
        ).saveMetric(name: 'Reading', kind: MetricKind.boolean);
        await db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: newId(),
                name: 'Walk',
                payload: jsonEncode({
                  'name': 'Walk',
                  'metricIds': [id],
                }),
              ),
            );
      },
    );
    await refresh(tester);
    await tester.tap(find.text('Walk'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Open this direction'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GrowthDirectionDialog), findsOneWidget);
    await settleAndUnmount(tester);
  });

  testWidgets('a direction chip in the template editor shows its urgency', (
    tester,
  ) async {
    await pump(
      tester,
      seed: (db) async {
        final id = await MetricService(
          db,
        ).saveMetric(name: 'Reading', kind: MetricKind.boolean);
        await db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: newId(),
                name: 'Walk',
                payload: jsonEncode({
                  'name': 'Walk',
                  'metricIds': [id],
                }),
              ),
            );
      },
    );
    await refresh(tester);
    await tester.tap(find.text('Walk'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byTooltip('Urgency to Keep in Balance'), findsWidgets);
    await settleAndUnmount(tester);
  });

  // ---- filters ---------------------------------------------------------------

  /// Walk (dir A, avg 30), Jog (A + B, avg 60), Read (B, never run), Nap (none).
  late String dirA, dirB;
  Future<void> seedFilterData(AppDatabase db) async {
    final svc = MetricService(db);
    dirA = await svc.saveMetric(name: 'Alpha', kind: MetricKind.boolean);
    dirB = await svc.saveMetric(name: 'Beta', kind: MetricKind.boolean);
    Future<void> tpl(String n, List<String> ids) => db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: newId(),
            name: n,
            payload: jsonEncode({'name': n, 'metricIds': ids}),
          ),
        );
    await tpl('Walk', [dirA]);
    await tpl('Jog', [dirA, dirB]);
    await tpl('Read', [dirB]);
    await tpl('Nap', []);
    Future<void> run(String n, int minutes) async {
      final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final start = end.subtract(Duration(minutes: minutes));
      await db
          .into(db.actionsTable)
          .insert(
            ActionsTableCompanion.insert(
              id: newId(),
              name: n,
              createdAt: dateTimeToDb(start)!,
              updatedAt: dateTimeToDb(DateTime.now().toUtc())!,
              done: const Value(true),
              startAt: Value(dateTimeToDb(start)),
              endAt: Value(dateTimeToDb(end)),
              completedAt: Value(dateTimeToDb(end)),
            ),
          );
    }

    await run('Walk', 30);
    await run('Jog', 60);
  }

  Finder row(String n) => find.text(n);

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('templates-options-toggle')));
    await tester.pump();
  }

  Future<void> pickDirection(
    WidgetTester tester,
    String pickerKey,
    String name,
  ) async {
    final add = find.descendant(
      of: find.byKey(ValueKey(pickerKey)),
      matching: find.byTooltip('Add…'),
    );
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(name).last);
    await tester.pump();
    await tester.tap(find.textContaining('Done ('));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> filtersScenario(WidgetTester tester, Size size) async {
    await pump(tester, size: size, seed: seedFilterData);
    await refresh(tester);
    for (final n in ['Walk', 'Jog', 'Read', 'Nap']) {
      expect(row(n), findsOneWidget);
    }
    await openPanel(tester);

    // Name.
    await tester.enterText(find.byKey(const ValueKey('tpl-filter-name')), 'A');
    await tester.pump();
    expect(row('Walk'), findsOneWidget);
    expect(row('Read'), findsOneWidget);
    expect(row('Nap'), findsOneWidget);
    expect(row('Jog'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tpl-filter-reset')));
    await tester.pump();
    expect(row('Jog'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpl-filter-reset')), findsNothing);

    // Average: a bound hides the never-run templates.
    await tester.enterText(
      find.byKey(const ValueKey('tpl-filter-min-avg')),
      '40',
    );
    await tester.pump();
    expect(row('Jog'), findsOneWidget);
    expect(row('Walk'), findsNothing);
    expect(row('Read'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('tpl-filter-min-avg')), '');
    await tester.enterText(
      find.byKey(const ValueKey('tpl-filter-max-avg')),
      '30',
    );
    await tester.pump();
    expect(row('Walk'), findsOneWidget);
    expect(row('Jog'), findsNothing);
    expect(row('Nap'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tpl-filter-reset')));
    await tester.pump();

    // Include (Any, then All) and exclude.
    await pickDirection(tester, 'tpl-filter-include', 'Alpha');
    expect(row('Walk'), findsOneWidget);
    expect(row('Jog'), findsOneWidget);
    expect(row('Read'), findsNothing);
    await pickDirection(tester, 'tpl-filter-include', 'Beta');
    expect(row('Read'), findsOneWidget); // Any of Alpha / Beta
    expect(row('Nap'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(row('Jog'), findsOneWidget);
    expect(row('Walk'), findsNothing);
    expect(row('Read'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tpl-filter-reset')));
    await tester.pump();
    await pickDirection(tester, 'tpl-filter-exclude', 'Beta');
    expect(row('Walk'), findsOneWidget);
    expect(row('Nap'), findsOneWidget);
    expect(row('Jog'), findsNothing);
    expect(row('Read'), findsNothing);

    // Everything hidden: "No matches", then Reset brings all back.
    await tester.enterText(find.byKey(const ValueKey('tpl-filter-name')), 'zzz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpl-filter-reset')));
    await tester.pump();
    for (final n in ['Walk', 'Jog', 'Read', 'Nap']) {
      expect(row(n), findsOneWidget);
    }
    await settleAndUnmount(tester);
  }

  testWidgets('template filters work on desktop', (tester) async {
    await filtersScenario(tester, const Size(1400, 900));
  });

  testWidgets('template filters work on a phone-sized window', (tester) async {
    await filtersScenario(tester, const Size(800, 1400));
  });

  testWidgets('the default saved view applies the filters on open; Clear '
      'drops them', (tester) async {
    await pump(
      tester,
      seed: (db) async {
        await seedFilterData(db);
        final id = await SavedViewService(db).save(
          screen: ViewScreens.actionsTemplates,
          name: 'Only A',
          kind: SavedViewKind.both,
          filter: templateFilterToJson(
            TemplateFilters(nameText: 'o', includeIds: {dirA}),
          ),
        );
        await SavedViewService(db).setDefault(id);
      },
    );
    await refresh(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(row('Jog'), findsOneWidget);
    expect(row('Walk'), findsNothing); // "o" is not in Walk
    expect(row('Nap'), findsNothing);
    expect(find.byKey(const ValueKey('templates-filters-badge')), findsOneWidget);

    await openPanel(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tpl-filter-name')))
          .controller!
          .text,
      'o',
    );
    await tester.tap(find.byKey(const ValueKey('views-clear')));
    await tester.pump();
    for (final n in ['Walk', 'Jog', 'Read', 'Nap']) {
      expect(row(n), findsOneWidget);
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tpl-filter-name')))
          .controller!
          .text,
      '',
    );
    await settleAndUnmount(tester);
  });
}
