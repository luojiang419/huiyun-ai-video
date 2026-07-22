import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_grsai_video_gen/services/api_service.dart';

void main() {
  late HttpServer server;
  late String apiUrl;
  Map<String, dynamic>? submittedBody;
  int statusRequestCount = 0;

  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6k0b8AAAAASUVORK5CYII=',
  );

  setUp(() async {
    submittedBody = null;
    statusRequestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    apiUrl = 'http://${server.address.address}:${server.port}';

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;

      if (request.method == 'POST' &&
          request.uri.path == '/api/generate/image') {
        final body = await utf8.decoder.bind(request).join();
        submittedBody = jsonDecode(body) as Map<String, dynamic>;
        request.response.write(
          jsonEncode({
            'task_id': 'task-1',
            'status': 'queued',
            'position': 0,
            'created_at': '2026-04-27T10:37:00',
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/api/task/task-1/status') {
        statusRequestCount++;
        request.response.write(
          jsonEncode({
            'task_id': 'task-1',
            'status': statusRequestCount >= 2 ? 'completed' : 'running',
            'progress': {
              'current_step': statusRequestCount >= 2 ? 35 : 12,
              'total_steps': 35,
              'percentage': statusRequestCount >= 2 ? 100.0 : 34.0,
              'eta_seconds': statusRequestCount >= 2 ? 0 : 3,
            },
            'queue_position': 0,
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/api/task/task-1/result') {
        request.response.write(
          jsonEncode({
            'video_url': '',
            'image_url': '/api/image/generated.jpg',
            'output_type': 'image',
            'seed': 123,
            'file_size': imageBytes.length,
            'error': '',
            'error_detail': '',
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/models') {
        request.response.write(
          jsonEncode({
            'models': [
              {
                'id': 'z_image_base',
                'name': 'Z-Image Base 6B',
                'type': 'image',
              },
              {
                'id': 'gemini-3-pro-image-preview',
                'name': 'Gemini 3 Pro Image Preview',
                'type': 'image',
              },
            ],
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/api/image/generated.jpg') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(imageBytes);
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'z_image_base uses wan2gp bridge image workflow and saves result',
    () async {
      final service = ApiService();
      final progresses = <GenerateProgress>[];

      await for (final progress in service.generateImage(
        apiUrl: apiUrl,
        apiKey: '',
        model: 'z_image_base',
        prompt: 'bridge smoke prompt',
        aspectRatio: '4:5',
        imageSize: '2K',
        sampleSteps: 52,
      )) {
        progresses.add(progress);
      }

      expect(submittedBody, isNotNull);
      expect(submittedBody!['task_type'], 'image');
      expect(submittedBody!['model_name'], 'z_image_base');
      expect(submittedBody!['resolution'], '1216x1536');
      expect(submittedBody!['sample_steps'], 52);
      expect(submittedBody!['guide_scale'], 4.0);
      expect(submittedBody!['shift_scale'], 6.0);
      expect(submittedBody!['sample_solver'], 'unified_2s');
      expect(submittedBody!['batch_size'], 1);

      expect(progresses, isNotEmpty);
      expect(progresses.any((item) => item.status == 'running'), isTrue);

      final succeeded = progresses.last;
      expect(succeeded.status, 'succeeded');
      expect(succeeded.results, isNotNull);
      expect(succeeded.results, hasLength(1));

      final appDir = File(Platform.resolvedExecutable).parent;
      final savedFile = File(path.join(appDir.path, succeeded.results!.single));
      final metaFile = File('${savedFile.path}.json');

      expect(await savedFile.exists(), isTrue);
      expect(await metaFile.exists(), isTrue);

      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      expect(meta['prompt'], 'bridge smoke prompt');

      await metaFile.delete();
      await savedFile.delete();
    },
  );

  test(
    'checkModelStatus reads wan2gp image models from bridge endpoint',
    () async {
      final service = ApiService();
      final isAvailable = await service.checkModelStatus(
        apiUrl,
        'z_image_base',
      );

      expect(isAvailable, isTrue);
    },
  );

  test('fetchModels falls back to bridge image model list', () async {
    final service = ApiService();
    final models = await service.fetchModels(apiUrl, '');

    expect(models, contains('z_image_base'));
    expect(models, contains('gemini-3-pro-image-preview'));
  });
}
