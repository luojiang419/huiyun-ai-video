class UpdateInfo {
  final String version;
  final String installerName;
  final String installerUrl;
  final String sha256;
  final int size;
  final String publishedAt;
  final String releaseNotes;
  final bool mandatory;

  const UpdateInfo({
    required this.version,
    required this.installerName,
    required this.installerUrl,
    required this.sha256,
    required this.size,
    required this.publishedAt,
    required this.releaseNotes,
    required this.mandatory,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('update.json 缺少有效字段: $key');
      }
      return value.trim();
    }

    final sizeValue = json['size'];
    final size = sizeValue is int
        ? sizeValue
        : sizeValue is num
        ? sizeValue.toInt()
        : int.tryParse(sizeValue?.toString() ?? '');
    if (size == null || size < 0) {
      throw const FormatException('update.json 缺少有效字段: size');
    }

    return UpdateInfo(
      version: requiredString('version'),
      installerName: requiredString('installerName'),
      installerUrl: requiredString('installerUrl'),
      sha256: requiredString('sha256').toUpperCase(),
      size: size,
      publishedAt: requiredString('publishedAt'),
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      mandatory: json['mandatory'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'installerName': installerName,
      'installerUrl': installerUrl,
      'sha256': sha256,
      'size': size,
      'publishedAt': publishedAt,
      'releaseNotes': releaseNotes,
      'mandatory': mandatory,
    };
  }

  String get sizeLabel {
    if (size <= 0) return '未知大小';
    final mb = size / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

List<int> parseAppVersionParts(String version) {
  final normalized = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final matches = RegExp(r'\d+').allMatches(normalized).toList();
  if (matches.isEmpty) {
    throw FormatException('无效版本号: $version');
  }
  final parts = matches.map((match) => int.parse(match.group(0)!)).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

int compareAppVersions(String left, String right) {
  final leftParts = parseAppVersionParts(left);
  final rightParts = parseAppVersionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var i = 0; i < maxLength; i++) {
    final leftPart = i < leftParts.length ? leftParts[i] : 0;
    final rightPart = i < rightParts.length ? rightParts[i] : 0;
    if (leftPart != rightPart) {
      return leftPart.compareTo(rightPart);
    }
  }
  return 0;
}

bool isNewerAppVersion(String candidate, String current) {
  return compareAppVersions(candidate, current) > 0;
}
