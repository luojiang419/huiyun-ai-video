import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/film_project.dart';

class FilmWorkshopStorageService {
  Future<void> saveWorkshopState({
    required Map<String, List<String>> referenceImages,
    required String? selectedStoryboard,
    Map<String, String>? imageRemarks,
    List<Map<String, dynamic>>? shots,
    Map<String, String>? shotStatus,
    Map<String, String?>? shotImages,
    Map<String, int>? shotTimer,
    List<Map<String, dynamic>>? sceneAssets,
    String? selectedModel,
    String? selectedAspectRatio,
    String? selectedImageSize,
    String? selectedImageQuality,
    int? sampleSteps,
    String? lastScriptContent,
    String? fullScript,
  }) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'film_workshop_state.json'),
      );
      if (!await stateFile.parent.exists()) {
        await stateFile.parent.create(recursive: true);
      }

      final state = {
        'referenceImages': referenceImages,
        'selectedStoryboard': selectedStoryboard,
        'imageRemarks': imageRemarks,
        'shots': shots,
        'shotStatus': shotStatus,
        'shotImages': shotImages,
        'shotTimer': shotTimer,
        'sceneAssets': sceneAssets,
        'selectedModel': selectedModel,
        'selectedAspectRatio': selectedAspectRatio,
        'selectedImageSize': selectedImageSize,
        'selectedImageQuality': selectedImageQuality,
        'sampleSteps': sampleSteps,
        'lastScriptContent': lastScriptContent,
        'fullScript': fullScript,
      };

      await stateFile.writeAsString(jsonEncode(state));
    } catch (e) {
      // 忽略保存错误
    }
  }

  Future<Map<String, dynamic>?> loadWorkshopState() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'film_workshop_state.json'),
      );

      if (!await stateFile.exists()) return null;

      final content = await stateFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveStoryboardState({
    required String projectName,
    required String artStyle,
    required String worldView,
    required String aspectRatio,
    required String script,
    required String result,
  }) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'storyboard_state.json'),
      );
      await stateFile.parent.create(recursive: true);

      final state = {
        'projectName': projectName,
        'artStyle': artStyle,
        'worldView': worldView,
        'aspectRatio': aspectRatio,
        'script': script,
        'result': result,
      };

      await stateFile.writeAsString(jsonEncode(state));
    } catch (e) {
      // 忽略保存错误
    }
  }

  Future<Map<String, dynamic>?> loadStoryboardState() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'storyboard_state.json'),
      );

      if (!await stateFile.exists()) return null;

      final content = await stateFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveProjectState(FilmProject project) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'film_project_state.json'),
      );
      await stateFile.parent.create(recursive: true);
      await stateFile.writeAsString(jsonEncode(project.toJson()));
    } catch (e) {
      // 忽略保存错误
    }
  }

  Future<String> loadSystemPrompt(String defaultPrompt) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final file = File(
        path.join(
          appDir.path,
          'data',
          'Settings',
          'storyboard_system_prompt.txt',
        ),
      );
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) return content;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(defaultPrompt);
    } catch (e) {
      // ignore
    }
    return defaultPrompt;
  }

  Future<void> saveSystemPrompt(String content) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final file = File(
        path.join(
          appDir.path,
          'data',
          'Settings',
          'storyboard_system_prompt.txt',
        ),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (e) {
      // ignore
    }
  }

  Future<FilmProject?> loadProjectState() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final stateFile = File(
        path.join(appDir.path, 'data', 'Settings', 'film_project_state.json'),
      );

      if (!await stateFile.exists()) return null;

      final content = await stateFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return FilmProject.fromJson(json);
    } catch (e) {
      return null;
    }
  }
}
