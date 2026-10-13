import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/direction_badge.dart';

/// The calendar badge shows only the emojis that fit the block, then '+N'
/// counting EVERY hidden direction (also the ones the provider already cut).
void main() {
  badgeScalerTest();
  test('everything fits: unchanged', () {
    expect(fitDirectionIcons('A B', null, 11), 'A B');
    expect(fitDirectionIcons('A B', 500, 11), 'A B');
  });

  test('a narrow block keeps the first icons and counts the rest', () {
    const icons = 'A B C D +2'; // 6 directions in all
    final full = directionBadgeWidth(icons, null, 11);
    final narrow = fitDirectionIcons(icons, full / 2, 11);
    final chunks = narrow.split(' ');
    expect(chunks.last.startsWith('+'), isTrue);
    final shown = chunks.length - 1;
    expect(chunks.take(shown), ['A', 'B', 'C', 'D'].take(shown));
    expect(chunks.last, '+${6 - shown}');
    expect(directionBadgeWidth(icons, full / 2, 11), lessThanOrEqualTo(full / 2));
  });

  test('no room at all: just the count', () {
    expect(fitDirectionIcons('A B C', 1, 11), '+3');
  });

  test('maxCount keeps the first emojis and folds the rest into +N', () {
    expect(fitDirectionIcons('A B C D E F', null, 11, maxCount: 4), 'A B C D +2');
    // An existing +n is merged into the count.
    expect(
      fitDirectionIcons('A B C D E F G H +3', null, 11, maxCount: 4),
      'A B C D +7',
    );
    expect(fitDirectionIcons('A B', null, 11, maxCount: 4), 'A B');
    // The width limit still applies after the count limit.
    final w = directionBadgeWidth('A B C D +2', null, 11);
    final narrow = fitDirectionIcons('A B C D E F', w / 2, 11, maxCount: 4);
    expect(narrow.split(' ').last, startsWith('+'));
    expect(narrow.split(' ').length, lessThan(5));
  });
}

// The badge is painted at the size it was measured at: the phone's text scale
// (Dynamic Type) must not make it wider than `fitDirectionIcons` allowed.
void badgeScalerTest() {
  testWidgets('the badge ignores the system text scale', (tester) async {
    Future<double> width(double scale) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Center(
                child: DirectionBadge(
                  actionId: 'a',
                  icons: 'A B C D',
                  maxWidth: 200,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(DirectionBadge)).width;
    }

    final normal = await width(1);
    final big = await width(1.6);
    expect(big, closeTo(normal, 0.5));
    expect(big, lessThanOrEqualTo(200));
  });
}
