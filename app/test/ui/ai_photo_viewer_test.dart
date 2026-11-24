import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/ai_history_loader.dart';
import 'package:livenow/ui/widgets/ai_photo_viewer.dart';

// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  Future<void> open(
    WidgetTester tester,
    List<AiPhotoRef> photos,
    Future<Uint8List?> Function(String) fetch,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiBlobFetcherProvider.overrideWithValue(fetch)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('go'),
              onPressed: () => showAiPhotoViewer(context, photos, 0),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a hub page shows a spinner, then the image', (tester) async {
    final done = Completer<Uint8List?>();
    await open(tester, [AiPhotoRef.hub('b1')], (_) => done.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-photo-counter')), findsNothing);
    expect(find.byKey(const ValueKey('ai-photo-next')), findsNothing);
    done.complete(_png);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-photo-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-photo-viewer')), findsNothing);
  });

  testWidgets('a hub page the hub cannot give says so', (tester) async {
    await open(tester, [AiPhotoRef.hub('b1')], (_) async => null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('The original is not available from the hub'),
      findsOneWidget,
    );
  });

  testWidgets('a throwing fetch gives the same message; fetched once', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, [AiPhotoRef.hub('b1'), AiPhotoRef.local(_png)], (
      _,
    ) async {
      calls++;
      throw StateError('offline');
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('The original is not available from the hub'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ai-photo-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-photo-prev')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
