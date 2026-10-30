import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_settings_store.dart';
import 'package:livenow/domain/ai/photo_prep.dart';

import 'ai_test_support.dart';

void main() {
  group('AiSettingsStore', () {
    late AppDatabase db;
    late AiSettingsStore store;

    setUp(() {
      db = memoryDb();
      store = AiSettingsStore(db);
    });
    tearDown(() => db.close());

    test('defaults are served when nothing is stored', () async {
      final s = await store.load();
      expect(s.llmUrl, 'http://127.0.0.1:11434');
      expect(s.ocrUrl, 'http://127.0.0.1:8765');
      expect(s.draftFirstCount, 5);
      expect(s.photoRetentionDays, 90);
      expect(s.confirmedCount, 0);
    });

    test(
      'values are stored and read back; blank falls back to default',
      () async {
        await store.set(AiSettingKey.llmUrl, 'http://hub:1');
        await store.set(AiSettingKey.ocrUrl, ' ');
        expect(await store.get(AiSettingKey.llmUrl), 'http://hub:1');
        expect(await store.get(AiSettingKey.ocrUrl), 'http://127.0.0.1:8765');
      },
    );

    test('draft-first stays active until N receipts were confirmed', () async {
      await store.set(AiSettingKey.draftFirstCount, '2');
      expect(await store.draftFirstActive(), isTrue);
      expect(await store.incrementConfirmed(), 1);
      expect(await store.draftFirstActive(), isTrue);
      expect(await store.incrementConfirmed(), 2);
      expect(await store.draftFirstActive(), isFalse);
    });

    test('the token is masked when printed', () async {
      await store.set(AiSettingKey.llmToken, 'sekret-token');
      expect((await store.load()).toString(), isNot(contains('sekret')));
    });
  });

  group('prepareReceiptPhoto', () {
    Uint8List jpeg(int w, int h) =>
        Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

    test('scales a large photo down to the long side', () {
      final p = prepareReceiptPhoto(jpeg(3200, 1600));
      expect((p.width, p.height), (1600, 800));
      final back = img.decodeJpg(p.bytes)!;
      expect((back.width, back.height), (1600, 800));
    });

    test('a tall photo is limited by its height', () {
      final p = prepareReceiptPhoto(jpeg(800, 2400), longSide: 1200);
      expect((p.width, p.height), (400, 1200));
    });

    test('a small photo is not enlarged', () {
      final p = prepareReceiptPhoto(jpeg(300, 200));
      expect((p.width, p.height), (300, 200));
    });

    test('EXIF rotation is applied', () {
      final src = img.Image(width: 400, height: 200);
      src.exif.imageIfd.orientation = 6; // rotate 90 degrees clockwise
      final p = prepareReceiptPhoto(Uint8List.fromList(img.encodeJpg(src)));
      expect((p.width, p.height), (200, 400));
    });

    test('garbage and oversized input are refused', () {
      expect(
        () => prepareReceiptPhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(
        () => prepareReceiptPhoto(Uint8List(kMaxPhotoInputBytes + 1)),
        throwsFormatException,
      );
    });
  });
}
