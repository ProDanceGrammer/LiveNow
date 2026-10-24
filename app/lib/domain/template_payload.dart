import 'dart:async';
import 'dart:convert';

import '../core/error_log.dart';
import '../core/number_rules.dart' show kMaxEstimatedMinutes;

/// Reads `action_templates.payload` without ever throwing. A payload that is
/// not valid JSON (or not an object) becomes a bare placeholder carrying
/// [fallbackName] (the row's own `name` column) and is written to the error
/// log; a field of the wrong type (a number where text belongs, an id list
/// holding numbers ...) is dropped, so one damaged template can never break the
/// Templates list, the editor or "new from template".
Map<String, dynamic> decodeTemplatePayload(
  String payload, {
  required String fallbackName,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on Object catch (e, st) {
    unawaited(ErrorLog.write(e, st, context: 'template payload'));
  }
  if (decoded is! Map) {
    if (decoded != null) {
      unawaited(
        ErrorLog.write(
          FormatException('A template payload is not an object', payload),
          null,
          context: 'template payload',
        ),
      );
    }
    return {'name': fallbackName, 'metricIds': <String>[]};
  }
  final out = <String, dynamic>{
    for (final e in decoded.entries) '${e.key}': e.value,
  };
  String? text(String key) => out[key] is String ? out[key] as String : null;
  void keepOnly<T>(String key) {
    if (out[key] != null && out[key] is! T) out.remove(key);
  }

  final name = text('name');
  out['name'] = (name == null || name.trim().isEmpty) ? fallbackName : name;
  final minutes = out['estimatedMinutes'];
  if (minutes is num) {
    if (minutes.isFinite && minutes >= 0 && minutes <= kMaxEstimatedMinutes) {
      out['estimatedMinutes'] = minutes.toInt();
    } else {
      out.remove('estimatedMinutes');
    }
  } else {
    out.remove('estimatedMinutes');
  }
  for (final k in ['postponeFlex', 'depthLevel', 'notes', 'diaryBlocks']) {
    keepOnly<String>(k);
  }
  keepOnly<bool>('isAllDay');
  keepOnly<bool>('useAverage');
  final ids = out['metricIds'];
  out['metricIds'] = ids is List
      ? [
          for (final id in ids)
            if (id is String) id,
        ]
      : <String>[];
  return out;
}
