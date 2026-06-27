class Settings {
  static const String uploadMethodRelayUrl = 'relay_url';
  static const String uploadMethodBase64 = 'base64';
  static const String updateDownloadProxySystem = 'system_proxy';
  static const String updateDownloadProxyCustom = 'custom_proxy';
  static const String defaultUpdateDownloadProxyAddress =
      'http://127.0.0.1:7890';

  final String apiUrl;
  final String apiKey;
  final String aiApiUrl;
  final String aiApiKey;
  final String aiModel;
  final String uploadMethod;
  final String updateDownloadProxyMode;
  final String updateDownloadProxyAddress;
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
    required this.updateDownloadProxyMode,
    required this.updateDownloadProxyAddress,
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
    updateDownloadProxyMode: updateDownloadProxySystem,
    updateDownloadProxyAddress: defaultUpdateDownloadProxyAddress,
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
    'updateDownloadProxyMode': updateDownloadProxyMode,
    'updateDownloadProxyAddress': updateDownloadProxyAddress,
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
    final updateDownloadProxyMode =
        json['updateDownloadProxyMode']?.toString() ??
        updateDownloadProxySystem;
    final normalizedUpdateDownloadProxyMode =
        updateDownloadProxyMode == updateDownloadProxyCustom
        ? updateDownloadProxyCustom
        : updateDownloadProxySystem;
    final updateDownloadProxyAddress =
        json['updateDownloadProxyAddress']?.toString().trim() ?? '';

    return Settings(
      apiUrl: json['apiUrl'] ?? '',
      apiKey: json['apiKey'] ?? '',
      aiApiUrl: json['aiApiUrl'] ?? '',
      aiApiKey: json['aiApiKey'] ?? '',
      aiModel: json['aiModel'] ?? '',
      uploadMethod: normalizedUploadMethod,
      updateDownloadProxyMode: normalizedUpdateDownloadProxyMode,
      updateDownloadProxyAddress: updateDownloadProxyAddress.isEmpty
          ? defaultUpdateDownloadProxyAddress
          : updateDownloadProxyAddress,
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
    String? updateDownloadProxyMode,
    String? updateDownloadProxyAddress,
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
    updateDownloadProxyMode:
        updateDownloadProxyMode ?? this.updateDownloadProxyMode,
    updateDownloadProxyAddress:
        updateDownloadProxyAddress ?? this.updateDownloadProxyAddress,
    outputFolder: outputFolder ?? this.outputFolder,
    filenameRule: filenameRule ?? this.filenameRule,
    customFilename: customFilename ?? this.customFilename,
    aiNickname: aiNickname ?? this.aiNickname,
    userNickname: userNickname ?? this.userNickname,
  );
}
