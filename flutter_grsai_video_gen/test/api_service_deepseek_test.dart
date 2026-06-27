import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/services/api_service.dart';

void main() {
  group('DeepSeek OpenAI compatible model normalization', () {
    test('strips 1M suffix from DeepSeek V4 model aliases', () {
      expect(
        ApiService.normalizeOpenAiCompatibleModel(
          apiUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-flash[1M]',
        ),
        'deepseek-v4-flash',
      );
      expect(
        ApiService.normalizeOpenAiCompatibleModel(
          apiUrl: 'https://api.deepseek.com/v1/chat/completions',
          model: 'deepseek-v4-pro[1m]',
        ),
        'deepseek-v4-pro',
      );
    });

    test('keeps official DeepSeek model names unchanged', () {
      expect(
        ApiService.normalizeOpenAiCompatibleModel(
          apiUrl: 'https://api.deepseek.com',
          model: 'deepseek-v4-flash',
        ),
        'deepseek-v4-flash',
      );
    });

    test('does not rewrite aliases for non-DeepSeek endpoints', () {
      expect(
        ApiService.normalizeOpenAiCompatibleModel(
          apiUrl: 'https://example.com',
          model: 'deepseek-v4-flash[1M]',
        ),
        'deepseek-v4-flash[1M]',
      );
    });

    test('can request JSON object response for structured chat', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? submittedBody;

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final body = await utf8.decoder.bind(request).join();
        submittedBody = jsonDecode(body) as Map<String, dynamic>;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"assets":[]}'},
              },
            ],
          }),
        );
        await request.response.close();
      });

      try {
        final apiOrigin = 'http://${server.address.address}:${server.port}';
        final content = await ApiService().chat(
          apiUrl: apiOrigin,
          apiKey: 'test-key',
          model: 'deepseek-v4-flash',
          systemPrompt: '只返回 JSON',
          jsonObjectResponse: true,
          messages: const [
            {'role': 'user', 'content': '提取资产'},
          ],
        );

        expect(content, '{"assets":[]}');
        expect(submittedBody, isNotNull);
        expect(submittedBody!['model'], 'deepseek-v4-flash');
        expect(submittedBody!['response_format'], {'type': 'json_object'});
        expect(submittedBody!['stream'], isNull);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
