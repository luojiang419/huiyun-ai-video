import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('checks latest manifest from server', () async {
    final bytes = utf8.encode('installer-body');
    final hash = sha256.convert(bytes).toString().toUpperCase();
    final server = await _serve((request) async {
      if (request.uri.path == '/update.json') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'version': 'V6.9',
            'installerName': '影视版-安装包-V6.9.exe',
            'installerUrl':
                'http://127.0.0.1:${request.connectionInfo!.localPort}/installer.exe',
            'sha256': hash,
            'size': bytes.length,
            'publishedAt': '2026-06-14T00:00:00Z',
            'releaseNotes': '测试发布',
            'mandatory': false,
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final tempDir = await Directory.systemTemp.createTemp('update_service_');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = UpdateService(
      updateJsonUrl: 'http://127.0.0.1:${server.port}/update.json',
      appDirectory: tempDir.path,
    );

    final info = await service.checkForUpdate(currentVersion: 'V6.8');
    expect(info, isNotNull);
    expect(info!.version, 'V6.9');
  });

  test('throws when installer hash does not match', () async {
    final bytes = utf8.encode('installer-body');
    final server = await _serve((request) async {
      if (request.uri.path == '/installer.exe') {
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final tempDir = await Directory.systemTemp.createTemp('update_service_');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = UpdateService(appDirectory: tempDir.path);
    final info = _info(
      installerUrl: 'http://127.0.0.1:${server.port}/installer.exe',
      sha256: '000000',
      size: bytes.length,
    );

    expect(
      () => service.downloadInstaller(info),
      throwsA(isA<UpdateException>()),
    );
  });

  test('throws when installer download fails', () async {
    final server = await _serve((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final tempDir = await Directory.systemTemp.createTemp('update_service_');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = UpdateService(appDirectory: tempDir.path);
    final info = _info(
      installerUrl: 'http://127.0.0.1:${server.port}/installer.exe',
      sha256: '000000',
      size: 1,
    );

    expect(
      () => service.downloadInstaller(info),
      throwsA(isA<UpdateException>()),
    );
  });
}

Future<HttpServer> _serve(Future<void> Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

UpdateInfo _info({
  required String installerUrl,
  required String sha256,
  required int size,
}) {
  return UpdateInfo(
    version: 'V6.9',
    installerName: '影视版-安装包-V6.9.exe',
    installerUrl: installerUrl,
    sha256: sha256,
    size: size,
    publishedAt: '2026-06-14T00:00:00Z',
    releaseNotes: '测试发布',
    mandatory: false,
  );
}
