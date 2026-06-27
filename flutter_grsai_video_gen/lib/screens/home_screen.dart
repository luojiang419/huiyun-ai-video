import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../widgets/navigation_sidebar.dart';
import '../widgets/reference_sidebar.dart';
// BackgroundTaskBar 已移至 NavigationSidebar 内部
import '../providers/api_config_provider.dart';
import '../services/generate_logic_service.dart';
import '../services/config_file_service.dart';
import '../providers/generate_params_provider.dart';
import '../providers/video_config_provider.dart';
import '../providers/video_gallery_provider.dart';
import '../providers/video_node_provider.dart';
import '../providers/update_provider.dart';
import '../widgets/update_prompt_dialog.dart';
import 'film_workshop_wrapper.dart';
import 'generate_screen.dart';
import 'video_generate_screen.dart';
import 'asset_library_screen.dart';
import 'storyboard_gallery_screen.dart';
import 'gallery_screen.dart';
import 'api_config_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  final TextEditingController _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(apiConfigsProvider);
      ref.read(videoSettingsProvider);
      ref.read(videoGalleryProvider);
      ref.read(videoNodesProvider.notifier).refreshStatuses();
      _autoLaunchWan2gp();
      _handleStartupUpdateFlow();
    });
  }

  Future<void> _handleStartupUpdateFlow() async {
    final job = await ref.read(updateProvider.notifier).prepareStartupUpdate();
    if (!mounted || job == null) return;
    await showUpdatePromptDialog(context: context, job: job);
  }

  Future<void> _autoLaunchWan2gp() async {
    final settings = await ConfigFileService().loadVideoSettingsConfig();
    if (!settings.wan2gp.autoLaunch) return;
    if (settings.wan2gp.scriptPath.trim().isEmpty) return;
    final pythonFile = File(settings.wan2gp.pythonPath);
    final scriptFile = File(settings.wan2gp.scriptPath);
    if (!pythonFile.existsSync() || !scriptFile.existsSync()) return;
    await ref
        .read(wan2gpBridgeServiceProvider)
        .launch(
          pythonPath: settings.wan2gp.pythonPath,
          scriptPath: settings.wan2gp.scriptPath,
          port: settings.wan2gp.port,
        );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          NavigationSidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
          if (_selectedIndex == 1)
            ReferenceSidebar(
              promptController: _promptController,
              onRepaintGenerate:
                  (prompt, imagePath, {Uint8List? croppedBytes}) async {
                    debugPrint(
                      '[HomeScreen] onRepaintGenerate: croppedBytes=${croppedBytes != null ? "${croppedBytes.length} bytes" : "null"}',
                    );
                    final configs = ref.read(apiConfigsProvider);
                    if (configs.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请先配置API')),
                        );
                      }
                      return;
                    }
                    String base64Str;
                    String refPath = imagePath;
                    if (croppedBytes != null) {
                      base64Str = base64Encode(croppedBytes);
                    } else {
                      final file = File(imagePath);
                      if (!await file.exists()) return;
                      final bytes = await file.readAsBytes();
                      base64Str = base64Encode(bytes);
                    }
                    final params = ref.read(generateParamsProvider);
                    ref
                        .read(generateLogicServiceProvider)
                        .generate(
                          prompt: prompt,
                          model: params.model,
                          aspectRatio: params.aspectRatio,
                          imageSize: params.imageSize,
                          imageQuality: params.imageQuality,
                          sampleSteps: params.sampleSteps,
                          referenceImages: [base64Str],
                          referenceImagePaths: [refPath],
                        );
                  },
            ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const FilmWorkshopWrapper(),
                GenerateScreen(
                  promptController: _promptController,
                  dropEnabled: _selectedIndex == 1,
                ),
                const VideoGenerateScreen(),
                AssetLibraryScreen(dropEnabled: _selectedIndex == 3),
                const StoryboardGalleryScreen(),
                const GalleryScreen(),
                const ApiConfigScreen(),
                const SettingsScreen(),
                const AboutScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
