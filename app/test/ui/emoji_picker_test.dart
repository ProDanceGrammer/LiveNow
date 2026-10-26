import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/widgets/emoji_picker_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The emoji / flag chooser beside an icon field: it has a search, and the
/// chosen emoji goes into the field.
void main() {
  Future<TextEditingController> mount(
    WidgetTester tester, {
    required bool replace,
    String initial = '',
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    final controller = TextEditingController(text: initial);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 200, child: TextField(controller: controller)),
              EmojiPickerButton(controller: controller, replace: replace),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('emoji-picker-button')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    return controller;
  }

  testWidgets('the picker has a search that finds emoji by name', (
    tester,
  ) async {
    final controller = await mount(tester, replace: true);
    expect(find.byType(EmojiPicker), findsOneWidget);

    // The magnifier in the bottom bar opens the search field.
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump(const Duration(milliseconds: 600));
    final field = find.descendant(
      of: find.byType(EmojiPicker),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, 'grinning');
    await tester.pump(const Duration(milliseconds: 800));
    final results = find.byType(EmojiCell);
    expect(results, findsWidgets);

    await tester.tap(results.first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    // The field holds the chosen emoji and the picker closed.
    expect(controller.text, isNotEmpty);
    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('a name field gets the emoji inserted at the cursor', (
    tester,
  ) async {
    final controller = await mount(tester, replace: false, initial: 'Run');
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byType(EmojiCell).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.text.endsWith('Run'), isTrue);
    expect(controller.text.length, greaterThan('Run'.length));
  });
}
