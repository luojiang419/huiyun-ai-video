import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_grsai_video_gen/models/settings.dart';
import 'package:flutter_grsai_video_gen/services/api_service.dart';

void main() {
  late HttpServer server;
  late String apiOrigin;
  late String apiUrl;
  late Directory tempDir;
  late File referenceFile;
  Map<String, dynamic>? submittedBody;

  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );

  setUp(() async {
    submittedBody = null;
    tempDir = await Directory.systemTemp.createTemp('grsai_ref_test_');
    referenceFile = File(path.join(tempDir.path, 'reference.png'));
    await referenceFile.writeAsBytes(imageBytes);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    apiOrigin = 'http://${server.address.address}:${server.port}';
    apiUrl = '$apiOrigin/v1/api/generate';

    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/v1/api/generate') {
        request.response.headers.contentType = ContentType.json;
        final body = await utf8.decoder.bind(request).join();
        submittedBody = jsonDecode(body) as Map<String, dynamic>;

        if (submittedBody!['prompt'] == 'fail') {
          request.response.write(
            jsonEncode({
              'id': 'task-failed',
              'status': 'failed',
              'failure_reason': 'error',
              'error': 'reference image url invalid',
            }),
          );
          await request.response.close();
          return;
        }

        request.response.write(
          jsonEncode({
            'id': 'task-1',
            'status': 'succeeded',
            'progress': 100,
            'results': [
              {'url': '$apiOrigin/v1/api/generated.png'},
            ],
          }),
        );
        await request.response.close();
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/v1/api/generated.png') {
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Grsai unified image API submits references through urls field',
    () async {
      final service = ApiService();
      final progresses = <GenerateProgress>[];

      await for (final progress in service.generateImage(
        apiUrl: apiUrl,
        apiKey: 'test-key',
        model: 'nano-banana-fast',
        prompt: 'use reference',
        aspectRatio: '16:9',
        imageSize: '1K',
        urls: [referenceFile.path],
        uploadMethod: Settings.uploadMethodBase64,
      )) {
        progresses.add(progress);
      }

      expect(submittedBody, isNotNull);
      expect(submittedBody!['urls'], isA<List>());
      expect(submittedBody!['urls'], isNotEmpty);
      expect(
        (submittedBody!['urls'] as List).single,
        startsWith('data:image/'),
      );
      expect(submittedBody!.containsKey('images'), isFalse);

      final succeeded = progresses.last;
      expect(succeeded.status, 'succeeded');
      expect(succeeded.results, hasLength(1));

      final appDir = File(Platform.resolvedExecutable).parent;
      final savedFile = File(path.join(appDir.path, succeeded.results!.single));
      final metaFile = File('${savedFile.path}.json');

      expect(await savedFile.exists(), isTrue);
      expect(await metaFile.exists(), isTrue);

      await metaFile.delete();
      await savedFile.delete();
    },
  );

  test('Grsai unified image API keeps detailed failure message', () async {
    final service = ApiService();
    final progresses = <GenerateProgress>[];

    await for (final progress in service.generateImage(
      apiUrl: apiUrl,
      apiKey: 'test-key',
      model: 'nano-banana-fast',
      prompt: 'fail',
      aspectRatio: '16:9',
      imageSize: '1K',
      urls: [referenceFile.path],
      uploadMethod: Settings.uploadMethodBase64,
    )) {
      progresses.add(progress);
    }

    expect(progresses.last.status, 'failed');
    expect(progresses.last.error, 'reference image url invalid');
  });
}
