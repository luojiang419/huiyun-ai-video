import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/api_config.dart';
import '../models/compute_node.dart';
import '../models/video_config.dart';
import '../models/video_item.dart';

class ConfigFileService {
  static Future<void> _configWriteQueue = Future.value();
  static const String defaultImageGenerationModel = 'nano-banana-fast';
  static const String legacyGeminiDefaultImageGenerationModel =
      'gemini-3-pro-image-preview';

  ConfigFileService({
    String? executableDir,
    List<String>? recoverySearchDirs,
    Future<List<String>> Function()? installedAppDirsLoader,
  }) : _executableDir = executableDir,
       _recoverySearchDirs = recoverySearchDirs,
       _installedAppDirsLoader = installedAppDirsLoader;

  final String? _executableDir;
  final List<String>? _recoverySearchDirs;
  final Future<List<String>> Function()? _installedAppDirsLoader;

  String get _exeDir =>
      _executableDir ?? File(Platform.resolvedExecutable).parent.path;

  String getConfigPath() {
    return '$_exeDir/data/Settings/config.json';
  }

  String getSystemPromptPath() {
    return '$_exeDir/data/Settings/system_prompt.txt';
  }

  String getSettingsDirectoryPath() {
    return '$_exeDir/data/Settings';
  }

  String getDefaultConfigPath() {
    return '$_exeDir/data/Defaults/config.json';
  }

  Map<String, dynamic> _buildDefaultConfig() => {
    'api_url': '',
    'api_key': '',
    'ai_api_url': '',
    'ai_api_key': '',
    'ai_model': '',
    'api_configs': <Map<String, dynamic>>[],
    'generate_params': {
      'model': defaultImageGenerationModel,
      'aspectRatio': 'auto',
      'imageSize': '1K',
      'imageQuality': 'auto',
      'sampleSteps': 30,
    },
    'video': {
      ...const VideoSettingsConfig().toJson(),
      'nodes': <Map<String, dynamic>>[],
      'gallery': <Map<String, dynamic>>[],
    },
  };

