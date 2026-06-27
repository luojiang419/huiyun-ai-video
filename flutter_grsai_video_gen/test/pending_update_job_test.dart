import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';

void main() {
  test('pending update job round-trips through json', () {
    const job = PendingUpdateJob(
      info: UpdateInfo(
        version: 'V8.9',
        installerName: '影视版-安装包-V8.9.exe',
        installerUrl: 'https://example.com/installer.exe',
        sha256: 'ABC123',
        size: 2048,
        publishedAt: '2026-06-27T00:00:00Z',
        releaseNotes: '更新说明',
        mandatory: false,
      ),
      installerPath: r'D:\Program Files\VideoGen\downloads\影视版-安装包-V8.9.exe',
      sha256: 'ABC123',
      downloadedAt: '2026-06-27T00:00:00Z',
      status: PendingUpdateStatus.scheduled,
      installOnNextLaunch: true,
      promptOnNextLaunch: true,
      lastFailureReason: '',
    );

    final decoded = PendingUpdateJob.fromJson(job.toJson());

    expect(decoded.targetVersion, 'V8.9');
    expect(decoded.installerName, '影视版-安装包-V8.9.exe');
    expect(decoded.status, PendingUpdateStatus.scheduled);
    expect(decoded.installOnNextLaunch, isTrue);
    expect(decoded.promptOnNextLaunch, isTrue);
    expect(decoded.info.releaseNotes, '更新说明');
  });

  test('pending update status parser keeps known values', () {
    expect(
      pendingUpdateStatusFromValue('installing'),
      PendingUpdateStatus.installing,
    );
    expect(pendingUpdateStatusFromValue('failed'), PendingUpdateStatus.failed);
    expect(
      pendingUpdateStatusFromValue('unknown'),
      PendingUpdateStatus.downloaded,
    );
  });
}
