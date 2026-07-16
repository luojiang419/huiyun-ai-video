import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/constants/update_config.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';

void main() {
  UpdateInfo info({
    String version = 'V10.0.1',
    String? installerName,
    String? installerUrl,
    String sha256 =
        '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF',
    int size = 1024,
  }) {
    final name = installerName ?? UpdateConfig.expectedInstallerName(version);
    return UpdateInfo(
      version: version,
      installerName: name,
      installerUrl:
          installerUrl ??
          'https://github.com/${UpdateConfig.releaseRepo}/releases/download/$version/$name',
      sha256: sha256,
      size: size,
      publishedAt: '2026-07-16T00:00:00Z',
      releaseNotes: '测试更新',
      mandatory: false,
      sourceSha: '0123456789abcdef0123456789abcdef01234567',
    );
  }

  test('production manifest matches exact version asset and GitHub URL', () {
    expect(
      () => UpdateConfig.validateProductionManifest(info()),
      returnsNormally,
    );
  });

  test('production manifest rejects two-part or prerelease-like versions', () {
    expect(
      () => UpdateConfig.validateProductionManifest(info(version: 'V10.1')),
      throwsFormatException,
    );
  });

  test('production manifest rejects a fuzzy or wrong asset name', () {
    expect(
      () => UpdateConfig.validateProductionManifest(
        info(installerName: 'another-installer.exe'),
      ),
      throwsFormatException,
    );
  });

  test('production manifest rejects a different repository URL', () {
    expect(
      () => UpdateConfig.validateProductionManifest(
        info(
          installerUrl:
              'https://github.com/example/other/releases/download/V10.0.1/HuiYunAI-VideoGen-Setup-V10.0.1.exe',
        ),
      ),
      throwsFormatException,
    );
  });

  test('production manifest rejects zero size and invalid digest', () {
    expect(
      () => UpdateConfig.validateProductionManifest(info(size: 0)),
      throwsFormatException,
    );
    expect(
      () => UpdateConfig.validateProductionManifest(info(sha256: 'ABC123')),
      throwsFormatException,
    );
  });
}
