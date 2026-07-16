import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';
import 'package:flutter_grsai_video_gen/models/update_install_session.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('inno installer exposes real silent install progress contract', () {
    final installerScript = File(
      path.join(Directory.current.path, 'windows', 'installer.iss'),
    ).readAsStringSync();

    expect(installerScript, contains('CurInstallProgressChanged'));
    expect(installerScript, contains("{param:UPDATEPROGRESS|}"));
    expect(installerScript, contains('WriteUpdateProgress(100)'));
    expect(installerScript, contains("UpdateProgressFilePath + '.tmp'"));
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

  test(
    'checks latest manifest from server when json contains utf8 bom',
    () async {
      final bytes = utf8.encode('installer-body');
      final hash = sha256.convert(bytes).toString().toUpperCase();
      final server = await _serve((request) async {
        if (request.uri.path == '/update.json') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '\uFEFF${jsonEncode({'version': 'V6.9', 'installerName': '影视版-安装包-V6.9.exe', 'installerUrl': 'http://127.0.0.1:${request.connectionInfo!.localPort}/installer.exe', 'sha256': hash, 'size': bytes.length, 'publishedAt': '2026-06-14T00:00:00Z', 'releaseNotes': '测试发布', 'mandatory': false})}',
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
    },
  );

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

  test(
    'launchSilentUpdateAndExit starts downloaded installer package and exits',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final appDir = Directory(path.join(tempDir.path, 'app'));
      await appDir.create(recursive: true);
      final exeFile = File(
        path.join(appDir.path, 'flutter_grsai_image_gen.exe'),
      );
      await exeFile.writeAsString('exe');

      final installerFile = File(path.join(tempDir.path, 'installer.exe'));
      await installerFile.writeAsBytes(utf8.encode('installer-body'));
      final installerHash = await UpdateService.calculateSha256(
        installerFile.path,
      );

      String? launchedExecutable;
      List<String>? launchedArguments;
      ProcessStartMode? launchedMode;
      bool? launchedRunInShell;
      int? exitCode;

      final service = UpdateService(
        appDirectory: appDir.path,
        resolvedExecutableProvider: () => exeFile.path,
        isWindowsProvider: () => true,
        installedAppDirsLoader: () async => const [],
        exitHandler: (code) => exitCode = code,
        processStarter:
            (
              executable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async {
              launchedExecutable = executable;
              launchedArguments = List<String>.from(arguments);
              launchedMode = mode;
              launchedRunInShell = runInShell;
              return Process.start('cmd.exe', const ['/c', 'exit', '0']);
            },
      );

      final pendingJob = PendingUpdateJob(
        info: _info(
          installerUrl: 'https://example.com/installer.exe',
          sha256: installerHash,
          size: await installerFile.length(),
        ),
        installerPath: installerFile.path,
        sha256: installerHash,
        downloadedAt: '2026-06-27T00:00:00Z',
      );

      await service.launchSilentUpdateAndExit(job: pendingJob);

      expect(exitCode, 0);
      expect(path.basename(launchedExecutable!), path.basename(exeFile.path));
      expect(
        launchedExecutable,
        contains('${path.separator}staging${path.separator}'),
      );
      expect(launchedMode, ProcessStartMode.detached);
      expect(launchedRunInShell, isFalse);
      expect(launchedArguments, isNotNull);
      final launchArgs = UpdateInstallSessionLaunchArgs.tryParse(
        launchedArguments!,
      );
      expect(launchArgs, isNotNull);
      final session = await service.loadInstallSession(
        sessionFilePath: launchArgs!.sessionFilePath,
      );
      expect(session, isNotNull);
      expect(session!.targetVersion, 'V6.9');
      expect(session.installerPath, installerFile.path);
      expect(session.installDir, appDir.path);
      expect(session.status, UpdateInstallSessionStatus.launching);
      expect(session.progressFilePath, endsWith('-progress.json'));
      expect(File(session.stagedExecutablePath).existsSync(), isTrue);
      expect(
        session.stagedExecutablePath,
        contains('${path.separator}staging${path.separator}'),
      );

      final pendingJson =
          jsonDecode(await File(service.pendingUpdateFilePath).readAsString())
              as Map<String, dynamic>;
      expect(pendingJson['targetVersion'], 'V6.9');
      expect(pendingJson['installerPath'], installerFile.path);
      expect(pendingJson['status'], PendingUpdateStatus.installing.value);
      expect(Directory(service.stagingDirectoryPath).existsSync(), isTrue);
    },
  );

  test(
    'launchSilentUpdateAndExit mirrors pending file to formal install directory',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final snapshotAppDir = Directory(
        path.join(tempDir.path, '实测输出', 'sandbox-install'),
      );
      await snapshotAppDir.create(recursive: true);
      final snapshotExe = File(
        path.join(snapshotAppDir.path, 'flutter_grsai_image_gen.exe'),
      );
      await snapshotExe.writeAsString('snapshot-exe');

      final formalInstallDir = Directory(
        path.join(tempDir.path, 'Program Files', 'VideoGen'),
      );
      await formalInstallDir.create(recursive: true);
      await File(
        path.join(formalInstallDir.path, 'flutter_grsai_image_gen.exe'),
      ).writeAsString('formal-exe');

      final installerFile = File(path.join(tempDir.path, 'installer.exe'));
      await installerFile.writeAsBytes(utf8.encode('installer-body'));
      final installerHash = await UpdateService.calculateSha256(
        installerFile.path,
      );

      String? launchedExecutable;
      List<String>? launchedArguments;

      final service = UpdateService(
        appDirectory: snapshotAppDir.path,
        resolvedExecutableProvider: () => snapshotExe.path,
        isWindowsProvider: () => true,
        installedAppDirsLoader: () async => [formalInstallDir.path],
        exitHandler: (_) {},
        processStarter:
            (
              executable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async {
              launchedExecutable = executable;
              launchedArguments = List<String>.from(arguments);
              return Process.start('cmd.exe', const ['/c', 'exit', '0']);
            },
      );

      final pendingJob = PendingUpdateJob(
        info: _info(
          installerUrl: 'https://example.com/installer.exe',
          sha256: installerHash,
          size: await installerFile.length(),
          version: 'V9.0',
        ),
        installerPath: installerFile.path,
        sha256: installerHash,
        downloadedAt: '2026-06-29T00:00:00Z',
      );

      await service.launchSilentUpdateAndExit(job: pendingJob);

      expect(
        path.basename(launchedExecutable!),
        path.basename(snapshotExe.path),
      );
      expect(
        launchedExecutable,
        contains('${path.separator}staging${path.separator}'),
      );
      expect(launchedArguments, isNotNull);
      final launchArgs = UpdateInstallSessionLaunchArgs.tryParse(
        launchedArguments!,
      );
      expect(launchArgs, isNotNull);
      final session = await service.loadInstallSession(
        sessionFilePath: launchArgs!.sessionFilePath,
      );
      expect(session, isNotNull);
      expect(session!.installDir, formalInstallDir.path);
      expect(
        session.targetExecutablePath,
        path.join(formalInstallDir.path, 'flutter_grsai_image_gen.exe'),
      );
      expect(
        session.sourcePendingUpdateFilePath,
        service.pendingUpdateFilePath,
      );
      expect(File(session.stagedExecutablePath).existsSync(), isTrue);

      final mirroredPendingFile = File(
        path.join(
          formalInstallDir.path,
          'data',
          '.system_update',
          'pending_update.json',
        ),
      );
      expect(mirroredPendingFile.existsSync(), isTrue);
      final mirroredPendingJson =
          jsonDecode(await mirroredPendingFile.readAsString())
              as Map<String, dynamic>;
      expect(mirroredPendingJson['targetVersion'], 'V9.0');
      expect(mirroredPendingJson['installerPath'], installerFile.path);
      expect(
        mirroredPendingJson['status'],
        PendingUpdateStatus.installing.value,
      );
      final snapshotPendingFile = File(
        path.join(
          snapshotAppDir.path,
          'data',
          '.system_update',
          'pending_update.json',
        ),
      );
      expect(snapshotPendingFile.existsSync(), isTrue);
      final snapshotPendingJson =
          jsonDecode(await snapshotPendingFile.readAsString())
              as Map<String, dynamic>;
      expect(snapshotPendingJson['targetVersion'], 'V9.0');
      expect(snapshotPendingJson['installerPath'], installerFile.path);
      expect(
        snapshotPendingJson['status'],
        PendingUpdateStatus.installing.value,
      );
      expect(File(launchArgs.sessionFilePath).existsSync(), isTrue);
    },
  );

  test(
    'runDetachedInstallSession uses storyboard style silent installer and relaunches once',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final appDir = Directory(path.join(tempDir.path, 'app'));
      await appDir.create(recursive: true);
      final executable = File(
        path.join(appDir.path, 'flutter_grsai_image_gen.exe'),
      );
      await executable.writeAsString('new-exe');
      final installer = File(path.join(tempDir.path, 'installer.exe'));
      await installer.writeAsString('installer-body');
      final installerHash = await UpdateService.calculateSha256(installer.path);

      final launches =
          <
            ({
              String executable,
              List<String> arguments,
              ProcessStartMode mode,
              bool runInShell,
            })
          >[];
      final service = UpdateService(
        appDirectory: appDir.path,
        resolvedExecutableProvider: () => executable.path,
        isWindowsProvider: () => true,
        processStarter:
            (
              launchedExecutable,
              arguments, {
              mode = ProcessStartMode.normal,
              runInShell = false,
            }) async {
              launches.add((
                executable: launchedExecutable,
                arguments: List<String>.from(arguments),
                mode: mode,
                runInShell: runInShell,
              ));
              return Process.start('cmd.exe', const ['/c', 'exit', '0']);
            },
      );
      final session =
          _session(
            service: service,
            sessionId: 'storyboard-style-install',
            targetVersion: 'V10.0.5',
          ).copyWith(
            installerPath: installer.path,
            installerSha256: installerHash,
            parentPid: 0,
            status: UpdateInstallSessionStatus.prepared,
          );
      await service.saveInstallSession(session);
      final progress = <UpdateInstallProgress>[];

      await service.runDetachedInstallSession(
        sessionFilePath: path.join(
          service.jobsDirectoryPath,
          '${session.sessionId}.json',
        ),
        expectedSessionId: session.sessionId,
        onProgress: (_, event) => progress.add(event),
      );

      expect(launches, hasLength(2));
      expect(launches.first.executable, 'powershell.exe');
      expect(launches.first.mode, ProcessStartMode.normal);
      expect(launches.first.runInShell, isFalse);
      expect(launches.first.arguments, contains('Hidden'));
      final fileIndex = launches.first.arguments.indexOf('-File');
      expect(fileIndex, greaterThanOrEqualTo(0));
      final scriptFile = File(launches.first.arguments[fileIndex + 1]);
      expect(scriptFile.existsSync(), isTrue);
      await _expectUtf8Bom(scriptFile);
      final script = await scriptFile.readAsString();
      expect(script, contains('/SP-'));
      expect(script, contains('/VERYSILENT'));
      expect(script, contains('/SUPPRESSMSGBOXES'));
      expect(script, contains('/NORESTART'));
      expect(script, contains('/NOCANCEL'));
      expect(script, contains('/FORCECLOSEAPPLICATIONS'));
      expect(script, contains('/UPDATEPROGRESS='));
      expect(script, contains('storyboard-style-install-progress.json'));
      expect(script, contains('-Verb RunAs -Wait -PassThru'));
      expect(launches.last.executable, executable.path);
      expect(launches.last.mode, ProcessStartMode.detached);
      expect(launches.last.arguments, isEmpty);
      final completed = await service.loadInstallSession(
        sessionFilePath: path.join(
          service.jobsDirectoryPath,
          '${session.sessionId}.json',
        ),
      );
      expect(completed!.status, UpdateInstallSessionStatus.completed);
      expect(progress.last.message, contains('新版本已启动'));
      expect(progress.last.percentage, 100);
      for (var index = 1; index < progress.length; index++) {
        expect(
          progress[index].percentage,
          greaterThanOrEqualTo(progress[index - 1].percentage),
        );
      }
    },
  );

  test(
    'acknowledgeCompletedUpdateOnStartup writes ack and cleans completed session',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final appDir = Directory(path.join(tempDir.path, 'app'));
      await appDir.create(recursive: true);
      final currentExePath = path.join(
        appDir.path,
        'flutter_grsai_image_gen.exe',
      );
      final service = UpdateService(
        appDirectory: appDir.path,
        resolvedExecutableProvider: () => currentExePath,
        isWindowsProvider: () => true,
      );

      final session = _session(
        service: service,
        sessionId: 'session-ack',
        targetVersion: 'V9.0',
      );
      await Directory(
        path.dirname(session.stagedRuntimeDir),
      ).create(recursive: true);
      await File(
        path.join(path.dirname(session.stagedRuntimeDir), 'runner.txt'),
      ).writeAsString('staged');
      await service.saveInstallSession(session);
      await File(session.resultFilePath).create(recursive: true);
      await File(session.resultFilePath).writeAsString(
        jsonEncode({'sessionId': session.sessionId, 'status': 'completed'}),
      );

      final pending = PendingUpdateJob(
        info: _info(
          installerUrl: 'https://example.com/installer.exe',
          sha256: 'ABC123',
          size: 1024,
          version: 'V9.0',
        ),
        installerPath: path.join(tempDir.path, 'installer.exe'),
        sha256: 'ABC123',
        downloadedAt: '2026-06-29T00:00:00Z',
        status: PendingUpdateStatus.installing,
      );
      await service.savePendingUpdate(pending);

      await service.acknowledgeCompletedUpdateOnStartup(currentVersion: 'V9.0');

      final ackJson =
          jsonDecode(await File(session.ackFilePath).readAsString())
              as Map<String, dynamic>;
      expect(ackJson['sessionId'], session.sessionId);
      expect(ackJson['status'], 'acknowledged');
      expect(ackJson['currentVersion'], 'V9.0');
      expect(ackJson['executablePath'], currentExePath);

      final resultJson =
          jsonDecode(await File(session.resultFilePath).readAsString())
              as Map<String, dynamic>;
      expect(resultJson['status'], 'acknowledged');
      expect(resultJson['acknowledgedVersion'], 'V9.0');
      expect(resultJson['acknowledgedExecutablePath'], currentExePath);

      expect(File(service.pendingUpdateFilePath).existsSync(), isFalse);
      expect(
        File(
          path.join(service.jobsDirectoryPath, '${session.sessionId}.json'),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(path.dirname(session.stagedRuntimeDir)).existsSync(),
        isFalse,
      );
      expect(File(session.logFilePath).existsSync(), isTrue);
      expect(
        await File(session.logFilePath).readAsString(),
        contains('检测到新版本启动确认'),
      );
    },
  );

  test(
    'acknowledgeCompletedUpdateOnStartup skips session when current version is still older',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final appDir = Directory(path.join(tempDir.path, 'app'));
      await appDir.create(recursive: true);
      final service = UpdateService(
        appDirectory: appDir.path,
        resolvedExecutableProvider: () => path.join(appDir.path, 'app.exe'),
        isWindowsProvider: () => true,
      );

      final session = _session(
        service: service,
        sessionId: 'session-future',
        targetVersion: 'V9.1',
      );
      await Directory(
        path.dirname(session.stagedRuntimeDir),
      ).create(recursive: true);
      await service.saveInstallSession(session);

      final pending = PendingUpdateJob(
        info: _info(
          installerUrl: 'https://example.com/installer.exe',
          sha256: 'DEF456',
          size: 2048,
          version: 'V9.1',
        ),
        installerPath: path.join(tempDir.path, 'installer-future.exe'),
        sha256: 'DEF456',
        downloadedAt: '2026-06-29T00:00:00Z',
        status: PendingUpdateStatus.installing,
      );
      await service.savePendingUpdate(pending);

      await service.acknowledgeCompletedUpdateOnStartup(currentVersion: 'V9.0');

      expect(File(session.ackFilePath).existsSync(), isFalse);
      expect(
        File(
          path.join(service.jobsDirectoryPath, '${session.sessionId}.json'),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(path.dirname(session.stagedRuntimeDir)).existsSync(),
        isTrue,
      );
      expect(File(service.pendingUpdateFilePath).existsSync(), isTrue);
    },
  );

  test(
    'acknowledgeCompletedUpdateOnStartup clears mirrored source pending file',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('update_service_');
      addTearDown(() => tempDir.delete(recursive: true));

      final sourceAppDir = Directory(
        path.join(tempDir.path, '实测输出', 'sandbox-install'),
      );
      await sourceAppDir.create(recursive: true);
      final formalAppDir = Directory(
        path.join(tempDir.path, 'Program Files', 'VideoGen'),
      );
      await formalAppDir.create(recursive: true);

      final service = UpdateService(
        appDirectory: formalAppDir.path,
        resolvedExecutableProvider: () =>
            path.join(formalAppDir.path, 'flutter_grsai_image_gen.exe'),
        isWindowsProvider: () => true,
      );

      final sourcePendingFile = File(
        path.join(
          sourceAppDir.path,
          'data',
          '.system_update',
          'pending_update.json',
        ),
      );
      await sourcePendingFile.create(recursive: true);
      await sourcePendingFile.writeAsString(
        jsonEncode({'targetVersion': 'V9.0', 'status': 'installing'}),
      );

      final session = _session(
        service: service,
        sessionId: 'session-mirrored-pending',
        targetVersion: 'V9.0',
        sourcePendingUpdateFilePath: sourcePendingFile.path,
      );
      await Directory(
        path.dirname(session.stagedRuntimeDir),
      ).create(recursive: true);
      await service.saveInstallSession(session);
      await File(session.resultFilePath).create(recursive: true);
      await File(session.resultFilePath).writeAsString(
        jsonEncode({'sessionId': session.sessionId, 'status': 'completed'}),
      );

      final targetPending = PendingUpdateJob(
        info: _info(
          installerUrl: 'https://example.com/installer.exe',
          sha256: 'ABC123',
          size: 1024,
          version: 'V9.0',
        ),
        installerPath: path.join(tempDir.path, 'installer.exe'),
        sha256: 'ABC123',
        downloadedAt: '2026-06-29T00:00:00Z',
        status: PendingUpdateStatus.installing,
      );
      await service.savePendingUpdate(targetPending);

      await service.acknowledgeCompletedUpdateOnStartup(currentVersion: 'V9.0');

      expect(sourcePendingFile.existsSync(), isFalse);
      expect(File(service.pendingUpdateFilePath).existsSync(), isFalse);
    },
  );
}

