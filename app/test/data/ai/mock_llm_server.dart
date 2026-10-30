// Loopback mock servers for the AI client tests: an OpenAI-compatible model
// server and the OCR service. Tests must set `HttpOverrides.global = null`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final Uint8List body;

  Map<String, dynamic> get json => jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
}

/// One canned reply. [content] becomes `choices[0].message.content`.
class MockReply {
  const MockReply.content(String this.content, {this.delay = Duration.zero})
    : status = 200,
      rawBody = null;
  const MockReply.status(this.status, {String? body, this.delay = Duration.zero})
    : content = null,
      rawBody = body;
  const MockReply.raw(String this.rawBody, {this.delay = Duration.zero})
    : status = 200,
      content = null;

  final int status;
  final String? content;
  final String? rawBody;
  final Duration delay;
}

class MockLlmServer {
  MockLlmServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<RecordedRequest> requests = [];
  final List<MockReply> _queue = [];

  /// Whether /v1/models answers 200 (false -> 404, and /api/tags answers).
  bool modelsRoute = true;
  bool tagsRoute = true;

  static Future<MockLlmServer> start() async =>
      MockLlmServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'http://127.0.0.1:${_server.port}';

  List<RecordedRequest> get chatRequests =>
      requests.where((r) => r.path == '/v1/chat/completions').toList();

  void enqueue(MockReply r) => _queue.add(r);
  void enqueueContent(String content) => _queue.add(MockReply.content(content));
  void enqueueJson(Object json) => enqueueContent(jsonEncode(json));

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await req.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    final rec = RecordedRequest(req.method, req.uri.path, headers, body.takeBytes());
    requests.add(rec);
    final res = req.response;
    try {
      if (req.uri.path == '/v1/models') {
        res.statusCode = modelsRoute ? 200 : 404;
        if (modelsRoute) res.write(jsonEncode({'data': [{'id': 'mock'}]}));
      } else if (req.uri.path == '/api/tags') {
        res.statusCode = tagsRoute ? 200 : 404;
        if (tagsRoute) res.write(jsonEncode({'models': []}));
      } else if (req.uri.path == '/v1/chat/completions') {
        if (_queue.isEmpty) {
          res.statusCode = 500;
          res.write('queue empty');
        } else {
          final r = _queue.removeAt(0);
          if (r.delay > Duration.zero) await Future<void>.delayed(r.delay);
          res.statusCode = r.status;
          if (r.content != null) {
            res.write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': r.content},
                  },
                ],
              }),
            );
          } else if (r.rawBody != null) {
            res.write(r.rawBody);
          }
        }
      } else {
        res.statusCode = 404;
      }
    } on Object {
      // the client gave up (timeout test): nothing to answer
    }
    try {
      await res.close();
    } on Object {
      // connection already closed
    }
  }
}

class MockOcrServer {
  MockOcrServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<RecordedRequest> requests = [];

  /// The JSON returned by POST /ocr.
  Object reply = {
    'engine': 'mock',
    'width': 100,
    'height': 200,
    'lines': <Object>[],
  };
  int status = 200;

  static Future<MockOcrServer> start() async =>
      MockOcrServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await req.fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    requests.add(RecordedRequest(req.method, req.uri.path, headers, body.takeBytes()));
    final res = req.response;
    if (req.uri.path == '/health') {
      res.write('{"ok":true}');
    } else if (req.uri.path == '/ocr') {
      res.statusCode = status;
      res.write(status == 200 ? jsonEncode(reply) : 'error');
    } else {
      res.statusCode = 404;
    }
    await res.close();
  }
}

/// OCR reply helper: one printed row per entry.
Map<String, Object> ocrReply(List<String> rows) => {
  'engine': 'mock',
  'width': 800,
  'height': 1600,
  'lines': [
    for (var i = 0; i < rows.length; i++)
      {
        'text': rows[i],
        'box': [10, 20 + i * 30, 700, 40 + i * 30],
        'confidence': 0.95,
      },
  ],
};
