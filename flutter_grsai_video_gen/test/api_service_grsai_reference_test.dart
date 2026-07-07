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
    'Grsai unified image API submits references through images field',
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
      expect(submittedBody!['images'], isA<List>());
      expect(submittedBody!['images'], isNotEmpty);
      expect(
        (submittedBody!['images'] as List).single,
        startsWith('data:image/'),
      );
      expect(submittedBody!.containsKey('urls'), isFalse);

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

  test(
    'Grsai gemini image models with references use unified images API',
    () async {
      final service = ApiService();
      final progresses = <GenerateProgress>[];

      await for (final progress in service.generateImage(
        apiUrl: apiUrl,
        apiKey: 'test-key',
        model: 'gemini-3-pro-image-preview',
        prompt: 'use reference with default model',
        aspectRatio: '16:9',
        imageSize: '1K',
        urls: [referenceFile.path],
        uploadMethod: Settings.uploadMethodBase64,
      )) {
        progresses.add(progress);
      }

      expect(submittedBody, isNotNull);
      expect(submittedBody!['model'], 'gemini-3-pro-image-preview');
      expect(submittedBody!['images'], isA<List>());
      expect(submittedBody!['images'], isNotEmpty);
      expect(
        (submittedBody!['images'] as List).single,
        startsWith('data:image/'),
      );
      expect(submittedBody!.containsKey('urls'), isFalse);

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

  test(
    'Manual local reference image path submits through Grsai images API',
    () async {
      final manualReferencePath = Platform.environment['REFERENCE_IMAGE_PATH'];
      if (manualReferencePath == null ||
          manualReferencePath.trim().isEmpty ||
          !File(manualReferencePath).existsSync()) {
        markTestSkipped('Set REFERENCE_IMAGE_PATH to run this smoke test.');
        return;
      }

      final service = ApiService();
      final progresses = <GenerateProgress>[];

      await for (final progress in service.generateImage(
        apiUrl: apiUrl,
        apiKey: 'test-key',
        model: 'gemini-3-pro-image-preview',
        prompt: 'manual smoke reference image',
        aspectRatio: '16:9',
        imageSize: '1K',
        urls: [manualReferencePath],
        uploadMethod: Settings.uploadMethodBase64,
      )) {
        progresses.add(progress);
      }

      expect(submittedBody, isNotNull);
      expect(submittedBody!['images'], isA<List>());
      expect(submittedBody!['images'], hasLength(1));
      expect(
        (submittedBody!['images'] as List).single,
        startsWith('data:image/'),
      );
      expect(submittedBody!.containsKey('urls'), isFalse);

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

  test(
    'Manual relay reference image path submits through Grsai images API as URL',
    () async {
      final manualReferencePath = Platform.environment['REFERENCE_IMAGE_PATH'];
      if (manualReferencePath == null ||
          manualReferencePath.trim().isEmpty ||
          !File(manualReferencePath).existsSync()) {
        markTestSkipped('Set REFERENCE_IMAGE_PATH to run this smoke test.');
        return;
      }

      final service = ApiService();
      final progresses = <GenerateProgress>[];

      await for (final progress in service.generateImage(
        apiUrl: apiUrl,
        apiKey: 'test-key',
        model: 'nano-banana-fast',
        prompt: 'manual smoke relay reference image',
        aspectRatio: '16:9',
        imageSize: '1K',
        urls: [manualReferencePath],
        uploadMethod: Settings.uploadMethodRelayUrl,
      )) {
        progresses.add(progress);
      }

      expect(submittedBody, isNotNull);
      expect(submittedBody!['images'], isA<List>());
      expect(submittedBody!['images'], hasLength(1));
      final imageInput = (submittedBody!['images'] as List).single.toString();
      expect(
        imageInput.startsWith('http://') || imageInput.startsWith('https://'),
        isTrue,
      );
      expect(submittedBody!.containsKey('urls'), isFalse);

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

  test('Manual real Grsai reference generation', () async {
    if (Platform.environment['RUN_REAL_GRSAI_REFERENCE_TEST'] != '1') {
      markTestSkipped('Set RUN_REAL_GRSAI_REFERENCE_TEST=1 to run real API.');
      return;
    }

    final manualReferencePath = Platform.environment['REFERENCE_IMAGE_PATH'];
    final configPath = Platform.environment['REAL_GRSAI_CONFIG_PATH'];
    final outputFolder = Platform.environment['REAL_GRSAI_OUTPUT_FOLDER'];
    if (manualReferencePath == null ||
        manualReferencePath.trim().isEmpty ||
        !File(manualReferencePath).existsSync()) {
      fail('REFERENCE_IMAGE_PATH is required and must point to an image.');
    }
    if (configPath == null ||
        configPath.trim().isEmpty ||
        !File(configPath).existsSync()) {
      fail('REAL_GRSAI_CONFIG_PATH is required and must point to config.json.');
    }
    if (outputFolder == null || outputFolder.trim().isEmpty) {
      fail('REAL_GRSAI_OUTPUT_FOLDER is required.');
    }

    final config = jsonDecode(await File(configPath).readAsString()) as Map;
    final apiConfigs = (config['api_configs'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) =>
              item['type']?.toString() == 'image' &&
              item['url']?.toString().contains('grsai') == true &&
              (item['key']?.toString().trim().isNotEmpty ?? false),
        )
        .toList();
    if (apiConfigs.isEmpty) {
      fail('No Grsai image config with a key was found.');
    }
    final imageConfig = apiConfigs.firstWhere(
      (item) => item['isDefault'] == true,
      orElse: () => apiConfigs.first,
    );
    final envModel = Platform.environment['REAL_GRSAI_MODEL']?.trim() ?? '';
    final configModel = imageConfig['model']?.toString().trim() ?? '';
    final model = envModel.isNotEmpty
        ? envModel
        : configModel.isEmpty || configModel == 'gemini-3-pro-image-preview'
        ? 'nano-banana-fast'
        : configModel;
    final uploadMethodEnv =
        Platform.environment['REAL_GRSAI_UPLOAD_METHOD']?.trim() ?? '';
    final uploadMethod = uploadMethodEnv == Settings.uploadMethodRelayUrl
        ? Settings.uploadMethodRelayUrl
        : Settings.uploadMethodBase64;

    final service = ApiService();
    final progresses = <GenerateProgress>[];

    await for (final progress in service.generateImage(
      apiUrl: imageConfig['url'].toString(),
      apiKey: imageConfig['key'].toString(),
      model: model,
      prompt: '根据参考图，生成一张同一人物在城市街道旁读信的电影感写实照片。',
      aspectRatio: '16:9',
      imageSize: '1K',
      urls: [manualReferencePath],
      uploadMethod: uploadMethod,
      outputFolder: outputFolder,
    )) {
      progresses.add(progress);
      if (progress.status == 'failed') {
        fail(progress.error ?? 'real Grsai generation failed');
      }
    }

    expect(progresses, isNotEmpty);
    expect(progresses.last.status, 'succeeded');
    expect(progresses.last.results, isNotEmpty);

    final appDir = File(Platform.resolvedExecutable).parent;
    for (final resultPath in progresses.last.results!) {
      final savedFile = File(path.join(appDir.path, resultPath));
      final metaFile = File('${savedFile.path}.json');
      expect(await savedFile.exists(), isTrue);
      expect(await metaFile.exists(), isTrue);
      await metaFile.delete();
      await savedFile.delete();
    }
  });

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
