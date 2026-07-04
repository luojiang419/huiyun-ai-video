import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/update_install_session.dart';

void main() {
  test('update install session round-trips through json', () {
    const session = UpdateInstallSession(
      sessionId: 'session-1',
      targetVersion: 'V8.9',
      installerPath: r'C:\Temp\installer.exe',
      installerSha256: 'ABC123',
      installDir: r'D:\Program Files\VideoGen',
      executableName: 'flutter_grsai_image_gen.exe',
      targetExecutablePath:
          r'D:\Program Files\VideoGen\flutter_grsai_image_gen.exe',
      stagedRuntimeDir:
          r'D:\Program Files\VideoGen\data\.system_update\staging\session-1\runtime',
      stagedExecutablePath:
          r'D:\Program Files\VideoGen\data\.system_update\staging\session-1\runtime\flutter_grsai_image_gen.exe',
      pendingUpdateFilePath:
          r'D:\Program Files\VideoGen\data\.system_update\pending_update.json',
      sourcePendingUpdateFilePath:
          r'G:\data\app\AI\实测输出\install\data\.system_update\pending_update.json',
      resultFilePath:
          r'D:\Program Files\VideoGen\data\.system_update\results\session-1.json',
      ackFilePath:
          r'D:\Program Files\VideoGen\data\.system_update\acks\session-1.ack',
      logFilePath:
          r'D:\Program Files\VideoGen\data\.system_update\logs\session-1.log',
      createdAt: '2026-06-27T00:00:00Z',
      parentPid: 1234,
      status: UpdateInstallSessionStatus.installing,
      lastError: '',
    );

    final decoded = UpdateInstallSession.fromJson(session.toJson());

    expect(decoded.sessionId, 'session-1');
    expect(decoded.targetVersion, 'V8.9');
    expect(decoded.parentPid, 1234);
    expect(decoded.status, UpdateInstallSessionStatus.installing);
    expect(decoded.executableName, 'flutter_grsai_image_gen.exe');
    expect(
      decoded.sourcePendingUpdateFilePath,
      r'G:\data\app\AI\实测输出\install\data\.system_update\pending_update.json',
    );
  });

  test(
    'update install session launch args parser keeps both required args',
    () {
      final parsed = UpdateInstallSessionLaunchArgs.tryParse([
        '--foo=bar',
        '--run-update-session=session-1',
        r'--update-session-file=C:\Temp\session-1.json',
      ]);

      expect(parsed, isNotNull);
      expect(parsed!.sessionId, 'session-1');
      expect(parsed.sessionFilePath, r'C:\Temp\session-1.json');
    },
  );
}