  Future<Map<String, dynamic>?> _loadBundledDefaultConfig() async {
    try {
      final file = File(getDefaultConfigPath());
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  static bool _isBlankValue(dynamic value) {
    return value == null || value.toString().trim().isEmpty;
  }

  static List<Map<String, dynamic>> _readConfigList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Map<String, dynamic> mergeConfigWithBundledDefaults(
    Map<String, dynamic> current,
    Map<String, dynamic>? bundledDefaults,
  ) {
    if (bundledDefaults == null) {
      return current;
    }

    final merged = Map<String, dynamic>.from(current);
    for (final key in const [
      'api_key',
      'ai_api_key',
      'api_url',
      'ai_api_url',
      'ai_model',
    ]) {
      if (_isBlankValue(merged[key]) && !_isBlankValue(bundledDefaults[key])) {
        merged[key] = bundledDefaults[key];
      }
    }

    final currentConfigs = _readConfigList(merged['api_configs']);
    final defaultConfigs = _readConfigList(bundledDefaults['api_configs']);
    if (currentConfigs.isEmpty && defaultConfigs.isNotEmpty) {
      merged['api_configs'] = defaultConfigs;
      return merged;
    }

    if (currentConfigs.isEmpty || defaultConfigs.isEmpty) {
      return merged;
    }

    final defaultsById = {
      for (final config in defaultConfigs)
        if (!_isBlankValue(config['id'])) config['id'].toString(): config,
    };
    var changed = false;
    final patchedConfigs = currentConfigs.map((config) {
      final id = config['id']?.toString() ?? '';
      final fallback = defaultsById[id];
      if (fallback == null) {
        return config;
      }
      final patched = Map<String, dynamic>.from(config);
      for (final key in const ['key', 'url', 'model', 'name']) {
        if (_isBlankValue(patched[key]) && !_isBlankValue(fallback[key])) {
          patched[key] = fallback[key];
          changed = true;
        }
      }
      return patched;
    }).toList();

    if (changed) {
      merged['api_configs'] = patchedConfigs;
    }
    return merged;
  }

  Future<Map<String, dynamic>> _applyBundledDefaults(
    Map<String, dynamic> current,
  ) async {
    return mergeConfigWithBundledDefaults(
      current,
      await _loadBundledDefaultConfig(),
    );
  }

  Future<T> _runExclusiveConfigWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _configWriteQueue;
    _configWriteQueue = () async {
      try {
        await previous;
      } catch (_) {
        // ignore
      }

      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<void> initConfigFiles() async {
    await _ensureStoredConfigReady();

    final promptPath = getSystemPromptPath();
    final promptFile = File(promptPath);
    if (!await promptFile.exists()) {
      const defaultPrompt =
          "你是一个图像和视频类智能AI提示词专家，摄影大师，影视工作者，电商销售，产品经理。用户给到的提示词都是用作ai生成图片，需要你根据用户提供的提示词进行润色，在不偏离原意的基础上，将画面描述得更精彩。\n\n每次收到用户的提示词后，你需要给出三条润色后的提示词结果。\n\nAI润色的提示词规则包括但不限于：\n- 可以根据文字提示构建所有内容——构图、主题、环境、光线、风格和运动\n- 视觉描述——描述我们看到的事物、它的位置以及它的外观\n- 动态描述——描述场景的运动和行为方式\n- 描述你希望看到什么，而不是你不希望看到什么\n- 要具体明确，使用清晰、可观察的描述\n- 确保提示信息中的各个要素彼此不矛盾\n\n请直接返回三条润色后的提示词，每条用换行符分隔，不要添加序号或其他标记。";
      await promptFile.writeAsString(defaultPrompt);
    }
  }

  Map<String, dynamic> _mergeWithDefaults(
    Map<String, dynamic> current,
    Map<String, dynamic> defaults,
  ) {
    final merged = <String, dynamic>{};
    for (final entry in defaults.entries) {
      final existingValue = current[entry.key];
      final defaultValue = entry.value;
      if (existingValue is Map && defaultValue is Map) {
        merged[entry.key] = _mergeWithDefaults(
          Map<String, dynamic>.from(existingValue),
          Map<String, dynamic>.from(defaultValue),
        );
      } else if (existingValue == null) {
        merged[entry.key] = defaultValue;
      } else {
        merged[entry.key] = existingValue;
      }
    }
    for (final entry in current.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }
    return merged;
  }

  Future<String> loadPromptRule(String ruleId) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final filePath = '$exeDir/data/Settings/${ruleId}_system.txt';
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  Future<String> loadSystemPrompt() async {
    const defaultPrompt =
        "你是一个图像和视频类智能AI提示词专家，摄影大师，影视工作者，电商销售，产品经理。用户给到的提示词都是用作ai生成图片，需要你根据用户提供的提示词进行润色，在不偏离原意的基础上，将画面描述得更精彩。\n\n每次收到用户的提示词后，你需要给出三条润色后的提示词结果。\n\nAI润色的提示词规则包括但不限于：\n- 可以根据文字提示构建所有内容——构图、主题、环境、光线、风格和运动\n- 视觉描述——描述我们看到的事物、它的位置以及它的外观\n- 动态描述——描述场景的运动和行为方式\n- 描述你希望看到什么，而不是你不希望看到什么\n- 要具体明确，使用清晰、可观察的描述\n- 确保提示信息中的各个要素彼此不矛盾\n\n请直接返回三条润色后的提示词，每条用换行符分隔，不要添加序号或其他标记。";

    try {
      final file = File(getSystemPromptPath());
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }
    } catch (_) {
      // ignore
    }
    return defaultPrompt;
  }

  Future<Map<String, dynamic>> _loadStoredConfig() async {
    return _ensureStoredConfigReady();
  }

  Future<Map<String, dynamic>> loadConfig() async {
    return _applyBundledDefaults(await _loadStoredConfig());
  }

  Future<void> saveConfig(Map<String, dynamic> config) async {
    final merged = _mergeWithDefaults(config, _buildDefaultConfig());
    final file = File(getConfigPath());
    await file.parent.create(recursive: true);
    await _writeConfigFileAtomically(
      file,
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }

  Future<void> _writeConfigFileAtomically(File file, String content) async {
    String? previousContent;
    final existed = await file.exists();
    if (existed) {
      try {
        previousContent = await file.readAsString();
        if (previousContent == content) {
          return;
        }
      } catch (_) {
        // ignore
      }
    }

    final tempFile = File('${file.path}.tmp-${_buildTimestampToken()}');
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsString(content, flush: true);

    try {
      if (existed && previousContent != null && previousContent != content) {
        await _writeConfigBackup(file.parent.path, previousContent);
      }

      if (existed) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } catch (_) {
      if (!await file.exists()) {
        try {
          if (previousContent != null) {
            await file.writeAsString(previousContent, flush: true);
          } else if (await tempFile.exists()) {
            await tempFile.copy(file.path);
          }
        } catch (_) {
          // ignore
        }
      }
      rethrow;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> _writeConfigBackup(
    String settingsDirPath,
    String content,
  ) async {
    final backupFile = File(
      '$settingsDirPath/config.json.bak-${_buildTimestampToken()}',
    );
    await backupFile.writeAsString(content, flush: true);
    await _pruneConfigBackupFiles(settingsDirPath);
  }

  Future<void> _pruneConfigBackupFiles(
    String settingsDirPath, {
    int keep = 10,
  }) async {
    final backups = await _listConfigBackupFiles(settingsDirPath);
    for (final backup in backups.skip(keep)) {
      try {
        await backup.delete();
      } catch (_) {
        // ignore
      }
    }
  }

  Future<List<ApiConfig>> loadApiConfigs() async {
    final config = await loadConfig();
    final list = config['api_configs'] as List? ?? [];

    if (list.isEmpty &&
        config['api_url'] != null &&
        (config['api_url'] as String).isNotEmpty) {
      return [
        ApiConfig(
          id: 'legacy-draw',
          name: '默认绘画API',
          type: 'image',
          url: config['api_url'] as String,
          key: config['api_key'] as String? ?? '',
          model: '',
          isDefault: true,
        ),
        if (config['ai_api_url'] != null &&
            (config['ai_api_url'] as String).isNotEmpty)
          ApiConfig(
            id: 'legacy-chat',
            name: '默认对话API',
            type: 'chat',
            url: config['ai_api_url'] as String,
            key: config['ai_api_key'] as String? ?? '',
            model: config['ai_model'] as String? ?? '',
            isDefault: true,
          ),
      ];
    }

    return list
        .map((e) => ApiConfig.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveApiConfigs(List<ApiConfig> configs) async {
    await _runExclusiveConfigWrite(() async {
      final config = await _loadStoredConfig();
      config['api_configs'] = configs.map((e) => e.toJson()).toList();
      await saveConfig(config);
    });
  }

  Future<Map<String, dynamic>> loadGenerateParams() async {
    final config = await loadConfig();
    final params = config['generate_params'] as Map<String, dynamic>?;
    final model = params?['model'] as String?;
    return {
      'model': model == null || model.trim().isEmpty
          ? defaultImageGenerationModel
          : model == legacyGeminiDefaultImageGenerationModel
          ? defaultImageGenerationModel
          : model,
      'aspectRatio': params?['aspectRatio'] as String? ?? 'auto',
      'imageSize': params?['imageSize'] as String? ?? '1K',
      'imageQuality': params?['imageQuality'] as String? ?? 'auto',
      'sampleSteps': (params?['sampleSteps'] as num?)?.toInt() ?? 30,
    };
  }

  Future<void> saveGenerateParams(
    String model,
    String aspectRatio,
    String imageSize,
    String imageQuality,
    int sampleSteps,
  ) async {
    await _runExclusiveConfigWrite(() async {
      final config = await _loadStoredConfig();
      config['generate_params'] = {
        'model': model,
        'aspectRatio': aspectRatio,
        'imageSize': imageSize,
        'imageQuality': imageQuality,
        'sampleSteps': sampleSteps,
      };
      await saveConfig(config);
    });
  }

  Future<VideoSettingsConfig> loadVideoSettingsConfig() async {
    final config = await loadConfig();
    final videoConfig = config['video'] is Map<String, dynamic>
        ? config['video'] as Map<String, dynamic>
        : config['video'] is Map
        ? Map<String, dynamic>.from(config['video'] as Map)
        : <String, dynamic>{};
    return VideoSettingsConfig.fromJson(videoConfig);
  }

  Future<void> saveVideoSettingsConfig(VideoSettingsConfig settings) async {
    await _runExclusiveConfigWrite(() async {
      final config = await _loadStoredConfig();
      final currentVideo = config['video'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(config['video'] as Map<String, dynamic>)
          : config['video'] is Map
          ? Map<String, dynamic>.from(config['video'] as Map)
          : <String, dynamic>{};
      currentVideo.addAll(settings.toJson());
      currentVideo['nodes'] ??= <Map<String, dynamic>>[];
      currentVideo['gallery'] ??= <Map<String, dynamic>>[];
      config['video'] = currentVideo;
      await saveConfig(config);
    });
  }

  Future<List<ComputeNode>> loadVideoNodes() async {
    final config = await loadConfig();
    final videoConfig = config['video'] is Map<String, dynamic>
        ? config['video'] as Map<String, dynamic>
        : config['video'] is Map
        ? Map<String, dynamic>.from(config['video'] as Map)
        : <String, dynamic>{};
    final list = videoConfig['nodes'] as List? ?? [];
    return list
        .map((e) => ComputeNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveVideoNodes(List<ComputeNode> nodes) async {
    await _runExclusiveConfigWrite(() async {
      final config = await _loadStoredConfig();
      final videoConfig = config['video'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(config['video'] as Map<String, dynamic>)
          : config['video'] is Map
          ? Map<String, dynamic>.from(config['video'] as Map)
          : <String, dynamic>{};
      videoConfig['nodes'] = nodes.map((e) => e.toJson()).toList();
      config['video'] = videoConfig;
      await saveConfig(config);
    });
  }

  Future<List<VideoItem>> loadVideoGallery() async {
    final config = await loadConfig();
    final videoConfig = config['video'] is Map<String, dynamic>
        ? config['video'] as Map<String, dynamic>
        : config['video'] is Map
        ? Map<String, dynamic>.from(config['video'] as Map)
        : <String, dynamic>{};
    final list = videoConfig['gallery'] as List? ?? [];
    return list
        .map((e) => VideoItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveVideoGallery(List<VideoItem> items) async {
    await _runExclusiveConfigWrite(() async {
      final config = await _loadStoredConfig();
      final videoConfig = config['video'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(config['video'] as Map<String, dynamic>)
          : config['video'] is Map
          ? Map<String, dynamic>.from(config['video'] as Map)
          : <String, dynamic>{};
      videoConfig['gallery'] = items.map((e) => e.toJson()).toList();
      config['video'] = videoConfig;
      await saveConfig(config);
    });
  }

  Future<List<String>> loadPromptHistory() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final file = File('$exeDir/data/Settings/prompt_history.json');
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List;
        return list.cast<String>();
      }
    } catch (_) {
      // ignore
    }
    return [];
  }

  Future<void> addPromptHistory(String prompt) async {
    if (prompt.trim().isEmpty) return;
    final history = await loadPromptHistory();
    history.removeWhere((h) => h == prompt);
    history.insert(0, prompt);
    final trimmed = history.take(10).toList();
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final file = File('$exeDir/data/Settings/prompt_history.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(trimmed));
    } catch (_) {
      // ignore
    }
  }

  Future<Map<String, dynamic>> _ensureStoredConfigReady() async {
    final configFile = File(getConfigPath());
    await configFile.parent.create(recursive: true);

    final current = await _readConfigFile(configFile);
    if (current != null) {
      return current;
    }

    if (await configFile.exists()) {
      await _moveCorruptConfigAside(configFile);
    }

    final recovered = await _restoreConfigFromCandidates(configFile);
    if (recovered != null) {
      return recovered;
    }

    final fallback = _buildDefaultConfig();
    await saveConfig(fallback);
    return fallback;
  }

  Future<Map<String, dynamic>?> _readConfigFile(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return _mergeWithDefaults(decoded, _buildDefaultConfig());
      }
      if (decoded is Map) {
        return _mergeWithDefaults(
          Map<String, dynamic>.from(decoded),
          _buildDefaultConfig(),
        );
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _moveCorruptConfigAside(File file) async {
    if (!await file.exists()) {
      return;
    }

    final corruptPath =
        '${file.parent.path}/config.json.corrupt-${_buildTimestampToken()}';
    await file.rename(corruptPath);
  }

  Future<Map<String, dynamic>?> _restoreConfigFromCandidates(
    File targetFile,
  ) async {
    final candidates = await _collectRecoveryCandidates(targetFile);
    for (final candidate in candidates) {
      final restored = await _readConfigFile(candidate);
      if (restored == null) {
        continue;
      }

      await saveConfig(restored);
      return restored;
    }
    return null;
  }

  Future<List<File>> _collectRecoveryCandidates(File targetFile) async {
    final candidates = <File>[];
    final seenPaths = <String>{_normalizePath(targetFile.path)};
    final currentSettingsDir = _normalizePath(targetFile.parent.path);

    Future<void> addCandidate(File file) async {
      final normalized = _normalizePath(file.path);
      if (seenPaths.contains(normalized) || !await file.exists()) {
        return;
      }
      seenPaths.add(normalized);
      candidates.add(file);
    }

    final currentCandidates = [
      ...await _listCorruptConfigFiles(targetFile.parent.path),
      ...await _listConfigBackupFiles(targetFile.parent.path),
    ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    for (final candidate in currentCandidates) {
      await addCandidate(candidate);
    }

    final externalCandidates = <File>[];
    for (final installDir in await _loadRecoveryInstallDirs()) {
      final settingsDir = _normalizePath('$installDir/data/Settings');
      if (settingsDir == currentSettingsDir) {
        continue;
      }

      final configFile = File('$installDir/data/Settings/config.json');
      if (await configFile.exists()) {
        externalCandidates.add(configFile);
      }
      externalCandidates.addAll(
        await _listConfigBackupFiles('$installDir/data/Settings'),
      );
      externalCandidates.addAll(
        await _listCorruptConfigFiles('$installDir/data/Settings'),
      );
    }

    externalCandidates.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    for (final candidate in externalCandidates) {
      await addCandidate(candidate);
    }

    return candidates;
  }

  Future<List<File>> _listConfigBackupFiles(String settingsDirPath) async {
    final settingsDir = Directory(settingsDirPath);
    if (!await settingsDir.exists()) {
      return const [];
    }

    final backups = <File>[];
    await for (final entity in settingsDir.list()) {
      if (entity is! File) {
        continue;
      }

      final name = entity.uri.pathSegments.isEmpty
          ? entity.path.split(Platform.pathSeparator).last
          : entity.uri.pathSegments.last;
      if (!name.startsWith('config.json.bak-')) {
        continue;
      }
      backups.add(entity);
    }

    backups.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return backups;
  }

  Future<List<File>> _listCorruptConfigFiles(String settingsDirPath) async {
    final settingsDir = Directory(settingsDirPath);
    if (!await settingsDir.exists()) {
      return const [];
    }

    final corruptFiles = <File>[];
    await for (final entity in settingsDir.list()) {
      if (entity is! File) {
        continue;
      }

      final name = entity.uri.pathSegments.isEmpty
          ? entity.path.split(Platform.pathSeparator).last
          : entity.uri.pathSegments.last;
      if (!name.startsWith('config.json.corrupt-')) {
        continue;
      }
      corruptFiles.add(entity);
    }

    corruptFiles.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return corruptFiles;
  }

  Future<List<String>> _loadRecoveryInstallDirs() async {
    final dirs = <String>{_exeDir, ...?_recoverySearchDirs};

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      dirs.add('$localAppData/HuiYunAI/VideoGen');
    }

    final programFiles = Platform.environment['ProgramFiles'];
    if (programFiles != null && programFiles.trim().isNotEmpty) {
      dirs.add('$programFiles/VideoGen');
    }

    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    if (programFilesX86 != null && programFilesX86.trim().isNotEmpty) {
      dirs.add('$programFilesX86/VideoGen');
    }

    if (Platform.isWindows) {
      if (_installedAppDirsLoader != null) {
        dirs.addAll(await _installedAppDirsLoader.call());
      } else {
        dirs.addAll(await _readInstalledDirsFromRegistry());
      }
    }

    return dirs
        .where((dir) => dir.trim().isNotEmpty)
        .map((dir) => dir.replaceAll('\\', '/'))
        .toList();
  }

  Future<List<String>> _readInstalledDirsFromRegistry() async {
    const script = r'''
$roots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)
$result = @()
foreach ($root in $roots) {
  if (-not (Test-Path $root)) {
    continue
  }

  Get-ChildItem $root -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'HuiYunAI.Video*' } |
    ForEach-Object {
      $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
      foreach ($name in @('Inno Setup: App Path', 'InstallLocation')) {
        $property = $item.PSObject.Properties[$name]
        if ($null -ne $property -and $property.Value) {
          $result += $property.Value.ToString().Trim()
        }
      }
    }
}

$result | Sort-Object -Unique | ConvertTo-Json -Compress
''';

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ]);
      if (result.exitCode != 0) {
        return const [];
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return const [];
      }

      final decoded = jsonDecode(output);
      if (decoded is String) {
        return [decoded];
      }
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // ignore
    }
    return const [];
  }

  String _normalizePath(String value) {
    final normalized = value.replaceAll('\\', '/').trim();
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _buildTimestampToken() {
    final now = DateTime.now();
    String pad(int value) => value.toString().padLeft(2, '0');
    String pad3(int value) => value.toString().padLeft(3, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}'
        '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}'
        '${pad3(now.millisecond)}${pad3(now.microsecond)}';
  }
}
