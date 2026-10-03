import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/theme/glass_theme.dart';
import 'package:livenow/ui/widgets/param_icons.dart';

Widget _wrap(Widget child, Brightness b) => MaterialApp(
  theme: buildAppTheme(b),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final b in Brightness.values) {
    testWidgets('renders every icon at 12/16/24 px (${b.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              for (final s in [12.0, 16.0, 24.0])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in Param.values) ParamIcon(p, size: s),
                  ],
                ),
            ],
          ),
          b,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ParamIcon), findsNWidgets(18));
    });
  }

  testWidgets('tooltip text per param', (tester) async {
    for (final p in Param.values) {
      await tester.pumpWidget(_wrap(ParamIcon(p), Brightness.light));
      final t = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(t.message, kParamNames[p]);
    }
    expect(kParamNames[Param.urgency], 'Urgency to Keep in Balance');
    await tester.pumpWidget(
      _wrap(const ParamIcon.weight(tooltip: false), Brightness.light),
    );
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('colour override and default', (tester) async {
    await tester.pumpWidget(
      _wrap(const ParamIcon.level(color: Colors.red), Brightness.light),
    );
    var p =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(ParamIcon),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter
            as ParamIconPainter;
    expect(p.color, Colors.red);
    await tester.pumpWidget(_wrap(const ParamIcon.level(), Brightness.light));
    p =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(ParamIcon),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter
            as ParamIconPainter;
  });

  testWidgets('urgency icon defaults to the violet token; text stays neutral', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      final token = b == Brightness.dark
          ? GlassTheme.darkTheme.urgencyIcon
          : GlassTheme.light.urgencyIcon;
      Color painted() =>
          (tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: find.byType(ParamIcon),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter
                  as ParamIconPainter)
              .color;
      await tester.pumpWidget(_wrap(const ParamIcon.urgency(), b));
      await tester.pumpAndSettle();
      expect(painted(), token);
      // ParamValue: `color` only tints the text, the icon stays violet.
      await tester.pumpWidget(
        _wrap(const ParamValue.urgency('9', color: Colors.red), b),
      );
      expect(painted(), token);
      expect(tester.widget<Text>(find.text('9')).style?.color, Colors.red);
      // Explicit colour (Balance header) wins.
      await tester.pumpWidget(
        _wrap(const ParamIcon.urgency(color: Colors.green), b),
      );
      expect(painted(), Colors.green);
    }
  });

  testWidgets('ParamValue keeps its text findable; tooltip on icon only', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ParamValue.urgency('910', key: Key('v')), Brightness.dark),
    );
    expect(find.text('910'), findsOneWidget);
    expect(find.byKey(const Key('v')), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Tooltip), matching: find.text('910')),
      findsNothing,
    );
  });

  testWidgets('ParamLabel shows icon and word', (tester) async {
    await tester.pumpWidget(
      _wrap(const ParamLabel(Param.direction), Brightness.light),
    );
    expect(find.text('Direction'), findsOneWidget);
    await tester.pumpWidget(
      _wrap(const ParamLabel(Param.weight, text: 'W'), Brightness.light),
    );
    expect(find.text('W'), findsOneWidget);
  });

  test('shouldRepaint only on colour/size/param change', () {
    final a = ParamIconPainter(Param.level, Colors.red, 16);
    expect(
      a.shouldRepaint(ParamIconPainter(Param.level, Colors.red, 16)),
      isFalse,
    );
    expect(
      a.shouldRepaint(ParamIconPainter(Param.level, Colors.blue, 16)),
      isTrue,
    );
    expect(
      a.shouldRepaint(ParamIconPainter(Param.level, Colors.red, 24)),
      isTrue,
    );
  });
}
