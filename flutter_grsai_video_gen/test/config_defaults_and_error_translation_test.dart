import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/services/config_file_service.dart';
import 'package:flutter_grsai_video_gen/utils/error_translator.dart';

void main() {
  group('ConfigFileService bundled defaults', () {
    test('fills empty api config list from bundled defaults', () {
      final merged = ConfigFileService.mergeConfigWithBundledDefaults(
        {'api_key': '', 'api_configs': <Map<String, dynamic>>[]},
        {
          'api_key': 'sk-default',
          'api_configs': [
            {
              'id': 'builtin-grsai-image',
              'name': 'Grsai图片生成',
              'type': 'image',
              'url': 'https://grsai.dakka.com.cn',
              'key': 'sk-default',
              'model': 'gemini-3-pro-image-preview',
            },
          ],
        },
      );

      expect(merged['api_key'], 'sk-default');
      expect(merged['api_configs'], isA<List>());
      expect(merged['api_configs'], hasLength(1));
      expect(merged['api_configs'][0]['key'], 'sk-default');
    });

    test('keeps user api config values when they are already set', () {
      final merged = ConfigFileService.mergeConfigWithBundledDefaults(
        {
          'api_configs': [
            {
              'id': 'builtin-grsai-image',
              'name': 'User Grsai',
              'type': 'image',
              'url': 'https://custom.example.com',
              'key': 'sk-user',
              'model': 'nano-banana-fast',
            },
          ],
        },
        {
          'api_configs': [
            {
              'id': 'builtin-grsai-image',
              'name': 'Grsai图片生成',
              'type': 'image',
              'url': 'https://grsai.dakka.com.cn',
              'key': 'sk-default',
              'model': 'gemini-3-pro-image-preview',
            },
          ],
        },
      );

      expect(merged['api_configs'][0]['name'], 'User Grsai');
      expect(merged['api_configs'][0]['url'], 'https://custom.example.com');
      expect(merged['api_configs'][0]['key'], 'sk-user');
      expect(merged['api_configs'][0]['model'], 'nano-banana-fast');
    });

    test(
      'does not write bundled defaults into stored config on save',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'config-defaults-test-',
        );
        try {
          final settingsDir = Directory('${tempDir.path}/data/Settings');
          final defaultsDir = Directory('${tempDir.path}/data/Defaults');
          await settingsDir.create(recursive: true);
          await defaultsDir.create(recursive: true);

          final storedConfig = File('${settingsDir.path}/config.json');
          await storedConfig.writeAsString(
            jsonEncode({
              'api_key': '',
              'api_configs': <Map<String, dynamic>>[],
              'generate_params': {'model': 'old-model'},
            }),
          );
          await File('${defaultsDir.path}/config.json').writeAsString(
            jsonEncode({
              'api_key': 'sk-default',
              'api_configs': [
                {
                  'id': 'builtin-grsai-image',
                  'name': 'Grsai图片生成',
                  'type': 'image',
                  'url': 'https://grsai.dakka.com.cn',
                  'key': 'sk-default',
                  'model': 'gemini-3-pro-image-preview',
                },
              ],
            }),
          );

          final service = ConfigFileService(executableDir: tempDir.path);
          final configs = await service.loadApiConfigs();
          expect(configs, hasLength(1));
          expect(configs.first.key, 'sk-default');

          await service.initConfigFiles();
          await service.saveGenerateParams(
            'new-model',
            '16:9',
            '2K',
            'auto',
            30,
          );

          final stored = jsonDecode(await storedConfig.readAsString()) as Map;
          expect(stored['api_key'], '');
          expect(stored['api_configs'], isEmpty);
          expect((stored['generate_params'] as Map)['model'], 'new-model');
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'restores missing config from local backup before creating defaults',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'config-backup-restore-test-',
        );
        try {
          final settingsDir = Directory('${tempDir.path}/data/Settings');
          await settingsDir.create(recursive: true);

          final backupFile = File(
            '${settingsDir.path}/config.json.bak-v7.7-20260618112922',
          );
          await backupFile.writeAsString(
            jsonEncode({
              'api_key': 'sk-backup',
              'api_configs': [
                {
                  'id': 'builtin-grsai-image',
                  'name': 'Backup Grsai',
                  'type': 'image',
                  'url': 'https://backup.example.com',
                  'key': 'sk-backup',
                  'model': 'gemini-backup',
                },
              ],
              'generate_params': {
                'model': 'backup-model',
                'aspectRatio': '21:9',
                'imageSize': '2K',
                'imageQuality': 'high',
                'sampleSteps': 40,
              },
            }),
          );

          final service = ConfigFileService(
            executableDir: tempDir.path,
            installedAppDirsLoader: () async => const [],
          );
          await service.initConfigFiles();

          final restoredFile = File('${settingsDir.path}/config.json');
          final restored = jsonDecode(await restoredFile.readAsString()) as Map;
          expect(restored['api_key'], 'sk-backup');
          expect((restored['api_configs'] as List), hasLength(1));
          expect((restored['generate_params'] as Map)['aspectRatio'], '21:9');
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'restores missing config from newer local corrupt snapshot before stale backup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'config-corrupt-restore-test-',
        );
        try {
          final settingsDir = Directory('${tempDir.path}/data/Settings');
          await settingsDir.create(recursive: true);

          final backupFile = File(
            '${settingsDir.path}/config.json.bak-20260618112922000000',
          );
          await backupFile.writeAsString(
            jsonEncode({
              'api_key': '',
              'api_configs': <Map<String, dynamic>>[],
              'generate_params': {
                'model': 'stale-backup',
                'aspectRatio': '16:9',
                'imageSize': '1K',
                'imageQuality': 'auto',
                'sampleSteps': 30,
              },
            }),
          );

          final corruptFile = File(
            '${settingsDir.path}/config.json.corrupt-20260618154220000000',
          );
          await corruptFile.writeAsString(
            jsonEncode({
              'api_key': 'sk-recovered',
              'api_configs': [
                {
                  'id': 'builtin-grsai-image',
                  'name': 'Recovered Grsai',
                  'type': 'image',
                  'url': 'https://recovered.example.com',
                  'key': 'sk-recovered',
                  'model': 'gemini-recovered',
                },
              ],
              'generate_params': {
                'model': 'recovered-model',
                'aspectRatio': '21:9',
                'imageSize': '2K',
                'imageQuality': 'high',
                'sampleSteps': 40,
              },
            }),
          );

          final service = ConfigFileService(
            executableDir: tempDir.path,
            installedAppDirsLoader: () async => const [],
          );
          await service.initConfigFiles();

          final restoredFile = File('${settingsDir.path}/config.json');
          final restored = jsonDecode(await restoredFile.readAsString()) as Map;
          expect(restored['api_key'], 'sk-recovered');
          expect((restored['api_configs'] as List), hasLength(1));
          expect(
            (restored['generate_params'] as Map)['model'],
            'recovered-model',
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('restores corrupt config from legacy install directory', () async {
      final currentDir = await Directory.systemTemp.createTemp(
        'config-current-install-test-',
      );
      final legacyDir = await Directory.systemTemp.createTemp(
        'config-legacy-install-test-',
      );
      try {
        final currentSettingsDir = Directory(
          '${currentDir.path}/data/Settings',
        );
        final legacySettingsDir = Directory('${legacyDir.path}/data/Settings');
        await currentSettingsDir.create(recursive: true);
        await legacySettingsDir.create(recursive: true);

        await File(
          '${currentSettingsDir.path}/config.json',
        ).writeAsString('{"broken": ');
        await File('${legacySettingsDir.path}/config.json').writeAsString(
          jsonEncode({
            'api_key': 'sk-legacy',
            'api_configs': [
              {
                'id': 'builtin-grsai-image',
                'name': 'Legacy Grsai',
                'type': 'image',
                'url': 'https://legacy.example.com',
                'key': 'sk-legacy',
                'model': 'legacy-model',
              },
            ],
            'generate_params': {
              'model': 'legacy-model',
              'aspectRatio': '4:3',
              'imageSize': '1K',
              'imageQuality': 'auto',
              'sampleSteps': 30,
            },
          }),
        );

        final service = ConfigFileService(
          executableDir: currentDir.path,
          recoverySearchDirs: [legacyDir.path],
          installedAppDirsLoader: () async => const [],
        );
        await service.initConfigFiles();

        final restoredFile = File('${currentSettingsDir.path}/config.json');
        final restored = jsonDecode(await restoredFile.readAsString()) as Map;
        expect(restored['api_key'], 'sk-legacy');
        expect((restored['api_configs'] as List), hasLength(1));
        expect((restored['generate_params'] as Map)['aspectRatio'], '4:3');

        final corruptFiles = await currentSettingsDir
            .list()
            .where(
              (entity) =>
                  entity is File &&
                  entity.path
                      .split(Platform.pathSeparator)
                      .last
                      .startsWith('config.json.corrupt-'),
            )
            .toList();
        expect(corruptFiles, isNotEmpty);
      } finally {
        await currentDir.delete(recursive: true);
        await legacyDir.delete(recursive: true);
      }
    });

    test(
      'creates bounded local backups when repeatedly saving config',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'config-save-backup-test-',
        );
        try {
          final settingsDir = Directory('${tempDir.path}/data/Settings');
          await settingsDir.create(recursive: true);

          final storedConfig = File('${settingsDir.path}/config.json');
          await storedConfig.writeAsString(
            jsonEncode({
              'api_key': 'sk-initial',
              'api_configs': [
                {
                  'id': 'builtin-grsai-image',
                  'name': 'Initial Grsai',
                  'type': 'image',
                  'url': 'https://initial.example.com',
                  'key': 'sk-initial',
                  'model': 'gemini-initial',
                },
              ],
              'generate_params': {
                'model': 'initial-model',
                'aspectRatio': '16:9',
                'imageSize': '1K',
                'imageQuality': 'auto',
                'sampleSteps': 30,
              },
            }),
          );

          final service = ConfigFileService(
            executableDir: tempDir.path,
            installedAppDirsLoader: () async => const [],
          );
          await service.initConfigFiles();

          for (var i = 0; i < 12; i++) {
            await service.saveGenerateParams(
              'model-$i',
              '16:9',
              '1K',
              'auto',
              30 + i,
            );
          }

          final backupFiles = await settingsDir
              .list()
              .where(
                (entity) =>
                    entity is File &&
                    entity.path
                        .split(Platform.pathSeparator)
                        .last
                        .startsWith('config.json.bak-'),
              )
              .toList();

          final stored = jsonDecode(await storedConfig.readAsString()) as Map;
          expect((stored['generate_params'] as Map)['model'], 'model-11');
          expect(backupFiles, isNotEmpty);
          expect(backupFiles.length, lessThanOrEqualTo(10));
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('ErrorTranslator', () {
    test('keeps apikey error specific and readable', () {
      expect(
        ErrorTranslator.translate('Exception: apikey error'),
        'API Key 无效或未配置，请检查图片生成 API Key',
      );
    });

    test('translates standalone generic error only', () {
      expect(ErrorTranslator.translate('error'), '生成服务异常，请尝试重新提交');
    });
  });
}
