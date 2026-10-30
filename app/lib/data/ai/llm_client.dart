/// Client for an OpenAI-compatible model server (Ollama, llama.cpp, vLLM):
/// non-streaming `/v1/chat/completions`, JSON-schema constrained output with a
/// "first JSON object in the text" fallback, retry with capped backoff, typed
/// failures and cancellation. Runs on the hub only.
///
/// Memory note (hub PC: CPU, <= 8 GB): the pipeline calls OCR and the model one
/// after the other, and Ollama should unload the model soon after use. Ollama's
/// OpenAI endpoint ignores a `keep_alive` body field, so set it for the server
/// (`OLLAMA_KEEP_ALIVE=1m`, done by install_ai.ps1); [extraBody] still lets a
/// server that does read such fields get them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/ai/model_prompts.dart';
import 'ai_http.dart';

export 'ai_http.dart'
    show
        AiBadResponseException,
        AiCancelToken,
        AiCancelledException,
        AiException,
        AiTimeoutException,
        AiUnreachableException;

/// One chat message. [content] is a String, or a list of OpenAI content parts
/// (text / image_url) for a vision model.
class LlmMessage {
  const LlmMessage(this.role, this.content);

  final String role;
  final Object content;

  factory LlmMessage.system(String text) => LlmMessage('system', text);
  factory LlmMessage.user(String text) => LlmMessage('user', text);

  /// A user message with one picture sent as a base64 data URL.
  factory LlmMessage.userWithImage(
    String text,
    Uint8List image, {
    String mime = 'image/jpeg',
  }) => LlmMessage('user', [
    {'type': 'text', 'text': text},
    {
      'type': 'image_url',
      'image_url': {'url': 'data:$mime;base64,${base64Encode(image)}'},
    },
  ]);

  Map<String, Object> toJson() => {'role': role, 'content': content};
}

class LlmClient {
  LlmClient({
    required String baseUrl,
    required this.model,
    this.apiKey,
    this.requestTimeout = const Duration(minutes: 10),
    this.maxRetries = 2,
    this.retryBaseDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.maxResponseBytes = 8 * 1024 * 1024,
    this.defaultTemperature = 0.1,
    this.extraBody = const {},
  }) : baseUrl = _normalizeBase(baseUrl);

  /// Server root without a trailing slash or `/v1`.
  final String baseUrl;
  final String model;
  final String? apiKey;

  /// Overall deadline of ONE request (CPU inference takes minutes).
  final Duration requestTimeout;

  /// Extra attempts after a connection failure, 429 or 5xx (not after a
  /// timeout: a stuck CPU job would only be started again).
  final int maxRetries;
  final Duration retryBaseDelay;
  final Duration maxRetryDelay;
  final int maxResponseBytes;
  final double defaultTemperature;

