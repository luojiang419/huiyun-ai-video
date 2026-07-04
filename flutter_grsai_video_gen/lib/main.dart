import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/app_version.dart';
import 'models/update_install_session.dart';
import 'screens/home_screen.dart';
import 'screens/update_installer_screen.dart';
import 'services/file_service.dart';
import 'services/config_file_service.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final updateLaunchArgs = UpdateInstallSessionLaunchArgs.tryParse(
    Platform.executableArguments,
  );
  if (updateLaunchArgs != null) {
    await _runUpdateInstallerMode(updateLaunchArgs);
    return;
  }

  final updateService = UpdateService();
  await updateService.acknowledgeCompletedUpdateOnStartup(
    currentVersion: appReleaseVersion,
  );
  final shouldExitForScheduledUpdate = await updateService
      .tryApplyScheduledUpdateOnStartup(currentVersion: appReleaseVersion);
  if (shouldExitForScheduledUpdate) {
    return;
  }

  await _runMainApplication();
}

Future<void> _runUpdateInstallerMode(
  UpdateInstallSessionLaunchArgs launchArgs,
) async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(760, 520),
    minimumSize: Size(760, 520),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: '绘云AI 更新安装器',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ProviderScope(child: UpdateInstallerApp(launchArgs: launchArgs)),
  );
}

Future<void> _runMainApplication() async {
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  // 初始化文件夹和配置文件
  final fileService = FileService();
  await fileService.initDirectories();

  final configService = ConfigFileService();
  await configService.initConfigFiles();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1300, 760),
    minimumSize: Size(1300, 760),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: appDisplayTitle,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a1a1a),
        primaryColor: const Color(0xFF4a9eff),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4a9eff),
          secondary: Color(0xFF6c757d),
          surface: Color(0xFF1e1e1e),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
