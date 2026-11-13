import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/app_search_field.dart';
import 'package:livenow/ui/widgets/keyboard_hide_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    builder: (context, c) => KeyboardHideLayer(child: c!),
    home: Scaffold(body: Center(child: child)),
  );

  group('AppSearchField', () {
    testWidgets('the X shows with text; it clears and reports the empty text', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(host(AppSearchField(
        key: const ValueKey('f'),
        clearKey: const ValueKey('x'),
        onChanged: seen.add,
      )));
      expect(find.byKey(const ValueKey('x')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('f')), 'milk');
      await tester.pump();
      expect(find.byKey(const ValueKey('x')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('x')));
      await tester.pump();
      expect(seen.last, '');
      expect(find.text('milk'), findsNothing);
      expect(find.byKey(const ValueKey('x')), findsNothing);
    });

    testWidgets('a closable search always shows the X; it clears, unfocuses and closes', (tester) async {
      var closed = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(host(AppSearchField(
        key: const ValueKey('f'),
        clearKey: const ValueKey('x'),
        focusNode: focus,
        onClose: () => closed++,
      )));
      expect(find.byKey(const ValueKey('x')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('f')), 'run');
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.byKey(const ValueKey('x')));
      await tester.pump();
      expect(closed, 1);
      expect(focus.hasFocus, isFalse);
    });
  });

  group('KeyboardHideLayer', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<FocusNode> openKeyboard(WidgetTester tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(host(TextField(key: const ValueKey('t'), focusNode: focus)));
      await tester.tap(find.byKey(const ValueKey('t')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      return focus;
    }

    testWidgets('iOS with the keyboard open: the button shows; a tap hides the keyboard', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final focus = await openKeyboard(tester);
      expect(focus.hasFocus, isTrue);
      expect(find.byKey(const ValueKey('keyboard-hide')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('keyboard-hide')));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('not iOS, or no keyboard: no button', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await openKeyboard(tester);
      expect(find.byKey(const ValueKey('keyboard-hide')), findsNothing);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.byKey(const ValueKey('keyboard-hide')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
