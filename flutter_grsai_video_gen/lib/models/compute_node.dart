class ComputeNode {
  static const Object _noChange = Object();

  final String id;
  final String name;
  final String publicUrl;
  final String? remark;
  final bool isOnline;
  final bool isDefault;
  final bool isGenerating;
  final int queueLength;
  final int? latency;
  final String? gpuName;
  final DateTime createdAt;

  const ComputeNode({
    required this.id,
    required this.name,
    required this.publicUrl,
    required this.createdAt,
    this.remark,
    this.isOnline = false,
    this.isDefault = false,
    this.isGenerating = false,
    this.queueLength = 0,
    this.latency,
    this.gpuName,
  });

  String get effectiveApiUrl => publicUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'publicUrl': publicUrl,
    'remark': remark,
    'isOnline': isOnline,
    'isDefault': isDefault,
    'isGenerating': isGenerating,
    'queueLength': queueLength,
    'latency': latency,
    'gpuName': gpuName,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ComputeNode.fromJson(Map<String, dynamic> json) => ComputeNode(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    publicUrl:
        json['publicUrl']?.toString() ??
        json['autoDlPublicUrl']?.toString() ??
        json['apiUrl']?.toString() ??
        '',
    remark: json['remark']?.toString(),
    isOnline: json['isOnline'] == true,
    isDefault: json['isDefault'] == true,
    isGenerating: json['isGenerating'] == true,
    queueLength: (json['queueLength'] as num?)?.toInt() ?? 0,
    latency: (json['latency'] as num?)?.toInt(),
    gpuName: json['gpuName']?.toString(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );

  ComputeNode copyWith({
    String? name,
    String? publicUrl,
    Object? remark = _noChange,
    bool? isOnline,
    bool? isDefault,
    bool? isGenerating,
    int? queueLength,
    Object? latency = _noChange,
    Object? gpuName = _noChange,
  }) {
    return ComputeNode(
      id: id,
      name: name ?? this.name,
      publicUrl: publicUrl ?? this.publicUrl,
      remark: identical(remark, _noChange) ? this.remark : remark as String?,
      isOnline: isOnline ?? this.isOnline,
      isDefault: isDefault ?? this.isDefault,
      isGenerating: isGenerating ?? this.isGenerating,
      queueLength: queueLength ?? this.queueLength,
      latency: identical(latency, _noChange) ? this.latency : latency as int?,
      gpuName: identical(gpuName, _noChange)
          ? this.gpuName
          : gpuName as String?,
      createdAt: createdAt,
    );
  }
}
