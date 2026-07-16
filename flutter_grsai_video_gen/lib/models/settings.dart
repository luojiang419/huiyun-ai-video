class Settings {
  static const String uploadMethodRelayUrl = 'relay_url';
  static const String uploadMethodBase64 = 'base64';
  static const String updatePolicyAutomatic = 'automatic';
  static const String updatePolicyManual = 'manual';
  static const String updatePolicyDisabled = 'disabled';
  static const String updateNetworkAutomaticProxy = 'automatic_proxy';
  static const String updateNetworkManualProxy = 'manual_proxy';
  static const String updateNetworkDirect = 'direct';
  static const String defaultUpdateManualProxyUrl = 'http://127.0.0.1:7890';

  static const String _legacyUpdateProxySystem = 'system_proxy';
  static const String _legacyUpdateProxyCustom = 'custom_proxy';

  final String apiUrl;
  final String apiKey;
  final String aiApiUrl;
  final String aiApiKey;
  final String aiModel;
  final String uploadMethod;
  final String updatePolicy;
  final String updateNetworkMode;
  final String updateManualProxyUrl;
  final String outputFolder;
  final String filenameRule;
  final String customFilename;
  final String aiNickname;
  final String userNickname;

  Settings({
    required this.apiUrl,
    required this.apiKey,
    required this.aiApiUrl,
    required this.aiApiKey,
    required this.aiModel,
    required this.uploadMethod,
    required this.updatePolicy,
    required this.updateNetworkMode,
    required this.updateManualProxyUrl,
    required this.outputFolder,
    required this.filenameRule,
    required this.customFilename,
    required this.aiNickname,
    required this.userNickname,
  });

  factory Settings.defaultSettings() => Settings(
    apiUrl: '',
    apiKey: '',
    aiApiUrl: '',
    aiApiKey: '',
    aiModel: '',
    uploadMethod: uploadMethodRelayUrl,
    updatePolicy: updatePolicyAutomatic,
    updateNetworkMode: updateNetworkAutomaticProxy,
    updateManualProxyUrl: defaultUpdateManualProxyUrl,
    outputFolder: 'data/output',
    filenameRule: 'date',
    customFilename: 'nano',
    aiNickname: 'MOSS',
    userNickname: '章北海',
  );

  Map<String, dynamic> toJson() => {
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'aiApiUrl': aiApiUrl,
    'aiApiKey': aiApiKey,
    'aiModel': aiModel,
    'uploadMethod': uploadMethod,
    'updatePolicy': updatePolicy,
    'updateNetworkMode': updateNetworkMode,
    'updateManualProxyUrl': updateManualProxyUrl,
    'outputFolder': outputFolder,
    'filenameRule': filenameRule,
    'customFilename': customFilename,
    'aiNickname': aiNickname,
    'userNickname': userNickname,
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    final uploadMethod =
        json['uploadMethod']?.toString() ?? uploadMethodRelayUrl;
    final normalizedUploadMethod = uploadMethod == uploadMethodBase64
        ? uploadMethodBase64
        : uploadMethodRelayUrl;
    final rawUpdatePolicy = json['updatePolicy']?.toString();
    final normalizedUpdatePolicy = switch (rawUpdatePolicy) {
      updatePolicyManual => updatePolicyManual,
      updatePolicyDisabled => updatePolicyDisabled,
      _ => updatePolicyAutomatic,
    };
    final rawUpdateNetworkMode =
        json['updateNetworkMode']?.toString() ??
        json['updateDownloadProxyMode']?.toString();
    final normalizedUpdateNetworkMode = switch (rawUpdateNetworkMode) {
      updateNetworkManualProxy ||
      _legacyUpdateProxyCustom => updateNetworkManualProxy,
      updateNetworkDirect => updateNetworkDirect,
      updateNetworkAutomaticProxy ||
      _legacyUpdateProxySystem => updateNetworkAutomaticProxy,
      _ => updateNetworkAutomaticProxy,
    };
    final updateManualProxyUrl =
        (json['updateManualProxyUrl'] ?? json['updateDownloadProxyAddress'])
            ?.toString()
            .trim() ??
        '';

    return Settings(
      apiUrl: json['apiUrl'] ?? '',
      apiKey: json['apiKey'] ?? '',
      aiApiUrl: json['aiApiUrl'] ?? '',
      aiApiKey: json['aiApiKey'] ?? '',
      aiModel: json['aiModel'] ?? '',
      uploadMethod: normalizedUploadMethod,
      updatePolicy: normalizedUpdatePolicy,
      updateNetworkMode: normalizedUpdateNetworkMode,
      updateManualProxyUrl: updateManualProxyUrl.isEmpty
          ? defaultUpdateManualProxyUrl
          : updateManualProxyUrl,
      outputFolder: json['outputFolder'] ?? 'data/output',
      filenameRule: json['filenameRule'] ?? 'date',
      customFilename: json['customFilename'] ?? 'nano',
      aiNickname: json['aiNickname'] ?? 'MOSS',
      userNickname: json['userNickname'] ?? '章北海',
    );
  }

  Settings copyWith({
    String? apiUrl,
    String? apiKey,
    String? aiApiUrl,
    String? aiApiKey,
    String? aiModel,
    String? uploadMethod,
    String? updatePolicy,
    String? updateNetworkMode,
    String? updateManualProxyUrl,
    String? outputFolder,
    String? filenameRule,
    String? customFilename,
    String? aiNickname,
    String? userNickname,
  }) => Settings(
    apiUrl: apiUrl ?? this.apiUrl,
    apiKey: apiKey ?? this.apiKey,
    aiApiUrl: aiApiUrl ?? this.aiApiUrl,
    aiApiKey: aiApiKey ?? this.aiApiKey,
    aiModel: aiModel ?? this.aiModel,
    uploadMethod: uploadMethod ?? this.uploadMethod,
    updatePolicy: updatePolicy ?? this.updatePolicy,
    updateNetworkMode: updateNetworkMode ?? this.updateNetworkMode,
    updateManualProxyUrl: updateManualProxyUrl ?? this.updateManualProxyUrl,
    outputFolder: outputFolder ?? this.outputFolder,
    filenameRule: filenameRule ?? this.filenameRule,
    customFilename: customFilename ?? this.customFilename,
    aiNickname: aiNickname ?? this.aiNickname,
    userNickname: userNickname ?? this.userNickname,
  );
}
