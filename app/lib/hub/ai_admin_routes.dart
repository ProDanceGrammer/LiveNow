import 'dart:async';

import '../data/ai/llm_client.dart';
import '../data/ai/ocr_client.dart';
import '../data/database.dart';
import '../domain/ai/ai_protocol.dart';
import '../domain/ai/ai_settings_store.dart';
import '../domain/sync/network_rules.dart';

/// The hub-side admin routes of the AI assistant (`ai-settings`, `ai-status`),
/// reached through `HubAdmin` (loopback + the admin device only). The token is
/// stored but never returned: reads only say whether one is set.
class AiAdminRoutes {
  AiAdminRoutes(this.db, {this.healthTimeout = const Duration(seconds: 3)})
    : settings = AiSettingsStore(db);

  final AppDatabase db;
  final AiSettingsStore settings;
  final Duration healthTimeout;

  static const _urlKeys = {AiSettingKey.llmUrl, AiSettingKey.ocrUrl};
  static const _textKeys = {
    AiSettingKey.llmModel,
    AiSettingKey.visionModel,
    AiSettingKey.llmToken,
  };
  static const _intRanges = <String, (int, int)>{
    AiSettingKey.draftFirstCount: (0, 1000),
    AiSettingKey.confirmedCount: (0, 1000000),
    AiSettingKey.photoRetentionDays: (0, 3650),
  };

  Future<Map<String, Object?>> handle(
    String route,
    Map<String, Object?> request,
  ) async {
    switch (route) {
      case 'ai-settings':
        final values = request['values'];
        if (values != null) {
          if (values is! Map) throw const FormatException('values');
          await _save(values.cast<String, Object?>());
        }
        return _read();
      case 'ai-status':
        return _status();
      default:
        throw const FormatException('unknown admin route');
    }
  }

  Future<Map<String, Object?>> _read() async {
    final s = await settings.load();
    return {
      AiSettingKey.llmUrl: s.llmUrl,
      AiSettingKey.llmModel: s.llmModel,
      'llm_token_set': s.llmToken.isNotEmpty,
      AiSettingKey.ocrUrl: s.ocrUrl,
      AiSettingKey.visionModel: s.visionModel,
      AiSettingKey.draftFirstCount: s.draftFirstCount,
      AiSettingKey.confirmedCount: s.confirmedCount,
      AiSettingKey.photoRetentionDays: s.photoRetentionDays,
    };
  }

  /// Validates EVERYTHING first, then writes: a bad value changes nothing.
  Future<void> _save(Map<String, Object?> values) async {
    final clean = <String, String>{};
    for (final e in values.entries) {
      clean[e.key] = _validate(e.key, e.value);
    }
    for (final e in clean.entries) {
      await settings.set(e.key, e.value);
    }
  }

  String _validate(String key, Object? v) {
    if (_urlKeys.contains(key)) {
      if (v is! String) throw FormatException(key);
      final t = v.trim();
      if (t.isEmpty) return t; // blank = the default
      final u = Uri.tryParse(t);
      final ok =
          u != null &&
          (u.scheme == 'http' || u.scheme == 'https') &&
          u.host.isNotEmpty &&
          u.userInfo.isEmpty &&
          (isPrivateAddress(u.host) || isLocalHostName(u.host));
      if (!ok) throw FormatException('$key must be a local http(s) address');
      return t;
    }
    if (_textKeys.contains(key)) {
      if (v is! String) throw FormatException(key);
      final t = v.trim();
      final max = key == AiSettingKey.llmToken ? 500 : 200;
      if (t.length > max || RegExp(r'[\x00-\x1f\x7f]').hasMatch(t)) {
        throw FormatException(key);
      }
      return t;
    }
    final range = _intRanges[key];
    if (range != null) {
      final n = v is num ? v.toInt() : int.tryParse('$v'.trim());
      if (n == null || n < range.$1 || n > range.$2) {
        throw FormatException('$key out of range');
      }
      return '$n';
    }
    throw FormatException('unknown setting $key');
  }

  Future<Map<String, Object?>> _status() async {
    final s = await settings.load();
    final key = s.llmToken.isEmpty ? null : s.llmToken;
    final checks = await Future.wait([
      LlmClient(
        baseUrl: s.llmUrl,
        model: s.llmModel,
        apiKey: key,
      ).health(timeout: healthTimeout),
      OcrClient(baseUrl: s.ocrUrl).health(timeout: healthTimeout),
    ]);
    final counts = <String, int>{};
    for (final r
        in await db
            .customSelect(
              'SELECT state, COUNT(*) AS n FROM ai_jobs GROUP BY state',
            )
            .get()) {
      counts[r.read<String>('state')] = r.read<int>('n');
    }
    final last = await db
        .customSelect(
          'SELECT id, error, updated_at FROM ai_jobs '
          "WHERE error IS NOT NULL AND error != '' "
          'ORDER BY updated_at DESC LIMIT 1',
        )
        .getSingleOrNull();
    return {
      'llm_ok': checks[0],
      'ocr_ok': checks[1],
      'llm_model': s.llmModel,
      'vision_model': s.visionModel,
      'queue': {for (final st in _states) st: counts[st] ?? 0},
      'last_error': last == null
          ? null
          : {
              'job_id': last.read<String>('id'),
              'error': last.read<String>('error'),
              'at': last.read<String>('updated_at'),
            },
    };
  }

  static const _states = [
    AiJobState.queued,
    AiJobState.running,
    AiJobState.needsInput,
    AiJobState.draftReady,
    AiJobState.committing,
    AiJobState.done,
    AiJobState.failed,
  ];
}
