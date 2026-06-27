import 'video_generate_params.dart';

class VideoVlmConfig {
  final String apiUrl;
  final String apiKey;
  final String model;

  const VideoVlmConfig({
    this.apiUrl = 'http://115.231.35.105:12345/v1/chat/completions',
    this.apiKey = '',
    this.model = 'qwen3.5-9b-vlm',
  });

  Map<String, dynamic> toJson() => {
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory VideoVlmConfig.fromJson(Map<String, dynamic> json) => VideoVlmConfig(
    apiUrl:
        json['apiUrl']?.toString() ??
        'http://115.231.35.105:12345/v1/chat/completions',
    apiKey: json['apiKey']?.toString() ?? '',
    model: json['model']?.toString() ?? 'qwen3.5-9b-vlm',
  );

  VideoVlmConfig copyWith({String? apiUrl, String? apiKey, String? model}) {
    return VideoVlmConfig(
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}

class Wan2gpBridgeConfig {
  final String pythonPath;
  final String scriptPath;
  final int port;
  final bool autoLaunch;

  const Wan2gpBridgeConfig({
    this.pythonPath = r'D:/pinokio/api/wan2gp.git/app/env/Scripts/pythonw.exe',
    this.scriptPath = r'G:/data/app/LTX2.3/wan2gp_bridge_server.py',
    this.port = 7861,
    this.autoLaunch = false,
  });

  Map<String, dynamic> toJson() => {
    'pythonPath': pythonPath,
    'scriptPath': scriptPath,
    'port': port,
    'autoLaunch': autoLaunch,
  };

  factory Wan2gpBridgeConfig.fromJson(Map<String, dynamic> json) =>
      Wan2gpBridgeConfig(
        pythonPath:
            json['pythonPath']?.toString() ??
            r'D:/pinokio/api/wan2gp.git/app/env/Scripts/pythonw.exe',
        scriptPath: (json['scriptPath']?.toString().trim().isNotEmpty ?? false)
            ? json['scriptPath']!.toString()
            : r'G:/data/app/LTX2.3/wan2gp_bridge_server.py',
        port: (json['port'] as num?)?.toInt() ?? 7861,
        autoLaunch: json['autoLaunch'] == true,
      );

  Wan2gpBridgeConfig copyWith({
    String? pythonPath,
    String? scriptPath,
    int? port,
    bool? autoLaunch,
  }) {
    return Wan2gpBridgeConfig(
      pythonPath: pythonPath ?? this.pythonPath,
      scriptPath: scriptPath ?? this.scriptPath,
      port: port ?? this.port,
      autoLaunch: autoLaunch ?? this.autoLaunch,
    );
  }
}

class VideoSettingsConfig {
  final VideoVlmConfig vlm;
  final Wan2gpBridgeConfig wan2gp;
  final VideoGenerateParams defaults;
  final List<String> hiddenModelIds;

  const VideoSettingsConfig({
    this.vlm = const VideoVlmConfig(),
    this.wan2gp = const Wan2gpBridgeConfig(),
    this.defaults = const VideoGenerateParams(),
    this.hiddenModelIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'vlm': vlm.toJson(),
    'wan2gp': wan2gp.toJson(),
    'defaults': defaults.toJson(),
    'hiddenModelIds': hiddenModelIds,
  };

  factory VideoSettingsConfig.fromJson(Map<String, dynamic> json) =>
      VideoSettingsConfig(
        vlm: json['vlm'] is Map<String, dynamic>
            ? VideoVlmConfig.fromJson(json['vlm'])
            : json['vlm'] is Map
            ? VideoVlmConfig.fromJson(
                Map<String, dynamic>.from(json['vlm'] as Map),
              )
            : const VideoVlmConfig(),
        wan2gp: json['wan2gp'] is Map<String, dynamic>
            ? Wan2gpBridgeConfig.fromJson(json['wan2gp'])
            : json['wan2gp'] is Map
            ? Wan2gpBridgeConfig.fromJson(
                Map<String, dynamic>.from(json['wan2gp'] as Map),
              )
            : const Wan2gpBridgeConfig(),
        defaults: json['defaults'] is Map<String, dynamic>
            ? VideoGenerateParams.fromJson(json['defaults'])
            : json['defaults'] is Map
            ? VideoGenerateParams.fromJson(
                Map<String, dynamic>.from(json['defaults'] as Map),
              )
            : const VideoGenerateParams(),
        hiddenModelIds: ((json['hiddenModelIds'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
      );

  VideoSettingsConfig copyWith({
    VideoVlmConfig? vlm,
    Wan2gpBridgeConfig? wan2gp,
    VideoGenerateParams? defaults,
    List<String>? hiddenModelIds,
  }) {
    return VideoSettingsConfig(
      vlm: vlm ?? this.vlm,
      wan2gp: wan2gp ?? this.wan2gp,
      defaults: defaults ?? this.defaults,
      hiddenModelIds: hiddenModelIds ?? this.hiddenModelIds,
    );
  }
}
