import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/screens/about_screen.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

class _NoopUpdateService extends UpdateService {
  _NoopUpdateService() : super(updateJsonUrl: 'http://127.0.0.1');

  int checkCount = 0;

  @override
  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
    bool includeSkipped = false,
  }) async {
    checkCount++;
    return null;
  }
}

void main() {
  testWidgets('about screen can manually check updates', (tester) async {
    final service = _NoopUpdateService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [updateServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: Scaffold(body: AboutScreen())),
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.checkCount, 1);
  });
}