  /// Merged into every request body (server-specific fields).
  final Map<String, Object?> extraBody;

  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/v1')) u = u.substring(0, u.length - 3);
    return u;
  }

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'accept': 'application/json',
    if (apiKey != null && apiKey!.isNotEmpty) 'authorization': 'Bearer $apiKey',
  };

  /// True when the server answers `GET /v1/models` (or Ollama's `/api/tags`).
  /// Never throws.
  Future<bool> health({Duration timeout = const Duration(seconds: 5)}) async {
    for (final path in const ['/v1/models', '/api/tags']) {
      try {
        final r = await aiHttpSend(
          'GET',
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          timeout: timeout,
          connectTimeout: timeout,
          maxBytes: 1024 * 1024,
        );
        if (r.ok) return true;
      } on AiException {
        // try the next route
      }
    }
    return false;
  }

  /// Sends [messages] and returns the reply text. With [jsonSchema] the server is
  /// asked for schema-constrained output; a server that rejects `response_format`
  /// (HTTP 400) is retried once with the schema written into the prompt instead.
  Future<String> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? jsonSchema,
    String schemaName = 'reply',
    double? temperature,
    int? maxTokens,
    AiCancelToken? cancel,
  }) async {
    try {
      return await _chatOnce(
        messages,
        jsonSchema: jsonSchema,
        schemaName: schemaName,
        useResponseFormat: true,
        temperature: temperature,
        maxTokens: maxTokens,
        cancel: cancel,
      );
    } on AiBadResponseException catch (e) {
      if (jsonSchema == null || e.status != 400) rethrow;
      return _chatOnce(
        [
          LlmMessage.system(
            'Answer with ONE JSON object matching this schema: ${jsonEncode(jsonSchema)}',
          ),
          ...messages,
        ],
        jsonSchema: jsonSchema,
        schemaName: schemaName,
        useResponseFormat: false,
        temperature: temperature,
        maxTokens: maxTokens,
        cancel: cancel,
      );
    }
  }

  /// [chat] with a schema, parsed into a JSON object. Text around the object is
  /// tolerated. If there is no object, asks once more ([jsonAttempts] total)
  /// before throwing [AiBadResponseException].
  Future<Map<String, dynamic>> chatJson(
    List<LlmMessage> messages, {
    required Map<String, dynamic> schema,
    String schemaName = 'reply',
    double? temperature,
    int? maxTokens,
    int jsonAttempts = 2,
    AiCancelToken? cancel,
  }) async {
    var msgs = messages;
    String last = '';
    for (var attempt = 0; attempt < jsonAttempts; attempt++) {
      last = await chat(
        msgs,
        jsonSchema: schema,
        schemaName: schemaName,
        temperature: temperature,
        maxTokens: maxTokens,
        cancel: cancel,
      );
      final obj = extractFirstJsonObject(last);
      if (obj != null) return obj;
      msgs = [
        ...messages,
        LlmMessage('assistant', last),
        LlmMessage.user('That was not valid JSON. Reply with the JSON object only.'),
      ];
    }
    throw AiBadResponseException(
      'no JSON object in the model reply: ${_clip(last)}',
    );
  }

  /// Runs one of the [ModelPrompt] tasks and returns the parsed JSON object.
  Future<Map<String, dynamic>> runPrompt(
    ModelPrompt p, {
    int? maxTokens,
    AiCancelToken? cancel,
  }) => chatJson(
    [LlmMessage.system(p.system), LlmMessage.user(p.user)],
    schema: p.schema,
    schemaName: p.schemaName,
    maxTokens: maxTokens,
    cancel: cancel,
  );

  Future<String> _chatOnce(
    List<LlmMessage> messages, {
    required Map<String, dynamic>? jsonSchema,
    required String schemaName,
    required bool useResponseFormat,
    double? temperature,
    int? maxTokens,
    AiCancelToken? cancel,
  }) async {
    final body = utf8.encode(
      jsonEncode({
        ...extraBody,
        'model': model,
        'messages': [for (final m in messages) m.toJson()],
        'stream': false,
        'temperature': temperature ?? defaultTemperature,
        'max_tokens': ?maxTokens,
        if (jsonSchema != null && useResponseFormat)
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': schemaName,
              'strict': true,
              'schema': jsonSchema,
            },
          },
      }),
    );
    final uri = Uri.parse('$baseUrl/v1/chat/completions');
    var delay = retryBaseDelay;
    for (var attempt = 0; ; attempt++) {
      try {
        final r = await aiHttpSend(
          'POST',
          uri,
          body: body,
          headers: _headers,
          timeout: requestTimeout,
          maxBytes: maxResponseBytes,
          cancel: cancel,
        );
        if (!r.ok) {
          throw AiBadResponseException(
            'HTTP ${r.status}: ${_clip(r.text)}',
            status: r.status,
          );
        }
        return _contentOf(r.text);
      } on AiException catch (e) {
        final retryable =
            e is AiUnreachableException ||
            (e is AiBadResponseException &&
                (e.status == 429 || (e.status ?? 0) >= 500));
        if (!retryable || attempt >= maxRetries) rethrow;
        await _wait(delay, cancel);
        delay = delay * 2 > maxRetryDelay ? maxRetryDelay : delay * 2;
      }
    }
  }

  Future<void> _wait(Duration d, AiCancelToken? cancel) async {
    if (d == Duration.zero) {
      if (cancel?.isCancelled ?? false) throw const AiCancelledException();
      return;
    }
    await Future<void>.delayed(d);
    if (cancel?.isCancelled ?? false) throw const AiCancelledException();
  }

  static String _contentOf(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw);
    } on FormatException {
      throw AiBadResponseException('reply is not JSON: ${_clip(raw)}');
    }
    final choices = j is Map ? j['choices'] : null;
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final msg = (choices.first as Map)['message'];
      final content = msg is Map ? msg['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content;
    }
    throw AiBadResponseException('reply has no message content: ${_clip(raw)}');
  }

  static String _clip(String s) => s.length <= 200 ? s : '${s.substring(0, 200)}...';
}
