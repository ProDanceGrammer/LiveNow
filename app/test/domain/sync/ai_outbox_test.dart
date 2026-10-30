import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_job_runner.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_settings_store.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/receipt_extractor.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'sync_harness.dart';

/// The text jobs of this test never read an image.
class _NoExtractor implements ReceiptExtractor {
  @override
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime}) =>
      throw StateError('no image expected');
}

/// The whole outbox on two devices: the phone writes a message + a job, sync
/// carries them to the hub, the hub's runner works, and the results come back as
/// ordinary rows (no new protocol). Re-running changes nothing.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late SyncDevice hub;
  late SyncDevice phone;

  setUp(() {
    hub = SyncDevice();
    phone = SyncDevice();
  });
  tearDown(() async {
    await hub.close();
    await phone.close();
  });

  Future<void> drainHub() async {
    final runner = AiJobRunner(
      db: hub.db,
      extractor: _NoExtractor(),
      settings: AiSettingsStore(hub.db),
    );
    var guard = 0;
    while (await runner.runNext()) {
      if (++guard > 20) fail('the runner never settles');
    }
  }

  Future<void> sync() async {
    await syncWith(phone, hub);
    await syncWith(phone, hub);
  }

  test('a transfer typed on the phone is recorded by the hub and syncs back', () async {
    final budget = BudgetService(hub.db);
    await budget.saveAccount(name: 'ФОП', currency: 'UAH', rateToBase: 44);
    await budget.saveAccount(name: 'Monobank', currency: 'UAH', rateToBase: 44);
    await sync(); // the phone knows the accounts

    final chat = AiChatService(phone.db);
    final thread = await chat.createThread(title: 'Money');
    final sent = await chat.sendText(thread, 'перевів 12582.50 з ФОП на Monobank');
    expect(sent.jobId, isNotNull);
    expect(await hub.count('ai_jobs'), 0, reason: 'nothing reaches the hub before a sync');

    await sync();
    expect(await hub.count('ai_jobs'), 1);
    expect(await hub.count('ai_messages', "kind = 'text'"), 1);

    await drainHub();
    expect(await hub.count('ai_jobs', "state = 'done'"), 1);
    expect(await hub.count('budget_transactions'), 2, reason: 'expense + income');

    await sync();
    // The phone got the results as ordinary synced rows.
    expect(await phone.count('budget_transactions'), 2);
    expect(await phone.count('ai_jobs', "state = 'done'"), 1);
    expect(await phone.count('ai_messages', "kind = 'result'"), 1);
    expect(await phone.count('ai_batches'), 1);

    // Running everything again (retry, another sync) duplicates nothing.
    await drainHub();
    await sync();
    expect(await hub.count('budget_transactions'), 2);
    expect(await hub.count('ai_batches'), 1);
    expect(await phone.count('budget_transactions'), 2);
  });

  test('purging old chat on the phone is local: the hub keeps it and nothing is re-sent', () async {
    final budget = BudgetService(hub.db);
    await budget.saveAccount(name: 'ФОП', currency: 'UAH', rateToBase: 44);
    await budget.saveAccount(name: 'Monobank', currency: 'UAH', rateToBase: 44);
    await sync();
    final chat = AiChatService(phone.db);
    final thread = await chat.createThread();
    await chat.sendText(thread, 'перевів 100 з ФОП на Monobank');
    await sync();
    await drainHub();
    await sync();

    final hubMessages = await hub.count('ai_messages');
    expect(hubMessages, greaterThan(1));

    final removed = await chat.pruneLocal(keepDays: 0, keepMessages: 0);
    expect(removed, greaterThan(0));
    expect(await phone.count('ai_messages'), lessThan(hubMessages));

    await sync();
    expect(await hub.count('ai_messages'), hubMessages, reason: 'the hub is the archive');
    expect(await hub.count('ai_jobs', "state = 'done'"), 1);
    // The budget rows are untouched by chat pruning.
    expect(await phone.count('budget_transactions'), 2);
  });

  test('a job written while the hub is unreachable waits and runs at the next sync', () async {
    final budget = BudgetService(hub.db);
    await budget.saveAccount(name: 'ФОП', currency: 'UAH', rateToBase: 44);
    await budget.saveAccount(name: 'Monobank', currency: 'UAH', rateToBase: 44);
    await sync();
    final chat = AiChatService(phone.db);
    final thread = await chat.createThread();
    await chat.sendText(thread, 'перевів 50 з ФОП на Monobank');
    await chat.sendText(thread, 'перевів 70 з ФОП на Monobank');
    // (no sync yet: the hub has no idea)
    await drainHub();
    expect(await hub.count('budget_transactions'), 0);

    await sync();
    await drainHub();
    await sync();
    expect(await phone.count('budget_transactions'), 4);
    expect(await phone.count('ai_jobs', "state = 'done'"), 2);
    expect(
      await phone.count('ai_jobs', "state = '${AiJobState.failed}'"),
      0,
    );
  });
}
