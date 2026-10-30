/// One small HTTP helper for the hub's local AI services (the OpenAI-compatible
/// model server and the OCR service). Plain `dart:io` `HttpClient`, a fresh
/// client per call that is always closed, an overall deadline (CPU inference
/// takes minutes, so callers pass generous ones), cooperative cancellation and a
/// byte cap on the buffered reply. NOT the sync transport.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Base of every failure the AI clients raise.
sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The service could not be reached (refused, DNS, reset).
class AiUnreachableException extends AiException {
  const AiUnreachableException(super.message);
}

/// The overall deadline passed before a full reply arrived.
class AiTimeoutException extends AiException {
  const AiTimeoutException(super.message);
}

/// The service answered, but not with something usable (HTTP error, bad JSON,
/// oversized or empty reply). [status] is the HTTP status when there was one.
class AiBadResponseException extends AiException {
  const AiBadResponseException(super.message, {this.status});
  final int? status;
}

/// The caller cancelled through its [AiCancelToken].
class AiCancelledException extends AiException {
  const AiCancelledException([super.message = 'cancelled']);
}

/// Lets a caller abort a running request (for example when a job is cancelled).
class AiCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

class AiHttpResponse {
  const AiHttpResponse(this.status, this.bytes);
  final int status;
  final Uint8List bytes;

  bool get ok => status >= 200 && status < 300;
  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// Sends one request and buffers the whole reply (at most [maxBytes]).
/// Throws only [AiException] subtypes. An HTTP error status is NOT an
/// exception here: the caller decides (it may retry a 5xx, read a 400 body).
Future<AiHttpResponse> aiHttpSend(
  String method,
  Uri uri, {
  List<int>? body,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(minutes: 10),
  Duration connectTimeout = const Duration(seconds: 10),
  int maxBytes = 8 * 1024 * 1024,
  AiCancelToken? cancel,
}) async {
  if (cancel?.isCancelled ?? false) throw const AiCancelledException();
  final client = HttpClient()..connectionTimeout = connectTimeout;
  var timedOut = false;
  final timer = Timer(timeout, () {
    timedOut = true;
    client.close(force: true);
  });
  cancel?._onCancel = () => client.close(force: true);
  try {
    final req = await client.openUrl(method, uri);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    final out = BytesBuilder(copy: false);
    await for (final chunk in res) {
      out.add(chunk);
      if (out.length > maxBytes) {
        throw AiBadResponseException(
          'reply larger than ${maxBytes ~/ 1024} KB',
          status: res.statusCode,
        );
      }
    }
    return AiHttpResponse(res.statusCode, out.takeBytes());
  } on AiException {
    rethrow;
  } on Object catch (e) {
    if (cancel?.isCancelled ?? false) throw const AiCancelledException();
    if (timedOut) {
      throw AiTimeoutException('no complete reply within ${timeout.inSeconds} s');
    }
    if (e is TimeoutException) {
      throw AiUnreachableException('could not connect to $uri');
    }
    throw AiUnreachableException('$uri: $e');
  } finally {
    timer.cancel();
    cancel?._onCancel = null;
    client.close(force: true);
  }
}

/// Finds the first balanced `{...}` object in [text] (a model may wrap its JSON
/// in prose or a code fence) and decodes it; null when there is none.
Map<String, dynamic>? extractFirstJsonObject(String text) {
  var start = text.indexOf('{');
  while (start >= 0) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final v = jsonDecode(text.substring(start, i + 1));
            if (v is Map) return Map<String, dynamic>.from(v);
          } on FormatException {
            // not JSON after all: try the next '{'
          }
          break;
        }
      }
    }
    start = text.indexOf('{', start + 1);
  }
  return null;
}
