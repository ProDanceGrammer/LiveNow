import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/form_effects.dart';
import 'package:livenow/domain/form_service.dart';
import 'package:livenow/domain/forms.dart';
import 'package:livenow/domain/growth_rules.dart' show MetricKind;
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/all_selection.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/forms_screen.dart';
import 'package:livenow/ui/views/all_actions_view.dart';
import 'package:livenow/ui/widgets/form_fill.dart';

/// The Forms tab, the builder, the fill dialog and the bulk-bar entry point.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  FormDef sample(String name) => FormDef(
    name: name,
    questions: [
      FormQuestion(
        id: 'q1',
        title: 'What did you do?',
        options: [
          FormOption(id: 'o1', label: 'Study', metricIds: const ['m1']),
          FormOption(id: 'o2', label: 'Sport', metricIds: const ['m2']),
        ],
      ),
    ],
  );

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1000, 900),
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Seed BEFORE mounting: writing while drift streams are live deadlocks.
    if (seed != null) await tester.runAsync(() => seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('empty Forms tab shows the hint', (tester) async {
    await mount(tester, const FormsScreen());
    expect(find.byKey(const ValueKey('forms-empty')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('lists forms with their counts, search filters, copy and delete', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async {
        final svc = FormService(db);
        id = await svc.save(sample('Goals'));
        await svc.save(sample('Mood'));
      },
    );
    expect(find.byKey(ValueKey('form-$id')), findsOneWidget);
    expect(find.textContaining('1 question · 2 answers'), findsNWidgets(2));

    await tester.enterText(find.byKey(const ValueKey('forms-search')), 'moo');
    await settle(tester);
    expect(find.byKey(ValueKey('form-$id')), findsNothing);
    expect(find.text('Mood'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('forms-search')), '');
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('form-copy-$id')));
    await settle(tester);
    expect(find.byType(ListTile), findsNWidgets(3));

    await tester.tap(find.byKey(ValueKey('form-delete-$id')));
    await settle(tester);
    expect(find.byKey(ValueKey('form-$id')), findsNothing);
    await tester.pump(const Duration(seconds: 6)); // the Undo toast's timer
    await unmount(tester);
  });

  testWidgets('the builder needs a name, then saves the form it made', (
    tester,
  ) async {
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-builder'),
          onPressed: () => FormsScreen.showNewForm(context),
          child: const Text('new'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-builder')));
    await settle(tester);

    // No name: Save does nothing.
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);
    expect(find.byKey(const ValueKey('form-name')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('form-name')), 'Day');
    await tester.tap(find.byKey(const ValueKey('form-add-question')));
    await tester.pumpAndSettle(); // the menu opens
    await tester.tap(find.text('Checkbox list'));
    await tester.pumpAndSettle(); // and closes
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);

    final saved = await tester.runAsync(() => FormService(db).all());
    expect(saved!.single.name, 'Day');
    // The blank placeholder question is not kept.
    expect(saved.single.def.questions, isEmpty);
    await unmount(tester);
  });

  testWidgets('fill dialog: Submit stays off until something is ticked and '
      'returns the directions of the ticked answers', (tester) async {
    FormEffects? result;
    final form = FormItem(id: 'f', def: sample('Goals'), updatedAt: '');
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-fill'),
          onPressed: () async => result = await FormFillDialog.show(
            context,
            form: form,
            actionCount: 2,
            actionNames: const ['A', 'B'],
          ),
          child: const Text('fill'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-fill')));
    await settle(tester);

    FilledButton submit() =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('form-submit')));
    expect(submit().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('form-option-q1-o2')));
    await settle(tester);
    expect(submit().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(result?.metricIds, ['m2']);
    await unmount(tester);
  });

  testWidgets('the All bulk bar offers Form and applies it to the selection', (
    tester,
  ) async {
    late String actionId;
    late String metricId;
    await mount(
      tester,
      const AllActionsView(),
      seed: (db) async {
        actionId = await ActionService(db).createAction(
          name: 'Read',
          startAt: DateTime.utc(2030, 1, 10, 9),
          endAt: DateTime.utc(2030, 1, 10, 10),
        );
        metricId = await MetricService(
          db,
        ).saveMetric(name: 'Learn', kind: MetricKind.boolean);
        await FormService(db).save(
          FormDef(
            name: 'Only',
            questions: [
              FormQuestion(
                id: 'q',
                title: 'Q',
                options: [
                  FormOption(id: 'o', label: 'Learn', metricIds: [metricId]),
                ],
              ),
            ],
          ),
        );
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AllActionsView)),
    );
    await tester.tap(find.byKey(ValueKey('all-check-$actionId')));
    await tester.pump();
    expect(container.read(allSelectionProvider), {actionId});

    // One form only: no picker, the fill dialog opens at once.
    await tester.tap(find.byKey(const ValueKey('bulk-form')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-option-q-o')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester, 500);

    final links = await tester.runAsync(
      () => db.select(db.actionMetricsTable).get(),
    );
    expect(links!.map((l) => (l.actionId, l.metricId)), [(actionId, metricId)]);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('the builder makes a combination rule and saves it', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(sample('Goals')),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-add-combo')));
    await settle(tester);
    final picks = find.byWidgetPredicate(
      (w) => w.key.toString().contains('combo-picks-') && w is ActionChip,
    );
    expect(picks, findsOneWidget);
    await tester.ensureVisible(picks);
    await tester.pump();
    await tester.tap(picks);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('combo-pick-q1-o1')));
    await tester.tap(find.byKey(const ValueKey('combo-pick-q1-o2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('combo-picks-ok')));
    await settle(tester);
    expect(find.textContaining('What did you do? · Study'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);
    final saved = await tester.runAsync(() => FormService(db).get(id));
    expect(saved!.def.combos.single.picks, [
      const FormPick('q1', 'o1'),
      const FormPick('q1', 'o2'),
    ]);
    await unmount(tester);
  });

  testWidgets('the Adds section is RIGHT of the answer text on a wide window and '
      'there is no "None"', (tester) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(sample('Goals')),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);

    final label = tester.getRect(find.byKey(const ValueKey('form-opt-label-o1')));
    final adds = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('form-opt-o1')),
        matching: find.text('Adds:'),
      ),
    );
    expect(adds.left, greaterThanOrEqualTo(label.right));
    expect((adds.center.dy - label.center.dy).abs(), lessThan(24));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('form-builder-scroll')),
        matching: find.text('None'),
      ),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('on a phone the Adds section stays UNDER the answer text', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      size: const Size(375, 812),
      seed: (db) async => id = await FormService(db).save(sample('Goals')),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    final label = tester.getRect(find.byKey(const ValueKey('form-opt-label-o1')));
    final adds = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('form-opt-o1')),
        matching: find.text('Adds:'),
      ),
    );
    expect(adds.top, greaterThanOrEqualTo(label.bottom));
    await unmount(tester);
  });

  testWidgets('the Forms list shows the description on its own, larger line', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(
        sample('Goals').copyWith(description: 'Which goals a task serves'),
      ),
    );
    final desc = tester.widget<Text>(find.byKey(ValueKey('form-desc-$id')));
    expect(desc.data, 'Which goals a task serves');
    expect(desc.style?.fontSize, greaterThanOrEqualTo(15));
    final title = tester.widget<Text>(find.text('Goals'));
    expect(title.style?.fontSize, greaterThanOrEqualTo(19));
    // The counts stay on a line of their own.
    expect(find.text('1 question · 2 answers'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a combination chip shows the QUESTION emoji as well as the answer one', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(
        FormDef(
          name: 'Icons',
          questions: [
            FormQuestion(
              id: 'q1',
              title: 'Asked about',
              icon: '📚',
              options: [
                FormOption(id: 'o1', label: 'Money', icon: '💵'),
                FormOption(id: 'o2', label: 'Health'),
              ],
            ),
          ],
          combos: const [
            FormCombo(
              id: 'c',
              picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    final chip = find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains('Asked about · 💵 Money'),
    );
    await tester.ensureVisible(chip);
    expect(find.textContaining('📚 Asked about · 💵 Money'), findsOneWidget);
    expect(find.textContaining('📚 Asked about · Health'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the hover text of a builder button is large (15 px), not shrunk with the rest', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(sample('Goals')),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('form-q-dup-q1'))));
    await tester.pump(const Duration(milliseconds: 600));
    final tip = find.text('Duplicate the question');
    expect(tip, findsOneWidget);
    final p = tester.renderObject<RenderParagraph>(tip);
    final px = p.textScaler.scale(p.text.style!.fontSize!);
    expect(px, closeTo(15, 0.6));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 600));
    await unmount(tester);
  });

  testWidgets('"New question below" sits left of "Add option", inserts right below '
      'and focuses the new title', (tester) async {
    late String id;
    FormQuestion q(String qid, String title) => FormQuestion(
      id: qid,
      title: title,
      options: [FormOption(id: '$qid-o', label: 'ans $title')],
    );
    await mount(
      tester,
      const FormsScreen(),
      size: const Size(1000, 1100),
      seed: (db) async => id = await FormService(db).save(
        FormDef(name: 'Below', questions: [q('qa', 'A'), q('qb', 'B')]),
      ),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);

    final below = tester.getRect(find.byKey(const ValueKey('form-q-below-qa')));
    final add = tester.getRect(find.byKey(const ValueKey('form-add-option-qa')));
    expect(below.right, lessThanOrEqualTo(add.left));
    expect((below.center.dy - add.center.dy).abs(), lessThan(6));

    await tester.tap(find.byKey(const ValueKey('form-q-below-qa')));
    await settle(tester);
    final newTitle = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('form-q-title-') &&
          !const {'form-q-title-qa', 'form-q-title-qb'}.contains(
            (w.key as ValueKey<String>).value,
          ),
    );
    expect(newTitle, findsOneWidget);
    // The keyboard focus is in it: typing goes there.
    final editable = find.descendant(of: newTitle, matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(newTitle, 'Middle');
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);

    final saved = (await tester.runAsync(() => FormService(db).get(id)))!;
    expect(saved.def.questions.map((x) => x.title), ['A', 'Middle', 'B']);
    await unmount(tester);
  });

  testWidgets('a combination shows its activity chip; removing it is saved', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(
        sample('Goals').copyWith(
          combos: const [
            FormCombo(
              id: 'c',
              picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
              activityName: 'Night training',
            ),
            FormCombo(
              id: 'd',
              picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    final withActivity = find.byKey(const ValueKey('combo-activity-c'));
    await tester.ensureVisible(withActivity);
    await tester.pump();
    expect(tester.widget<InputChip>(withActivity).label, isA<Text>());
    expect(find.text('Activity: Night training'), findsOneWidget);
    // The other rule offers to add one.
    expect(
      tester.widget(find.byKey(const ValueKey('combo-activity-d'))),
      isA<ActionChip>(),
    );

    tester.widget<InputChip>(withActivity).onDeleted!();
    await settle(tester);
    expect(find.text('Activity: Night training'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);
    final saved = (await tester.runAsync(() => FormService(db).get(id)))!;
    expect(saved.def.combos.map((c) => c.activityName), [null, null]);
    await unmount(tester);
  });

  testWidgets('a question can be duplicated: a copy right below, new ids, saved', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(sample('Goals')),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-q-dup-q1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);

    final saved = (await tester.runAsync(() => FormService(db).get(id)))!;
    final qs = saved.def.questions;
    expect(qs, hasLength(2));
    expect(qs[0].id, 'q1');
    expect(qs[1].id, isNot('q1'));
    expect(qs[1].title, qs[0].title);
    expect(qs[1].options.map((o) => o.label), ['Study', 'Sport']);
    expect(
      qs[1].options.map((o) => o.id).toSet().intersection({'o1', 'o2'}),
      isEmpty,
    );
    await unmount(tester);
  });

  testWidgets('a combination can be duplicated too', (tester) async {
    late String id;
    await mount(
      tester,
      const FormsScreen(),
      seed: (db) async => id = await FormService(db).save(
        sample('Goals').copyWith(
          combos: const [
            FormCombo(
              id: 'c',
              picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
              metricIds: ['m-both'],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);
    final dup = find.byKey(const ValueKey('combo-dup-c'));
    await tester.ensureVisible(dup);
    await tester.pump();
    await tester.tap(dup);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);

    final saved = (await tester.runAsync(() => FormService(db).get(id)))!;
    final cs = saved.def.combos;
    expect(cs, hasLength(2));
    expect(cs[0].id, 'c');
    expect(cs[1].id, isNot('c'));
    expect(cs[1].picks, cs[0].picks);
    expect(cs[1].metricIds, ['m-both']);
    await unmount(tester);
  });

  testWidgets('dragging a question by its handle moves it, and the order is saved', (
    tester,
  ) async {
    late String id;
    FormQuestion q(String qid, String title) => FormQuestion(
      id: qid,
      title: title,
      options: [FormOption(id: '$qid-o', label: 'ans $title')],
    );
    await mount(
      tester,
      const FormsScreen(),
      size: const Size(1000, 1100),
      seed: (db) async => id = await FormService(db).save(
        FormDef(name: 'Order', questions: [q('qa', 'A'), q('qb', 'B'), q('qc', 'C')]),
      ),
    );
    await tester.tap(find.byKey(ValueKey('form-$id')));
    await settle(tester);

    Finder handle(String qid) => find.descendant(
      of: find.byKey(ValueKey(qid)),
      matching: find.byIcon(Icons.drag_indicator),
    );
    final start = tester.getCenter(handle('qa'));
    final target = tester.getCenter(handle('qc'));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 50));
    // In small steps, like a hand, past the last card.
    final dy = target.dy - start.dy + 60;
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(start + Offset(0, dy * i / 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-save')));
    await settle(tester);

    final saved = (await tester.runAsync(() => FormService(db).get(id)))!;
    expect(saved.def.questions.map((x) => x.id), ['qb', 'qc', 'qa']);
    await unmount(tester);
  });

  testWidgets('filling a form: a rule adds its directions once all answers are '
      'ticked', (tester) async {
    FormEffects? result;
    final form = FormItem(
      id: 'f',
      def: sample('Goals').copyWith(
        combos: const [
          FormCombo(
            id: 'c',
            picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
            metricIds: ['m-both'],
          ),
        ],
      ),
      updatedAt: '',
    );
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-fill'),
          onPressed: () async => result = await FormFillDialog.show(
            context,
            form: form,
            actionCount: 1,
            actionNames: const ['A'],
          ),
          child: const Text('fill'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-fill')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-option-q1-o1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-option-q1-o2')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-submit')));
    await settle(tester);
    expect(result?.metricIds, ['m1', 'm2', 'm-both']);
    await unmount(tester);
  });

  testWidgets('phone width: list, builder and fill dialog do not overflow', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;

    final form = FormItem(id: 'f', def: sample('Goals'), updatedAt: '');
    await mount(
      tester,
      Column(
        children: [
          const Expanded(child: FormsScreen()),
          Builder(
            builder: (context) => Row(
              children: [
                TextButton(
                  key: const ValueKey('open-builder'),
                  onPressed: () => FormsScreen.showNewForm(context),
                  child: const Text('new'),
                ),
                TextButton(
                  key: const ValueKey('open-fill'),
                  onPressed: () => FormFillDialog.show(
                    context,
                    form: form,
                    actionCount: 3,
                    actionNames: const ['A', 'B', 'C'],
                  ),
                  child: const Text('fill'),
                ),
              ],
            ),
          ),
        ],
      ),
      size: const Size(375, 812),
      seed: (db) async => FormService(db).save(
        sample('Goals').copyWith(
          combos: const [
            FormCombo(
              id: 'c',
              picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
              metricIds: ['m-both'],
            ),
          ],
        ),
      ),
    );
    // The list's row opens the builder with an option row and a rule in it.
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-builder-cancel')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('open-builder')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-builder-cancel')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('open-fill')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('form-cancel')));
    await settle(tester);

    FlutterError.onError = old;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    await unmount(tester);
  });
}
