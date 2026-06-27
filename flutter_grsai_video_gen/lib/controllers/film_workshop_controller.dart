import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/film_project_provider.dart';
import '../providers/generate_provider.dart';
import '../services/film_workshop_service.dart';
import '../services/generate_logic_service.dart';
import '../models/shot.dart';
import '../utils/error_translator.dart';

final filmWorkshopControllerProvider = Provider(
  (ref) => FilmWorkshopController(ref),
);

class FilmWorkshopController {
  final Ref _ref;
  late final FilmWorkshopService _service;

  FilmWorkshopController(this._ref) {
    _service = FilmWorkshopService(_ref.read(apiServiceProvider));
  }

  Future<void> generateShots({
    required List<int> taskIndices,
    required String selectedStoryboard,
    required String selectedModel,
    required String selectedAspectRatio,
    required String selectedImageSize,
    required String selectedImageQuality,
    int? sampleSteps,
    required List<String> referenceImages, // Paths
    required Map<int, String> imageRemarks,
  }) async {
    // Determine batch number (shared for this batch)
    final projectName = selectedStoryboard
        .replaceAll('.txt', '')
        .replaceAll('.json', '');
    final batchNumber = _service.getNextBatchNumber(projectName);

    _ref.read(filmProjectProvider.notifier).startGeneration();

    await Future.wait(
      taskIndices.map((index) async {
        if (index > 0) {
          await Future<void>.delayed(Duration(milliseconds: index * 200));
        }
        try {
          _ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabShotStatus(index, '生成中');

          await _generateSingleShotInternal(
            index: index,
            projectName: projectName,
            batchNumber: batchNumber,
            selectedModel: selectedModel,
            selectedAspectRatio: selectedAspectRatio,
            selectedImageSize: selectedImageSize,
            selectedImageQuality: selectedImageQuality,
            sampleSteps: sampleSteps,
            referenceImages: referenceImages,
            imageRemarks: imageRemarks,
          );
        } catch (e) {
          debugPrint('Error generating shot $index: $e');
          _ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabShotStatus(index, '失败');
          _ref.read(filmProjectProvider.notifier).incrementFailed();
        } finally {
          _checkAndFinishGeneration();
        }
      }),
    );
  }

  Future<void> _generateSingleShotInternal({
    required int index,
    required String projectName,
    required int batchNumber,
    required String selectedModel,
    required String selectedAspectRatio,
    required String selectedImageSize,
    required String selectedImageQuality,
    int? sampleSteps,
    required List<String> referenceImages,
    required Map<int, String> imageRemarks,
  }) async {
    final projectState = _ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || index >= currentTab.shots.length) return;
    final shot = currentTab.shots[index];
    final taskRequest = buildShotGenerationTask(
      shot: shot,
      selectedModel: selectedModel,
      selectedAspectRatio: selectedAspectRatio,
      selectedImageSize: selectedImageSize,
      selectedImageQuality: selectedImageQuality,
      sampleSteps: sampleSteps,
      referenceImages: referenceImages,
      imageRemarks: imageRemarks,
    );

