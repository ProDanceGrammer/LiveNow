// Shared fixture of the AiJobRunner tests: a budget with accounts and a few
// categories, a scripted extractor, the app-side chat service (writes the job
// rows exactly as the phone does) and the runner under test.
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_alias_db_source.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_job_runner.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_settings_store.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/receipt_extractor.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'ai_test_support.dart';

class FakeExtractor implements ReceiptExtractor {
  FakeExtractor([this.receipt]);

  ExtractedReceipt? receipt;

  /// Receipts handed out one per call, before falling back to [receipt].
  final queue = <ExtractedReceipt>[];
  Object? error;
  int calls = 0;

  @override
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime}) async {
    calls++;
    if (error != null) throw error!;
    return queue.isNotEmpty ? queue.removeAt(0) : receipt!;
  }
}

ReceiptLine rl(
  String raw,
  double? total, {
  String? name,
  double? qty,
  String? unit,
  double? unitPrice,
  double? grams,
  double discount = 0,
}) => ReceiptLine(
  raw: raw,
  name: name ?? raw,
  lineTotal: total,
  qtyLine: qty == null ? null : QtyLine(qty: qty, unit: unit, unitPrice: unitPrice),
  pack: grams == null ? null : PackSize(grams: grams),
  discount: discount,
);

ExtractedReceipt receiptOf(
  List<ReceiptLine> lines, {
  String merchant = 'BIM',
  String at = '2026-10-08T19:40:00',
  double? total,
  List<Tender>? tenders,
}) {
  final sum = lines.fold(0.0, (a, l) => a + (l.lineTotal ?? 0) - l.discount);
  final t = total ?? (sum * 100).round() / 100;
  return ExtractedReceipt(
    merchant: merchant,
    terminalDatetimeLocal: at,
    currency: 'TRY',
    total: t,
    tenders: tenders ?? [Tender(method: 'card', last4: '6141', amount: t)],
    lines: lines,
  );
}

class RunnerEnv {
  late AppDatabase db;
  late BudgetService budget;
  late ActionService actions;
  late AiChatService chat;
  late AiSettingsStore settings;
  late AiJobRunner runner;
  late DbAliasSource aliases;
  late AiRulesMemory rules;
  late String thread;
  late String tryAcc;
  late String monoAcc;
  late String fopAcc;
  late String groupFood;
  late String bread;
  late String salami;
  late String apricot;
  late String snacks;
  late String water;
  final extractor = FakeExtractor();
  final stored = <String>[];

  Future<void> init({
    bool autoMode = false,
    LlmClient? llm,
    OcrClient? ocr,
    ReceiptExtractor? realExtractor,
  }) async {
    db = memoryDb();
    budget = BudgetService(db);
    actions = ActionService(db);
    chat = AiChatService(db);
    settings = AiSettingsStore(db);
    aliases = DbAliasSource(db);
    rules = AiRulesMemory(db);
    if (autoMode) await settings.set(AiSettingKey.draftFirstCount, '0');

    tryAcc = await budget.saveAccount(name: 'Готівка TRY', currency: 'TRY', rateToBase: 36);
    monoAcc = await budget.saveAccount(name: 'Monobank', currency: 'UAH', rateToBase: 44);
    fopAcc = await budget.saveAccount(name: 'ФОП', currency: 'UAH', rateToBase: 44);
    final seed = Seed(db);
    groupFood = await seed.group('Їжа');
    Future<String> leaf(String n, double price, {BudgetUnit unit = BudgetUnit.kilogram}) =>
        seed.leaf(n, price: price, parentId: groupFood, unit: unit, count: tryAcc, use: monoAcc);
    bread = await leaf('🍞 Хліб', 106.67);
    salami = await leaf('🥩 Салямі', 650);
    apricot = await leaf('🍑 Курага', 650);
    water = await leaf('💧 Вода', 20);
    snacks = await leaf('🍫 Снеки (асорті)', 1, unit: BudgetUnit.piece);

    await aliases.remember('EKMEK KÖY 600G', categoryId: bread);
    await aliases.remember('SALAM HİNDİ FIST.50G', categoryId: salami);
    await aliases.remember('KURU KAYISI 250 G', categoryId: apricot);
    await aliases.remember('SAKA SU', categoryId: water);
    await rules.set('card.6141', {'account_id': monoAcc});

    thread = await chat.createThread(title: 't');
    runner = AiJobRunner(
      db: db,
      extractor: realExtractor ?? extractor,
      llm: llm,
      ocr: ocr,
      settings: settings,
      storeOriginal: (b) async => stored.add(b.id),
    );
  }

  Future<void> close() => db.close();

  Future<int> count(String table, [String where = '1=1']) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table WHERE $where').getSingle())
          .read<int>('n');

  /// A queued receipt job exactly as the phone writes it.
  Future<String> sendReceipt([ExtractedReceipt? r]) async {
    if (r != null) extractor.receipt = r;
    final sent = await chat.sendPhoto(thread, Uint8List.fromList(List.generate(40, (i) => i)));
    return sent.jobId!;
  }

  Future<String> sendScreenshot() async {
    final sent = await chat.sendPhoto(
      thread,
      Uint8List.fromList(List.generate(40, (i) => i + 1)),
      kind: AiJobKind.screenshot,
    );
    return sent.jobId!;
  }

  /// One message with several photos, as the phone sends it. Each photo is 40
  /// bytes of its marker, so a test OCR server can tell them apart.
  Future<String> sendPhotos(List<int> markers, {String caption = ''}) async {
    final sent = await chat.sendPhotos(thread, [
      for (final m in markers) (bytes: Uint8List.fromList(List.filled(40, m)), width: null, height: null),
    ], caption: caption);
    return sent.jobId!;
  }

  Future<int> drain([int max = 30]) async {
    var n = 0;
    while (n < max && await runner.runNext()) {
      n++;
    }
    return n;
  }

  Future<AiJob> job(String id) =>
      (db.select(db.aiJobsTable)..where((t) => t.id.equals(id))).getSingle();

  /// The newest ASSISTANT message of [kind] of the job.
  Future<AiMessage?> message(String jobId, String kind) async {
    final rows = await messages(jobId, kind);
    return rows.isEmpty ? null : rows.last;
  }

  Future<List<AiMessage>> messages(String jobId, String kind) =>
      (db.select(db.aiMessagesTable)
            ..where(
              (t) =>
                  t.jobId.equals(jobId) &
                  t.kind.equals(kind) &
                  t.role.equals(AiRole.assistant),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  Future<DraftCardView> draft(String jobId) async {
    final m = (await message(jobId, AiMessageKind.draft))!;
    return DraftCardView(m.id, jsonDecode(m.contentJson) as Map<String, dynamic>);
  }

  Future<List<BudgetTransaction>> transactions() =>
      (db.select(db.budgetTransactionsTable)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
}

/// Category inputs of the tests.
abstract final class CategoryInputLike {
  static CategoryInput leaf(
    String name,
    double price,
    String parent,
    String count,
    String use, {
    bool piece = false,
  }) => CategoryInput(
    name: name,
    unit: piece ? BudgetUnit.piece : BudgetUnit.kilogram,
    price: price,
    parentId: parent,
    accountCountId: count,
    accountUseId: use,
  );
}

class DraftCardView {
  DraftCardView(this.messageId, this.json);
  final String messageId;
  final Map<String, dynamic> json;

  List<Map<String, dynamic>> get lines => [
    for (final l in json['lines'] as List) Map<String, dynamic>.from(l as Map),
  ];
  Map<String, dynamic> get sum => Map<String, dynamic>.from(json['sum'] as Map);
}
