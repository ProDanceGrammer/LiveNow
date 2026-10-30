import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/domain/ai/model_prompts.dart';

import 'mock_llm_server.dart';

void main() {
  late MockLlmServer server;

  setUpAll(() => HttpOverrides.global = null);
  setUp(() async => server = await MockLlmServer.start());
  tearDown(() => server.close());

  LlmClient client({
    Duration timeout = const Duration(seconds: 5),
    int retries = 2,
    String? key,
  }) => LlmClient(
    baseUrl: '${server.url}/v1/',
    model: 'qwen-test',
    apiKey: key,
    requestTimeout: timeout,
    maxRetries: retries,
    retryBaseDelay: Duration.zero,
  );

  test('happy path: request shape, bearer token, schema response_format', () async {
    server.enqueueJson({'ok': true});
    final out = await client(key: 'tok').chatJson(
      [LlmMessage.system('s'), LlmMessage.user('u')],
      schema: {
        'type': 'object',
        'properties': {'ok': {'type': 'boolean'}},
      },
      schemaName: 'demo',
    );
    expect(out, {'ok': true});
    final req = server.chatRequests.single;
    expect(req.headers['authorization'], 'Bearer tok');
    final b = req.json;
    expect(b['model'], 'qwen-test');
    expect(b['stream'], false);
    expect(b['temperature'], lessThanOrEqualTo(0.2));
    expect(b['response_format']['type'], 'json_schema');
    expect(b['response_format']['json_schema']['name'], 'demo');
    expect((b['messages'] as List).length, 2);
  });

  test('base URL with trailing /v1/ is normalised', () {
    expect(client().baseUrl, server.url);
  });

  test('JSON is extracted from prose and a code fence', () async {
    server.enqueueContent('Sure! Here it is:\n```json\n{"a": {"b": "}"}, "c": 1}\n```\nBye');
    final out = await client().chatJson(
      [LlmMessage.user('x')],
      schema: {'type': 'object'},
    );
    expect(out, {'a': {'b': '}'}, 'c': 1});
  });

  test('bad JSON: asks once more, then fails with a typed exception', () async {
    server.enqueueContent('no json here');
    server.enqueueContent('still nothing');
    await expectLater(
      client().chatJson([LlmMessage.user('x')], schema: {'type': 'object'}),
      throwsA(isA<AiBadResponseException>()),
    );
    expect(server.chatRequests.length, 2);
  });

  test('bad JSON then good JSON on the second ask', () async {
    server.enqueueContent('oops');
    server.enqueueJson({'v': 2});
    final out = await client().chatJson(
      [LlmMessage.user('x')],
      schema: {'type': 'object'},
    );
    expect(out['v'], 2);
    final second = (server.chatRequests[1].json['messages'] as List);
    expect(second.last['content'], contains('not valid JSON'));
  });

  test('a non-JSON HTTP body is a bad response', () async {
    server.enqueue(const MockReply.raw('<html>'));
    await expectLater(
      client().chat([LlmMessage.user('x')]),
      throwsA(isA<AiBadResponseException>()),
    );
  });

  test('retries a 503 then succeeds; gives up after maxRetries', () async {
    server.enqueue(const MockReply.status(503));
    server.enqueueContent('hello');
    expect(await client().chat([LlmMessage.user('x')]), 'hello');
    expect(server.chatRequests.length, 2);

    server.requests.clear();
    for (var i = 0; i < 3; i++) {
      server.enqueue(const MockReply.status(500));
    }
    await expectLater(
      client(retries: 2).chat([LlmMessage.user('x')]),
      throwsA(isA<AiBadResponseException>().having((e) => e.status, 'status', 500)),
    );
    expect(server.chatRequests.length, 3);
  });

  test('a 4xx is not retried', () async {
    server.enqueue(const MockReply.status(401, body: 'nope'));
    await expectLater(
      client().chat([LlmMessage.user('x')]),
      throwsA(isA<AiBadResponseException>().having((e) => e.status, 'status', 401)),
    );
    expect(server.chatRequests.length, 1);
  });

  test('400 on response_format falls back to the schema in the prompt', () async {
    server.enqueue(const MockReply.status(400, body: 'response_format unsupported'));
    server.enqueueJson({'k': 1});
    final out = await client().chatJson(
      [LlmMessage.user('x')],
      schema: {'type': 'object'},
    );
    expect(out['k'], 1);
    final second = server.chatRequests[1].json;
    expect(second.containsKey('response_format'), isFalse);
    expect(jsonEncode(second['messages']), contains('schema'));
  });

  test('timeout raises AiTimeoutException and is not retried', () async {
    server.enqueue(const MockReply.content('late', delay: Duration(seconds: 3)));
    final sw = Stopwatch()..start();
    await expectLater(
      client(timeout: const Duration(milliseconds: 300)).chat([LlmMessage.user('x')]),
      throwsA(isA<AiTimeoutException>()),
    );
    expect(sw.elapsedMilliseconds, lessThan(2500));
    expect(server.chatRequests.length, 1);
  });

  test('cancel aborts a running request', () async {
    server.enqueue(const MockReply.content('late', delay: Duration(seconds: 3)));
    final token = AiCancelToken();
    final f = client().chat([LlmMessage.user('x')], cancel: token);
    final check = expectLater(f, throwsA(isA<AiCancelledException>()));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    token.cancel();
    await check;
  });

  test('unreachable server: typed exception after retries', () async {
    final c = LlmClient(
      baseUrl: 'http://127.0.0.1:1',
      model: 'm',
      maxRetries: 1,
      retryBaseDelay: Duration.zero,
    );
    await expectLater(c.chat([LlmMessage.user('x')]), throwsA(isA<AiUnreachableException>()));
  });

  test('response over the byte cap is refused', () async {
    server.enqueue(MockReply.content('x' * 5000));
    final c = LlmClient(
      baseUrl: server.url,
      model: 'm',
      maxResponseBytes: 1000,
      retryBaseDelay: Duration.zero,
    );
    await expectLater(c.chat([LlmMessage.user('x')]), throwsA(isA<AiBadResponseException>()));
  });

  test('health: /v1/models, then /api/tags, else false', () async {
    expect(await client().health(), isTrue);
    server.modelsRoute = false;
    expect(await client().health(), isTrue);
    server.tagsRoute = false;
    expect(await client().health(), isFalse);
    expect(
      await LlmClient(baseUrl: 'http://127.0.0.1:1', model: 'm').health(
        timeout: const Duration(seconds: 1),
      ),
      isFalse,
    );
  });

  test('image part is sent as a base64 data URL', () async {
    server.enqueueContent('ok');
    await client().chat([
      LlmMessage.userWithImage('look', Uint8List.fromList([1, 2, 3]), mime: 'image/png'),
    ]);
    final parts = (server.chatRequests.single.json['messages'] as List).single['content'] as List;
    expect(parts[0], {'type': 'text', 'text': 'look'});
    expect(parts[1]['image_url']['url'], 'data:image/png;base64,${base64Encode([1, 2, 3])}');
  });

  test('enum schema output: candidate choice prompt end to end', () async {
    const cands = [
      CandidateCategory(id: 'id-milk', name: 'Молоко'),
      CandidateCategory(id: 'id-cheese', name: 'Сир'),
    ];
    server.enqueueJson({'choice': 'c2', 'confidence': 0.8});
    final p = candidateChoicePrompt(itemText: 'PEYNIR 200G', candidates: cands);
    final choice = parseCandidateChoice(await client().runPrompt(p), cands);
    expect(choice.category?.id, 'id-cheese');
    final fmt = server.chatRequests.single.json['response_format']['json_schema']['schema'];
    expect(fmt['properties']['choice']['enum'], ['c1', 'c2', 'none']);
  });
}
