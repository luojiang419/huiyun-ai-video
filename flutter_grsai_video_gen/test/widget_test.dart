import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/main.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/screens/home_screen.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

class _NoopUpdateService extends UpdateService {
  _NoopUpdateService() : super(updateJsonUrl: 'http://127.0.0.1');

  @override
  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
    bool includeSkipped = false,
  }) async {
    return null;
  }
}

void main() {
  testWidgets('app boots smoke test', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateServiceProvider.overrideWithValue(_NoopUpdateService()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
