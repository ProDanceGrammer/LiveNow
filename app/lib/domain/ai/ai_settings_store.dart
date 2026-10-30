import '../../data/database.dart';
import 'ai_protocol.dart';

/// The hub's device-local AI settings (`ai_settings`, never synced or backed
/// up). The token is stored here and is never logged: [AiSettingsSnapshot]
/// prints it masked.
class AiSettingsStore {
  AiSettingsStore(this.db);

  final AppDatabase db;

  static const defaults = <String, String>{
    AiSettingKey.llmUrl: 'http://127.0.0.1:11434',
    AiSettingKey.llmModel: 'qwen2.5:3b-instruct',
    AiSettingKey.llmToken: '',
    // The port of app/windows/hub/ai/ocr_service.py (kOcrServicePort).
    AiSettingKey.ocrUrl: 'http://127.0.0.1:47655',
    AiSettingKey.visionModel: '',
    AiSettingKey.draftFirstCount: '5',
    AiSettingKey.confirmedCount: '0',
    AiSettingKey.photoRetentionDays: '90',
  };

  /// A stored value, or the default when there is none (or it is blank).
  Future<String> get(String key) async {
    final row = await (db.select(
      db.aiSettingsTable,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    final v = row?.value ?? '';
    return v.trim().isEmpty ? (defaults[key] ?? '') : v;
  }

  Future<int> getInt(String key) async =>
      int.tryParse(await get(key)) ?? int.parse(defaults[key] ?? '0');

  Future<void> set(String key, String value) => db
      .into(db.aiSettingsTable)
      .insertOnConflictUpdate(
        AiSettingsTableCompanion.insert(key: key, value: value),
      );

  Future<AiSettingsSnapshot> load() async => AiSettingsSnapshot(
    llmUrl: await get(AiSettingKey.llmUrl),
    llmModel: await get(AiSettingKey.llmModel),
    llmToken: await get(AiSettingKey.llmToken),
    ocrUrl: await get(AiSettingKey.ocrUrl),
    visionModel: await get(AiSettingKey.visionModel),
    draftFirstCount: await getInt(AiSettingKey.draftFirstCount),
    confirmedCount: await getInt(AiSettingKey.confirmedCount),
    photoRetentionDays: await getInt(AiSettingKey.photoRetentionDays),
  );

  Future<int> confirmedCount() => getInt(AiSettingKey.confirmedCount);

  /// Counts one more confirmed receipt; returns the new count.
  Future<int> incrementConfirmed() => db.transaction(() async {
    final n = await confirmedCount() + 1;
    await set(AiSettingKey.confirmedCount, '$n');
    return n;
  });

  /// True while fewer receipts than `draft_first_count` were confirmed: the
  /// worker then prepares a draft instead of writing.
  Future<bool> draftFirstActive() async =>
      await confirmedCount() < await getInt(AiSettingKey.draftFirstCount);
}

class AiSettingsSnapshot {
  const AiSettingsSnapshot({
    required this.llmUrl,
    required this.llmModel,
    required this.llmToken,
    required this.ocrUrl,
    required this.visionModel,
    required this.draftFirstCount,
    required this.confirmedCount,
    required this.photoRetentionDays,
  });

  final String llmUrl;
  final String llmModel;
  final String llmToken;
  final String ocrUrl;
  final String visionModel;
  final int draftFirstCount;
  final int confirmedCount;
  final int photoRetentionDays;

  @override
  String toString() =>
      'AiSettingsSnapshot(llmUrl: $llmUrl, llmModel: $llmModel, '
      'llmToken: ${llmToken.isEmpty ? '' : '***'}, ocrUrl: $ocrUrl, '
      'visionModel: $visionModel, draftFirstCount: $draftFirstCount, '
      'confirmedCount: $confirmedCount, photoRetentionDays: $photoRetentionDays)';
}
