import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/urgency_colors.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  DateTime at(int hour, [int minute = 0]) =>
      DateTime.fromMillisecondsSinceEpoch(
        localDayStart(DateTime.now().toUtc()).millisecondsSinceEpoch +
            Duration(hours: hour, minutes: minute).inMilliseconds,
        isUtc: true,
      );

  Future<void> pump(
    WidgetTester tester,
    Map<String, double> urgency, {
    ThemeMode mode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
          actionUrgencyProvider.overrideWith((ref) => Map.of(urgency)),
          // Linked = has an urgency (the real links stream is not awaited).
          actionsWithDirectionsProvider.overrideWith(
            (ref) => ref.watch(actionUrgencyProvider).keys.toSet(),
          ),
        ],
        child: MaterialApp(
          themeMode: mode,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          home: const Scaffold(body: CalendarView()),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
  }

  Future<String> create(
    WidgetTester tester,
    String name,
    DateTime start,
    DateTime end, {
    bool isAllDay = false,
  }) async => (await tester.runAsync(
    () => container
        .read(actionServiceProvider)
        .createAction(
          name: name,
          startAt: start,
          endAt: end,
          isAllDay: isAllDay,
        ),
  ))!;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Color? blockColor(WidgetTester tester, String name) {
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.textContaining(name),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  final urgency = <String, double>{};

  Future<void> setUrgency(WidgetTester tester, Map<String, double> byId) async {
    urgency
      ..clear()
      ..addAll(byId);
    container.invalidate(actionUrgencyProvider);
    await settle(tester);
  }

  Future<void> tomorrow(WidgetTester tester) async {
    await tester.tap(find.byTooltip('2 days'));
    await settle(tester);
  }

  const samples = <String, double>{
    'Neg': -5,
    'Low': 5,
    'Mid': 50,
    'High': 200,
    'Vhigh': 400,
    'Crit': 900,
  };
  const bands = <String, UrgencyBand>{
    'Neg': UrgencyBand.negative,
    'Low': UrgencyBand.low,
    'Mid': UrgencyBand.medium,
    'High': UrgencyBand.high,
    'Vhigh': UrgencyBand.veryHigh,
    'Crit': UrgencyBand.critical,
  };

  for (final dark in [false, true]) {
    testWidgets('timed blocks are coloured by band (dark=$dark)', (
      tester,
    ) async {
      urgency.clear();
      await pump(
        tester,
        urgency,
        mode: dark ? ThemeMode.dark : ThemeMode.light,
      );
      await tomorrow(tester);
      final ids = <String, double>{};
      for (final e in samples.entries) {
        final id = await create(tester, e.key, at(33), at(34));
        ids[id] = e.value;
      }
      await setUrgency(tester, ids);
      for (final e in samples.entries) {
        expect(
          blockColor(tester, e.key),
          urgencyBackground(bands[e.key]!, dark: dark),
          reason: e.key,
        );
      }
      await unmount(tester);
    });
  }

  testWidgets('unlinked is white, running keeps its colour, done is muted', (
    tester,
  ) async {
    urgency.clear();
    await pump(tester, urgency);
    await tomorrow(tester);
    final scheme = Theme.of(tester.element(find.byType(CalendarView)))
        .colorScheme;
    final unlinked = await create(tester, 'Unlinked', at(33), at(34));
    final future = await create(tester, 'Future', at(36), at(37));
    final done = await create(tester, 'Doneone', at(0), at(0, 20));
    final doneGrey = await create(tester, 'Donegrey', at(1), at(1, 20));
    final run = await create(tester, 'Runner', at(40), at(41));
    await tester.runAsync(
      () => container.read(actionServiceProvider).start(run),
    );
    await setUrgency(tester, {future: 900, done: 900, run: 900});
    expect(unlinked.isNotEmpty, isTrue);
    expect(blockColor(tester, 'Unlinked'), emptyColors(dark: false).bg);
    expect(
      blockColor(tester, 'Future'),
      urgencyBackground(UrgencyBand.critical, dark: false),
    );
    // Linked + done: the band colour, muted. Unlinked + done: still white.
    expect(doneGrey.isNotEmpty, isTrue);
    expect(
      blockColor(tester, 'Doneone'),
      urgencyColorsMuted(900, dark: false).bg,
    );
    expect(blockColor(tester, 'Donegrey'), emptyColors(dark: false).bg);
    expect(blockColor(tester, 'Runner'), scheme.primary);
    await unmount(tester);
  });

  testWidgets(
    'block has a 1px neutral outline, 2px onSurface border when selected',
    (tester) async {
      for (final dark in [false, true]) {
        urgency.clear();
        await pump(
          tester,
          urgency,
          mode: dark ? ThemeMode.dark : ThemeMode.light,
        );
        await tomorrow(tester);
        await create(tester, 'Edge', at(33), at(34));
        await settle(tester);
        final scheme = Theme.of(tester.element(find.byType(CalendarView)))
            .colorScheme;
        BoxDecoration deco() =>
            tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.textContaining('Edge'),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        final thin = deco().border! as Border;
        expect(thin.top.width, 1, reason: 'thin outline, dark=$dark');
        expect(thin.top.color, isNot(scheme.onSurface));
        expect(deco().borderRadius, BorderRadius.circular(8));
        await tester.tap(find.textContaining('Edge'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        final selected = deco().border! as Border;
        expect(selected.top.width, 2);
        expect(selected.top.color, scheme.onSurface);
        await unmount(tester);
      }
    },
  );
}
