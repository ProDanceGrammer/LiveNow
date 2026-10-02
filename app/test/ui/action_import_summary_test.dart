import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/action_import_service.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/widgets/action_import_summary_dialog.dart';

void main() {
  testWidgets('summary dialog lists counts and problems', (tester) async {
    const result = ActionImportResult(
      created: 5,
      skippedDuplicates: 2,
      edgesCreated: 3,
      unmatchedDirections: ['Невідомий напрям'],
      unresolvedRefs: ['A -> Давня задача (2026-07-05)'],
      rejectedEdges: ['B -> A'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ActionImportSummaryDialog.show(context, result),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('5 created'), findsOneWidget);
    expect(find.text('2 skipped as duplicates'), findsOneWidget);
    expect(find.text('Unmatched growth directions (1)'), findsOneWidget);
    expect(find.text('Невідомий напрям'), findsOneWidget);
    expect(
      find.text('Unresolved next/previous references (1)'),
      findsOneWidget,
    );
    expect(find.text('Links refused (1)'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionImportSummaryDialog), findsNothing);
    expect(openStackedDialogCount, 0);
  });
}