Future<void> _expectUtf8Bom(File file) async {
  final bytes = await file.openRead(0, 3).first;
  expect(bytes, [0xEF, 0xBB, 0xBF]);
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
  String version = 'V6.9',
}) {
  return UpdateInfo(
    version: version,
    installerName: '影视版-安装包-$version.exe',
    installerUrl: installerUrl,
    sha256: sha256,
    size: size,
    publishedAt: '2026-06-14T00:00:00Z',
    releaseNotes: '测试发布',
    mandatory: false,
  );
}

UpdateInstallSession _session({
  required UpdateService service,
  required String sessionId,
  required String targetVersion,
  String? sourcePendingUpdateFilePath,
}) {
  final stagedRuntimeDir = path.join(
    service.stagingDirectoryPath,
    sessionId,
    'runtime',
  );
  return UpdateInstallSession(
    sessionId: sessionId,
    targetVersion: targetVersion,
    installerPath: path.join(
      service.downloadsDirectoryPath,
      '$targetVersion.exe',
    ),
    installerSha256: 'ABC123',
    installDir: service.appDirectory,
    executableName: 'flutter_grsai_image_gen.exe',
    targetExecutablePath: path.join(
      service.appDirectory,
      'flutter_grsai_image_gen.exe',
    ),
    stagedRuntimeDir: stagedRuntimeDir,
    stagedExecutablePath: path.join(
      stagedRuntimeDir,
      'flutter_grsai_image_gen.exe',
    ),
    pendingUpdateFilePath: service.pendingUpdateFilePath,
    sourcePendingUpdateFilePath:
        sourcePendingUpdateFilePath ?? service.pendingUpdateFilePath,
    resultFilePath: path.join(service.resultsDirectoryPath, '$sessionId.json'),
    ackFilePath: path.join(service.acksDirectoryPath, '$sessionId.ack'),
    logFilePath: path.join(service.logsDirectoryPath, '$sessionId.log'),
    createdAt: '2026-06-29T00:00:00Z',
    parentPid: 1234,
    status: UpdateInstallSessionStatus.completed,
  );
}
