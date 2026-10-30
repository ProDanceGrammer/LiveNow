import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai/ai_protocol.dart';
import '../sync_providers.dart';

/// Settings > Assistant: the hub's model server, models, how many receipts need
/// a draft first and how long photos are kept. The values live on the HUB (set
/// through its admin side), so the token never reaches a phone; only a device
/// the hub trusts as admin can change them.
class AiHubSettings extends ConsumerStatefulWidget {
  const AiHubSettings({super.key});

  @override
  ConsumerState<AiHubSettings> createState() => _AiHubSettingsState();
}

class _AiHubSettingsState extends ConsumerState<AiHubSettings> {
  final _llmUrl = TextEditingController();
  final _llmModel = TextEditingController();
  final _token = TextEditingController();
  final _ocrUrl = TextEditingController();
  final _vision = TextEditingController();
  final _draftCount = TextEditingController();
  final _retention = TextEditingController();

  bool _tokenSet = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  Map<String, Object?>? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _llmUrl,
      _llmModel,
      _token,
      _ocrUrl,
      _vision,
      _draftCount,
      _retention,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _s(Map<String, Object?> m, String key) => (m[key] ?? '').toString();

  void _fill(Map<String, Object?> m) {
    _llmUrl.text = _s(m, AiSettingKey.llmUrl);
    _llmModel.text = _s(m, AiSettingKey.llmModel);
    _ocrUrl.text = _s(m, AiSettingKey.ocrUrl);
    _vision.text = _s(m, AiSettingKey.visionModel);
    _draftCount.text = _s(m, AiSettingKey.draftFirstCount);
    _retention.text = _s(m, AiSettingKey.photoRetentionDays);
    _tokenSet = m['llm_token_set'] == true;
    _token.clear();
  }

  /// Reads the settings and the status from the hub.
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = ref.read(hubAdminProvider);
      final settings = await access.run((h) => h.fetchAiSettings());
      final status = await access.run((h) => h.fetchAiStatus());
      if (!mounted) return;
      setState(() {
        _fill(settings);
        _status = status;
        _loaded = true;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'Cannot read the hub\'s assistant settings: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final values = <String, Object?>{
      AiSettingKey.llmUrl: _llmUrl.text.trim(),
      AiSettingKey.llmModel: _llmModel.text.trim(),
      AiSettingKey.ocrUrl: _ocrUrl.text.trim(),
      AiSettingKey.visionModel: _vision.text.trim(),
      AiSettingKey.draftFirstCount: _draftCount.text.trim(),
      AiSettingKey.photoRetentionDays: _retention.text.trim(),
      // Empty = leave the stored token as it is (typing one replaces it).
      if (_token.text.isNotEmpty) AiSettingKey.llmToken: _token.text,
    };
    try {
      final now = await ref
          .read(hubAdminProvider)
          .run((h) => h.saveAiSettings(values));
      final status = await ref.read(hubAdminProvider).run((h) => h.fetchAiStatus());
      if (!mounted) return;
      setState(() {
        _fill(now);
        _status = status;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Not saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearToken() async {
    setState(() => _busy = true);
    try {
      final now = await ref
          .read(hubAdminProvider)
          .run((h) => h.saveAiSettings({AiSettingKey.llmToken: ''}));
      if (mounted) setState(() => _fill(now));
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Not saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, TextEditingController c, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      key: ValueKey(key),
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
    ),
  );

  String _statusText() {
    final s = _status;
    if (s == null) return '';
    String yn(Object? v) => v == true ? 'reachable' : 'not reachable';
    final q = s['queue'];
    final queued = q is Map ? q : const {};
    final waiting =
        (queued[AiJobState.queued] ?? 0).toString();
    final running = (queued[AiJobState.running] ?? 0).toString();
    final err = s['last_error'];
    return 'Model server: ${yn(s['llm_ok'])}. OCR service: ${yn(s['ocr_ok'])}. '
        'Jobs: $waiting queued, $running running.'
        '${err is Map ? '\nLast error: ${err['error']}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These settings live on the hub. The assistant reads receipts '
            'there, so the model server must be reachable from the hub PC.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const ValueKey('ai-settings-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_loaded) ...[
            _field('ai-settings-llm-url', 'Model server URL', _llmUrl,
                hint: 'http://127.0.0.1:11434'),
            _field('ai-settings-llm-model', 'Text model', _llmModel,
                hint: 'qwen2.5:3b-instruct'),
            _field(
              'ai-settings-token',
              _tokenSet ? 'Token (set; type to replace)' : 'Token (optional)',
              _token,
              obscure: true,
            ),
            if (_tokenSet)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('ai-settings-clear-token'),
                  onPressed: _busy ? null : _clearToken,
                  child: const Text('Remove token'),
                ),
              ),
            _field('ai-settings-ocr-url', 'OCR service URL', _ocrUrl,
                hint: 'http://127.0.0.1:47655'),
            _field('ai-settings-vision-model', 'Vision model (optional)', _vision,
                hint: 'leave empty on a CPU-only hub'),
            _field('ai-settings-draft-count', 'Receipts that need a draft first',
                _draftCount, keyboard: TextInputType.number),
            _field('ai-settings-retention', 'Keep receipt photos (days)',
                _retention, keyboard: TextInputType.number),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: const ValueKey('ai-settings-save'),
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('ai-settings-refresh'),
                  onPressed: _busy ? null : _load,
                  child: const Text('Check status'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _statusText(),
                  key: const ValueKey('ai-settings-status'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ] else if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else
            TextButton(
              key: const ValueKey('ai-settings-retry'),
              onPressed: _load,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