    // Start Timer
    final startTime = DateTime.now();
    Timer? shotTimer;
    shotTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      _ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabShotTimer(index, elapsed);
    });

    String? localPath;
    try {
      final generatedResults = await _ref
          .read(generateLogicServiceProvider)
          .runImageTask(taskRequest);
      if (generatedResults.isNotEmpty) {
        localPath = generatedResults.first;
      }
    } catch (e) {
      final translatedError = ErrorTranslator.translate(e.toString());
      _ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabShotStatus(index, '失败: $translatedError');
      _ref.read(filmProjectProvider.notifier).incrementFailed();
      return;
    } finally {
      shotTimer.cancel();
    }

    if (localPath != null) {
      try {
        final savedPath = await _service.saveGeneratedImage(
          imageUrl: localPath,
          projectName: projectName,
          batchNumber: batchNumber,
          shotNumber: index + 1,
        );

        _ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotStatus(index, '已完成');
        _ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotImage(index, savedPath);
        _ref.read(filmProjectProvider.notifier).incrementSuccess();
      } catch (e) {
        debugPrint('Error saving image: $e');
        _ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotStatus(index, '保存失败');
        _ref.read(filmProjectProvider.notifier).incrementFailed();
      }
    } else {
      _ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabShotStatus(index, '生成失败');
      _ref.read(filmProjectProvider.notifier).incrementFailed();
    }
  }

  @visibleForTesting
  static GenerateImageTaskRequest buildShotGenerationTask({
    required Shot shot,
    required String selectedModel,
    required String selectedAspectRatio,
    required String selectedImageSize,
    required String selectedImageQuality,
    int? sampleSteps,
    required List<String> referenceImages,
    required Map<int, String> imageRemarks,
  }) {
    final boundReferenceImages = buildBoundReferenceImages(shot);
    final cleanPrompt = cleanShotPrompt(shot.prompt);

    final assetsMapping = buildReferenceMappings(
      boundReferenceImages,
      referenceImages: referenceImages,
      imageRemarks: imageRemarks,
      assetRemarks: shot.assetRemarks,
    );

    final details = <String>[];
    void addIfNotEmpty(String label, String value) {
      if (value.isNotEmpty && value != '无') {
        details.add('[$label]：$value');
      }
    }

    addIfNotEmpty('景别', shot.shotType);
    addIfNotEmpty('视角与摄影机', shot.cameraAngle);
    addIfNotEmpty('光影氛围', shot.lighting);
    addIfNotEmpty('场景基础描述', shot.sceneDescription);
    addIfNotEmpty('场景细节描述', shot.sceneDetails);
    addIfNotEmpty('画面文字', shot.textInFrame);
    addIfNotEmpty('物体状态', shot.objectState);
    addIfNotEmpty('角色名称', shot.characterName);
    addIfNotEmpty('服装化妆', shot.costume);
    addIfNotEmpty('人物动作', shot.action);
    addIfNotEmpty('人物表情', shot.expression);
    addIfNotEmpty('使用道具', shot.props);
    addIfNotEmpty('运镜', shot.movement);
    addIfNotEmpty('画面描述', cleanPrompt);

    final finalPromptParts = <String>[];
    if (assetsMapping.isNotEmpty) {
      finalPromptParts.add(assetsMapping);
    }
    if (details.isNotEmpty) {
      finalPromptParts.add(details.join('，'));
    }

    return GenerateImageTaskRequest(
      prompt: finalPromptParts.join(' '),
      model: selectedModel,
      aspectRatio: selectedAspectRatio,
      imageSize: selectedImageSize,
      imageQuality: selectedImageQuality,
      sampleSteps: sampleSteps,
      referenceImagePaths: boundReferenceImages,
    );
  }

  @visibleForTesting
  static String cleanShotPrompt(String prompt) {
    String cleanPrompt = prompt;
    final mappingRegex = RegExp(r'.*?是第\d+张提供的图片\[Image\d+\].*?[,，。]?\s*');
    while (mappingRegex.hasMatch(cleanPrompt)) {
      cleanPrompt = cleanPrompt.replaceFirst(mappingRegex, '');
    }
    cleanPrompt = cleanPrompt
        .replaceAll(',,', ',')
        .replaceAll('，，', '，')
        .replaceAll('。。', '。')
        .trim();
    if (cleanPrompt.startsWith(',')) {
      cleanPrompt = cleanPrompt.substring(1).trim();
    }
    if (cleanPrompt.startsWith('，')) {
      cleanPrompt = cleanPrompt.substring(1).trim();
    }
    if (cleanPrompt.startsWith('。')) {
      cleanPrompt = cleanPrompt.substring(1).trim();
    }
    return cleanPrompt;
  }

  @visibleForTesting
  static List<String> buildBoundReferenceImages(Shot shot) {
    final source = shot.manualReferenceImages.isNotEmpty
        ? shot.manualReferenceImages
        : shot.referenceImagePaths;
    final seen = <String>{};
    final result = <String>[];
    for (final imagePath in source) {
      final trimmed = imagePath.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      result.add(trimmed);
    }
    return result;
  }

  @visibleForTesting
  static String buildReferenceMappings(
    List<String> boundReferenceImages, {
    required List<String> referenceImages,
    required Map<int, String> imageRemarks,
    Map<String, String>? assetRemarks,
  }) {
    final mappings = <String>[];
    for (int i = 0; i < boundReferenceImages.length; i++) {
      final imagePath = boundReferenceImages[i];
      final remark = resolveReferenceRemark(
        imagePath,
        referenceImages: referenceImages,
        imageRemarks: imageRemarks,
        assetRemarks: assetRemarks,
      );
      mappings.add('$remark是第${i + 1}张提供的图片[Image${i + 1}]');
    }
    return mappings.join('，');
  }

  @visibleForTesting
  static String resolveReferenceRemark(
    String imagePath, {
    required List<String> referenceImages,
    required Map<int, String> imageRemarks,
    Map<String, String>? assetRemarks,
  }) {
    var remark = assetRemarks?[imagePath]?.trim() ?? '';
    if (remark.isEmpty) {
      final index = referenceImages.indexOf(imagePath);
      if (index != -1) {
        remark = imageRemarks[index]?.trim() ?? '';
      }
    }
    if (remark.isEmpty ||
        remark.startsWith('参考图') ||
        RegExp(r'^参考图\d+$').hasMatch(remark)) {
      return '参考图';
    }
    return remark;
  }

  void _checkAndFinishGeneration() {
    final projectState = _ref.read(filmProjectProvider);
    if (!projectState.isGenerating) return;

    final project = projectState.currentProject;
    if (project == null) return;

    bool hasGenerating = false;
    for (final tab in project.tabs) {
      for (final status in tab.shotStatus.values) {
        if (status == '生成中') {
          hasGenerating = true;
          break;
        }
      }
      if (hasGenerating) break;
    }

    if (!hasGenerating) {
      _ref.read(filmProjectProvider.notifier).finishGeneration();
    }
  }
}
