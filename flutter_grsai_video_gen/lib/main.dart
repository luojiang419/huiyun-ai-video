import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/app_version.dart';
import 'screens/home_screen.dart';
import 'services/file_service.dart';
import 'services/config_file_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
