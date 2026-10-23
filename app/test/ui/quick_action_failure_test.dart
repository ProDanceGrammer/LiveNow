import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/error_log.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/undo.dart';

/// A quick button whose write fails must not "do nothing" silently: a toast says
/// what could not be done and the error goes to error.log.
void main() {
  late AppDatabase db;
  late Directory logDir;

  setUp(() {
    logDir = Directory.systemTemp.createTempSync('livenow_errlog_');
    ErrorLog.errorLogDirectoryOverride = logDir;
  });

  tearDown(() {
    ErrorLog.errorLogDirectoryOverride = null;
    if (logDir.existsSync()) logDir.deleteSync(recursive: true);
  });

  testWidgets('a failing operation shows a toast and is written to error.log', (
    tester,
  ) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final id = (await tester.runAsync(
      () => ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)])
          .read(actionServiceProvider)
          .createAction(name: 'Планування на наступний тиждень'),
    ))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => runUndoable(
                  context,
                  ref,
                  id,
                  'Started',
                  () async => throw StateError('Too many elements'),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Could not complete "Started"'),
      findsOneWidget,
    );
    expect(find.textContaining('Too many elements'), findsOneWidget);

    final text = await tester.runAsync(
      () => File('${logDir.path}${Platform.pathSeparator}error.log')
          .readAsString(),
    );
    expect(text, contains('[Started]'));
    expect(text, contains('Too many elements'));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
