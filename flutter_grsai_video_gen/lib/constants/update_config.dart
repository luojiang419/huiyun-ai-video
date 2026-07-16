import '../models/update_info.dart';

class UpdateConfig {
  static const String releaseRepo = 'luojiang419/huiyun-ai-video-releases';
  static const String releaseApiUrl =
      'https://api.github.com/repos/$releaseRepo/releases/latest';
  static const String latestManifestUrl =
      'https://github.com/$releaseRepo/releases/latest/download/update.json';
  static const String installerPrefix = 'HuiYunAI-VideoGen-Setup-';

  static String expectedInstallerName(String version) {
    return '$installerPrefix$version.exe';
  }

  static void validateProductionManifest(UpdateInfo info) {
    if (!RegExp(
      r'^V\d+\.\d+\.\d+$',
      caseSensitive: false,
    ).hasMatch(info.version)) {
      throw FormatException('更新版本必须是稳定三段版本号: ${info.version}');
    }

    final expectedName = expectedInstallerName(info.version);
    if (info.installerName != expectedName) {
      throw FormatException(
        '安装包名称不符合发布契约，期望 $expectedName，实际 ${info.installerName}',
      );
    }
    if (!RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(info.sha256)) {
      throw const FormatException('安装包 SHA-256 必须是 64 位十六进制字符串');
    }
    if (info.size <= 0) {
      throw const FormatException('安装包大小必须大于 0');
    }

    final uri = Uri.tryParse(info.installerUrl);
    final expectedSegments = [
      'luojiang419',
      'huiyun-ai-video-releases',
      'releases',
      'download',
      info.version,
      expectedName,
    ];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.pathSegments.length != expectedSegments.length) {
      throw const FormatException('安装包 URL 不是允许的 GitHub Release 地址');
    }
    for (var index = 0; index < expectedSegments.length; index++) {
      if (uri.pathSegments[index] != expectedSegments[index]) {
        throw const FormatException('安装包 URL 与版本或资产名称不一致');
      }
    }
  }
}
