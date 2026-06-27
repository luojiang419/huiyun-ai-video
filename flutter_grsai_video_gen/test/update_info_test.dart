import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';

void main() {
  test('compares V-style app versions', () {
    expect(compareAppVersions('V6.8', 'V6.9'), lessThan(0));
    expect(compareAppVersions('V6.10', 'V6.9'), greaterThan(0));
    expect(compareAppVersions('V6.9', '6.9.0'), 0);
    expect(isNewerAppVersion('V6.10', 'V6.9'), isTrue);
    expect(isNewerAppVersion('V6.9', 'V6.9'), isFalse);
  });

  test('parses update manifest', () {
    final info = UpdateInfo.fromJson({
      'version': 'V6.9',
      'installerName': '影视版-安装包-V6.9.exe',
      'installerUrl': 'https://example.com/installer.exe',
      'sha256': 'abc123',
      'size': 1024,
      'publishedAt': '2026-06-14T00:00:00Z',
      'releaseNotes': '更新说明',
      'mandatory': false,
    });

    expect(info.version, 'V6.9');
    expect(info.sha256, 'ABC123');
    expect(info.sizeLabel, '0.0 MB');
  });

  test('rejects malformed update manifest', () {
    expect(
      () => UpdateInfo.fromJson({
        'version': 'V6.9',
        'installerName': '',
        'installerUrl': 'https://example.com/installer.exe',
        'sha256': 'abc123',
        'size': 1024,
        'publishedAt': '2026-06-14T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
