import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// The editor lives inside a dialog whose parent rebuilds on every keystroke
/// in other fields; the editor must survive that (regression: a `late final`
/// field assigned in `build` threw a LateError on the second build) and must
/// keep its content and state.
void main() {
  testWidgets('rebuilding the parent keeps the editor and its state', (
    tester,
  ) async {
    final rebuild = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, n, _) => Column(
              children: [
                Text('rebuild $n'),
                NotesEditor(
                  key: const ValueKey('notes'),
                  initialJson: null,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final state = tester.state(find.byType(NotesEditor));
    for (var i = 1; i <= 3; i++) {
      rebuild.value = i;
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('rebuild 3'), findsOneWidget);
    expect(
      identical(tester.state(find.byType(NotesEditor)), state),
      isTrue,
      reason: 'the same State object survives the parent rebuilds',
    );
  });

  testWidgets('a theme change rebuilds the editor without errors', (
    tester,
  ) async {
    final dark = ValueNotifier(false);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, isDark, _) => MaterialApp(
          theme: isDark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: NotesEditor(initialJson: null, onChanged: (_) {}),
          ),
        ),
      ),
    );
    dark.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(NotesEditor), findsOneWidget);
  });
}
