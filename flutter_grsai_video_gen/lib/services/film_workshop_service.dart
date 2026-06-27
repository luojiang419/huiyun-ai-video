import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/asset.dart';
import '../models/film_scene_asset.dart';
import '../models/shot.dart';
import 'api_service.dart';

class FilmReferenceImageAnalysis {
  final String imagePath;
  final String displayName;
  final String assetName;
  final String assetCategory;
  final String assetDescription;
  final String imageDescription;
  final String visualDescription;

  const FilmReferenceImageAnalysis({
    required this.imagePath,
    required this.displayName,
    this.assetName = '',
    this.assetCategory = '',
    this.assetDescription = '',
    this.imageDescription = '',
    this.visualDescription = '',
  });

  FilmReferenceImageAnalysis copyWith({
    String? imagePath,
    String? displayName,
    String? assetName,
    String? assetCategory,
    String? assetDescription,
    String? imageDescription,
    String? visualDescription,
  }) {
    return FilmReferenceImageAnalysis(
      imagePath: imagePath ?? this.imagePath,
      displayName: displayName ?? this.displayName,
      assetName: assetName ?? this.assetName,
      assetCategory: assetCategory ?? this.assetCategory,
      assetDescription: assetDescription ?? this.assetDescription,
      imageDescription: imageDescription ?? this.imageDescription,
      visualDescription: visualDescription ?? this.visualDescription,
    );
  }

  String get effectiveName {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    return path.basenameWithoutExtension(imagePath);
  }

  String get matchDescription {
    final parts = <String>[
      '名称/备注: $effectiveName',
      '文件名: ${path.basename(imagePath)}',
    ];
    if (assetName.trim().isNotEmpty) {
      parts.add('所属资产: ${assetName.trim()}');
    }
    if (assetCategory.trim().isNotEmpty) {
      parts.add('资产类别: ${assetCategory.trim()}');
    }
    if (assetDescription.trim().isNotEmpty) {
      parts.add(
        '资产说明: ${_compactPromptText(assetDescription, maxLength: 220)}',
      );
    }
    if (imageDescription.trim().isNotEmpty) {
      parts.add(
        '图片视图说明: ${_compactPromptText(imageDescription, maxLength: 220)}',
      );
    }
    if (visualDescription.trim().isNotEmpty) {
      parts.add(
        '视觉模型解析: ${_compactPromptText(visualDescription, maxLength: 900)}',
      );
    }
    return parts.join('；');
  }
}

String _compactPromptText(String value, {int maxLength = 1200}) {
  final compacted = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compacted.length <= maxLength) return compacted;
  return '${compacted.substring(0, maxLength)}...';
}

class FilmWorkshopService {
  final ApiService _apiService;
  final Dio _dio = Dio();
  static final RegExp _genericCostumePattern = RegExp(
    r'外套|御寒衣|冬衣|破衣|衣服|便装|工装|工作服|夹克|羽绒服|大衣|披肩|围巾|制服|西装|长袍|披风|斗篷|盔甲|铠甲|婚纱|戏服|旗袍|校服|军装',
    caseSensitive: false,
  );
  static final RegExp _distinctiveCostumePattern = RegExp(
    r'红|橙|黄|绿|青|蓝|紫|黑|白|灰|棕|金|银|粉|条纹|格纹|刺绣|徽章|花纹|图腾|logo|皮革|毛领|羽绒|铆钉|补丁|破洞|血迹|婚纱|戏服|旗袍|校服|军装|披风|斗篷|盔甲|铠甲|头盔|面罩',
    caseSensitive: false,
  );
  static final RegExp _wrapperCostumePattern = RegExp(
    r'包裹|裹住|包住|覆盖|遮住',
    caseSensitive: false,
  );
  static final RegExp _transientPropPattern = RegExp(
    r'树枝|木屑|野菜|柴火|火苗|碎石|沟壑|残骸|积雪|雪花|瓦砾|垃圾|灰烬',
    caseSensitive: false,
  );
  static final RegExp _corePropPattern = RegExp(
    r'摩托车|汽车|卡车|自行车|背包|雪人|种子|钢管|枪|刀|剑|钥匙|手机|相机|项链|戒指|地图|信件|面具|箱|行李|书|乐器|机器人',
    caseSensitive: false,
  );

  FilmWorkshopService(this._apiService);

  static String sanitizeAssetFileName(
    String value, {
    String fallback = '未命名资产',
  }) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'_+'), '_')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static String buildSceneAssetFileName(String assetName, String viewName) {
    return '${sanitizeAssetFileName(assetName)}-${sanitizeAssetFileName(viewName, fallback: '视图')}.png';
  }

  static String normalizeSceneAssetCategory(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.contains('人物') ||
        text.contains('角色') ||
        text.contains('character') ||
        text.contains('person')) {
      return 'Person';
    }
    if (text.contains('场景') ||
        text.contains('环境') ||
        text.contains('scene') ||
        text.contains('location')) {
      return 'Scene';
    }
    if (text.contains('服装') ||
        text.contains('妆造') ||
        text.contains('costume') ||
        text.contains('clothing')) {
      return 'Costume';
    }
    if (text.contains('道具') ||
        text.contains('物品') ||
        text.contains('prop') ||
        text.contains('object')) {
      return 'Prop';
    }
    return 'Other';
  }

  static List<int> _parseSourceShotIndexes(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
  }

  static String _extractJsonCandidate(String content) {
    final assetsMarker = content.lastIndexOf('"assets"');
    if (assetsMarker != -1) {
      final start = content.lastIndexOf('{', assetsMarker);
      if (start != -1) {
        final end = _findStaticMatchingBrace(content, start);
        if (end != -1) return content.substring(start, end + 1);
      }
    }

    final arrayStart = content.indexOf('[');
    if (arrayStart != -1) {
      final arrayEnd = content.lastIndexOf(']');
      if (arrayEnd > arrayStart) {
        return content.substring(arrayStart, arrayEnd + 1);
      }
    }

    final objectStart = content.indexOf('{');
    if (objectStart != -1) {
      final objectEnd = _findStaticMatchingBrace(content, objectStart);
      if (objectEnd != -1) return content.substring(objectStart, objectEnd + 1);
    }
    return content;
  }

  static int _findStaticMatchingBrace(String content, int startIndex) {
    var depth = 0;
    var inString = false;
    var escaping = false;
    for (var i = startIndex; i < content.length; i++) {
      final char = content[i];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (char == '\\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static dynamic _decodeSceneAssetExtractionJson(String content) {
    final candidate = _extractJsonCandidate(content);
    try {
      return jsonDecode(candidate);
    } on FormatException catch (error) {
      final repairedCandidate = _extractJsonCandidate(
        _repairSceneAssetExtractionJson(content),
      );
      if (repairedCandidate == candidate) {
        throw error;
      }
      try {
        return jsonDecode(repairedCandidate);
      } on FormatException {
        throw error;
      }
    }
  }

  static String _repairSceneAssetExtractionJson(String content) {
    var repaired = content.trim();
    repaired = repaired.replaceAllMapped(
      RegExp(r'\\+([{}\[\],:])'),
      (match) => match.group(1)!,
    );
    repaired = repaired.replaceAll(r'\"', '"');
    repaired = repaired.replaceAllMapped(
      RegExp(
        r'"(name|label|asset|category|type|description|prompt|visualDescription)([^":,{}\[\]]+)"',
      ),
      (match) {
        final key = match.group(1)!;
        final value = match.group(2)!.trim();
        if (value.isEmpty) return match.group(0)!;
        return '"$key":"$value"';
      },
    );
    return repaired.replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (match) => match.group(1)!,
    );
  }

  static List<FilmSceneAsset> parseSceneAssetExtraction(String content) {
    final decoded = _decodeSceneAssetExtractionJson(content);
    final rawAssets = decoded is List
        ? decoded
        : decoded is Map
        ? (decoded['assets'] as List? ??
              decoded['sceneAssets'] as List? ??
              const [])
        : const [];

    final byKey = <String, FilmSceneAsset>{};
    var order = 0;
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final name = (map['name'] ?? map['label'] ?? map['asset'] ?? '')
          .toString()
          .trim();
      if (name.isEmpty) continue;

      final category = normalizeSceneAssetCategory(
        map['category'] ?? map['type'],
      );
      final description =
          (map['description'] ??
                  map['prompt'] ??
                  map['visualDescription'] ??
                  '')
              .toString()
              .trim();
      final sourceShotIndexes = _parseSourceShotIndexes(
        map['sourceShotIndexes'] ??
            map['source_shot_indexes'] ??
            map['shotIndexes'] ??
            map['shots'],
      );
      final key = '$category|${name.toLowerCase()}';
      final existing = byKey[key];
      if (existing == null) {
        final safeName = sanitizeAssetFileName(name, fallback: 'asset');
        byKey[key] = FilmSceneAsset(
          id: 'scene_asset_${category}_${safeName}_$order',
          name: name,
          category: category,
          description: description,
          sourceShotIndexes: sourceShotIndexes,
        );
        order++;
      } else {
        final mergedShotIndexes = {
          ...existing.sourceShotIndexes,
          ...sourceShotIndexes,
        }.toList()..sort();
        byKey[key] = existing.copyWith(
          sourceShotIndexes: mergedShotIndexes,
          description: existing.description.length >= description.length
              ? existing.description
              : description,
        );
      }
    }
    return _refineSceneAssets(byKey.values.toList());
  }

  static List<FilmSceneAsset> _refineSceneAssets(List<FilmSceneAsset> assets) {
    final anchorNames = assets
        .where((asset) => asset.category != 'Costume')
        .map((asset) => asset.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final refined = <FilmSceneAsset>[];
    for (final asset in assets) {
      if (_shouldDropSceneAsset(asset, anchorNames)) {
        continue;
      }
      refined.add(
        asset.copyWith(
          name: asset.name.replaceAll(RegExp(r'\s+'), ' ').trim(),
          description: asset.description.trim(),
        ),
      );
    }
    return refined;
  }

  static bool _shouldDropSceneAsset(
    FilmSceneAsset asset,
    Set<String> anchorNames,
  ) {
    if (asset.name.trim().isEmpty) {
      return true;
    }
    if (asset.category == 'Costume' &&
        _isGenericLinkedCostume(asset, anchorNames)) {
      return true;
    }
    if (asset.category == 'Prop' && _isTransientPropAsset(asset)) {
      return true;
    }
    return false;
  }

  static bool _isGenericLinkedCostume(
    FilmSceneAsset asset,
    Set<String> anchorNames,
  ) {
    final text = '${asset.name} ${asset.description}'.trim();
    if (!_genericCostumePattern.hasMatch(text)) {
      return false;
    }
    if (_wrapperCostumePattern.hasMatch(text)) {
      return true;
    }
    if (_distinctiveCostumePattern.hasMatch(text)) {
      return false;
    }
    final hasAnchor = anchorNames.any(
      (anchor) =>
          anchor != asset.name && anchor.isNotEmpty && text.contains(anchor),
    );
    if (hasAnchor) {
      return true;
    }
    return text.contains('御寒') ||
        text.contains('低温环境') ||
        text.contains('用于包裹') ||
        text.contains('防止');
  }

  static bool _isTransientPropAsset(FilmSceneAsset asset) {
    final text = '${asset.name} ${asset.description}'.trim();
    if (_corePropPattern.hasMatch(text)) {
      return false;
    }
    if (_transientPropPattern.hasMatch(text)) {
      return true;
    }
    if (asset.sourceShotIndexes.length > 1) {
      return false;
    }
    return text.contains('生存物资') ||
        text.contains('助燃') ||
        text.contains('食材') ||
        text.contains('被积雪掩埋');
  }

  static List<FilmReferenceImageAnalysis> buildMatchingReferenceImages({
    required List<String> slotReferenceImages,
    required Map<int, String> slotRemarks,
    required Map<int, String> slotAssetIds,
    required List<Asset> globalAssets,
    required List<FilmSceneAsset> sceneAssets,
  }) {
    final referenceImages = <FilmReferenceImageAnalysis>[];
    void addReferenceImage(FilmReferenceImageAnalysis item) {
      final normalizedPath = path.normalize(item.imagePath);
      final existingIndex = referenceImages.indexWhere(
        (existing) => path.normalize(existing.imagePath) == normalizedPath,
      );
      if (existingIndex == -1) {
        referenceImages.add(item);
        return;
      }

      final existing = referenceImages[existingIndex];
      final itemScore =
          item.effectiveName.length +
          (item.assetName.trim().isNotEmpty ? 20 : 0) +
          (item.imageDescription.trim().isNotEmpty ? 10 : 0);
      final existingScore =
          existing.effectiveName.length +
          (existing.assetName.trim().isNotEmpty ? 20 : 0) +
          (existing.imageDescription.trim().isNotEmpty ? 10 : 0);
      if (itemScore > existingScore) {
        referenceImages[existingIndex] = item;
      }
    }

    for (var i = 0; i < slotReferenceImages.length; i++) {
      final imagePath = slotReferenceImages[i];
      if (imagePath.isEmpty) continue;

      final slotAssetId = slotAssetIds[i];
      if (slotAssetId != null && slotAssetId.isNotEmpty) {
        final matchingAssets = globalAssets.where(
          (asset) => asset.id == slotAssetId,
        );
        if (matchingAssets.isNotEmpty) {
          final asset = matchingAssets.first;
          for (final img in asset.allImages) {
            if (img.path.isEmpty) continue;
            addReferenceImage(
              FilmReferenceImageAnalysis(
                imagePath: img.path,
                displayName: img.name.isNotEmpty
                    ? '${asset.name}-${img.name}'
                    : asset.name,
                assetName: asset.name,
                assetCategory: asset.category,
                assetDescription: asset.description,
                imageDescription: img.description,
              ),
            );
          }
          continue;
        }
      }

      final remark = slotRemarks[i]?.trim() ?? '';
      final displayName = remark.isNotEmpty
          ? remark
          : path.basenameWithoutExtension(imagePath);
      addReferenceImage(
        FilmReferenceImageAnalysis(
          imagePath: imagePath,
          displayName: displayName.isNotEmpty ? displayName : '参考图${i + 1}',
          imageDescription: '影视工坊参考图插槽${i + 1}',
        ),
      );
    }

    for (final sceneAsset in sceneAssets) {
      for (final view in FilmSceneAssetViews.all) {
        final imagePath = sceneAsset.viewImages[view.name] ?? '';
        if (imagePath.isEmpty) continue;
        addReferenceImage(
          FilmReferenceImageAnalysis(
            imagePath: imagePath,
            displayName: '${sceneAsset.name}-${view.name}',
            assetName: sceneAsset.name,
            assetCategory: sceneAsset.category,
            assetDescription: sceneAsset.description,
            imageDescription: view.description,
          ),
        );
      }
    }

    return referenceImages;
  }

  static Asset buildGlobalAssetFromSceneAsset({
    required FilmSceneAsset sceneAsset,
    required String assetId,
  }) {
    final frontPath = sceneAsset.viewImages[FilmSceneAssetViews.front] ?? '';
    final extraImages = <AssetRefImage>[];
    for (final view in FilmSceneAssetViews.all) {
      if (view.name == FilmSceneAssetViews.front) continue;
      final imagePath = sceneAsset.viewImages[view.name] ?? '';
      if (imagePath.isEmpty) continue;
      extraImages.add(
        AssetRefImage(
          path: imagePath,
          name: '${sceneAsset.name}-${view.name}',
          description: '${view.description} ${sceneAsset.description}'.trim(),
        ),
      );
    }
    return Asset(
      id: assetId,
      name: sceneAsset.name,
      category: sceneAsset.category,
      imagePath: frontPath,
      description: sceneAsset.description,
      images: extraImages,
    );
  }

  static String buildSceneAssetExtractionPrompt({
    required List<Shot> shots,
    required String fullScript,
  }) {
    final shotsText = shots
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final shot = entry.value;
          return '''
shotIndex: $index
镜头序号: ${shot.shotNumber}
镜头名称: ${shot.shotName}
景别: ${shot.shotType}
角色名称: ${shot.characterName}
服装化妆: ${shot.costume}
使用道具: ${shot.props}
场景基础描述: ${shot.sceneDescription}
场景细节描述: ${shot.sceneDetails}
物体状态: ${shot.objectState}
画面描述: ${shot.prompt}
''';
        })
        .join('\n---\n');

    return '''请从当前影视工坊拆解分镜中深度提取需要参考图的视觉资产元素。

要求：
1. 结果宁少勿滥，优先提取 4 到 12 个最核心、最需要锁定一致性的视觉资产。
2. 人物默认已经包含稳定脸部特征、发型和主服装；不要再为同一角色重复拆出普通外套、御寒衣、包裹物等泛化 Costume，除非该服装本身是独立设计重点。
3. 关键道具只保留会反复出现、推动剧情、或造型强识别的物件；不要提取树枝、木屑、野菜、普通积雪、碎石、车辆残骸等一次性零散物资或背景杂物。
4. 重要场景只保留 1 到 3 个需要持续统一空间结构的场景；不要把局部背景细节拆成独立资产。
5. 不要提取抽象情绪、镜头语言、光效本身。
6. 同一元素跨镜头出现要去重，但要合并来源镜头。
7. sourceShotIndexes 必须使用输入中的 0 基 shotIndex。
8. category 只能输出 Person、Scene、Prop、Costume、Other。
9. description 要写成可直接用于生成资产图的中文视觉描述，包含外观、材质、颜色、年代、状态、用途。
10. 必须输出可被 JSON.parse 直接解析的严格 JSON：键名和值之间必须有冒号，不要输出 \\{、\\}、\\" 这类转义对象符号。

完整剧本上下文：
$fullScript

当前拆解分镜：
$shotsText

请只返回严格 JSON 对象，不要 markdown，不要解释，格式：
{"assets":[{"name":"元素名","category":"Person/Scene/Prop/Costume/Other","description":"视觉描述","sourceShotIndexes":[0,1]}]}''';
  }

  Future<List<FilmSceneAsset>> extractSceneAssets({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Shot> shots,
    required String fullScript,
    Function(String)? onProgress,
  }) async {
    final prompt = buildSceneAssetExtractionPrompt(
      shots: shots,
      fullScript: fullScript,
    );
    const systemPrompt =
        '你是专业影视美术指导，负责从分镜中提取需要参考图锁定造型的资产元素。'
        '只返回可被 JSON.parse 解析的严格 JSON 对象。';
    try {
      onProgress?.call('正在使用结构化 JSON 模式提取资产...\n');
      final content = await _apiService.chat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        jsonObjectResponse: true,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      onProgress?.call(content);
      return parseSceneAssetExtraction(content);
    } catch (error) {
      debugPrint('Structured scene asset extraction failed: $error');
      onProgress?.call('\n结构化 JSON 模式失败，正在回退流式提取...\n');
    }

    final buffer = StringBuffer();
    final stream = _apiService.chatStream(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
    );
    await for (final chunk in stream) {
      buffer.write(chunk);
      onProgress?.call(chunk);
    }
    return parseSceneAssetExtraction(buffer.toString());
  }

  Future<String> saveSceneAssetImage({
    required String imageUrl,
    required String projectName,
    required String assetName,
    required String viewName,
  }) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final safeProjectName = sanitizeAssetFileName(
      projectName,
      fallback: '未命名项目',
    );
    final safeAssetName = sanitizeAssetFileName(assetName);
    final projectDir = path.join(
      appDir.path,
      'data',
      '分镜图',
      '$safeProjectName-分镜图',
      '本场资产',
      safeAssetName,
    );
    await Directory(projectDir).create(recursive: true);

    final filePath = path.join(
      projectDir,
      buildSceneAssetFileName(assetName, viewName),
    );

    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      final response = await _dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      await File(filePath).writeAsBytes(response.data);
      return filePath;
    }

    if (imageUrl.startsWith('data:')) {
      final commaIndex = imageUrl.indexOf(',');
      final base64Data = commaIndex == -1
          ? imageUrl
          : imageUrl.substring(commaIndex + 1);
      await File(filePath).writeAsBytes(base64Decode(base64Data));
      return filePath;
    }

    var sourcePath = imageUrl;
    if (!path.isAbsolute(sourcePath)) {
      sourcePath = path.join(appDir.path, sourcePath);
    }
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('资产图源文件不存在: $imageUrl');
    }
    if (path.normalize(sourceFile.path) == path.normalize(filePath)) {
      return filePath;
    }
    await sourceFile.copy(filePath);
    return filePath;
  }

  Future<String> _loadMatchAssetPrompt() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final promptPath = path.join(
        appDir.path,
        'data',
        'Settings',
        'match_asset_prompt.txt',
      );
      final file = File(promptPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }

      final defaultContent = _getDefaultMatchAssetPrompt();
      await file.parent.create(recursive: true);
      await file.writeAsString(defaultContent);
      return defaultContent;
    } catch (e) {
      return _getDefaultMatchAssetPrompt();
    }
  }

  String _getDefaultMatchAssetPrompt() {
    return '''请根据剧情和分镜头综合分析，智能匹配左侧参考图资产到该场戏的分镜头。

参考图片资产列表（每项已包含名称/备注、资产归属和视觉模型解析内容）:
{{IMAGE_LIST}}

当前分镜信息:
{{CONTEXT_INFO}}
分镜描述: {{PROMPT}}

智能匹配规则：
0. 视觉解析优先：参考图片资产列表中的“视觉模型解析”代表图片真实内容，“名称/备注”和“所属资产”代表用户命名意图。必须综合两者判断，不要只做关键词匹配；当名称写着“XX人”“XX道具”“XX场景”时，需要把这个身份/所属关系保留下来参与匹配。

1. 综合分析：结合完整剧情上下文和当前分镜头描述，深度理解场景中出现的人物、道具、场景等元素。通读全文后，仔细理解每个场景的切换，考虑人物所在的空间变化可能只是在一个场景里的不同位置。

2. 视角智能匹配（核心规则）：
   - 每个主体可能有多张不同视角的参考图（正面、左侧、右侧、背面、特写等）
   - 根据分镜头描述中人物的朝向、动作、镜头角度，选择最合适的视角参考图
   - **朝向推理**：
     * 人物"看向窗外/右方" → 选择该人物的右侧视图（因为面朝右）
     * 人物"看向左方/门口（在左侧）" → 选择该人物的左侧视图
     * 人物"背对镜头/走远" → 选择该人物的背面视图
     * 人物"面对镜头/正面" → 选择该人物的正面视图
     * 人物"俯拍/从上方" → 选择该人物的顶部视图
   - **景别推理**：
     * 特写/大特写镜头 → 优先选择面部特写、眼睛特写等局部参考图
     * 近景镜头 → 优先选择面部特写或正面半身参考图
     * 中景镜头 → 选择正面或侧面参考图
     * 全景/远景镜头 → 选择全身视图参考图
   - **对话场景**：两人对话时，选择各自的侧面视图

3. 镜头类型匹配：
   - 全景/远景：优先匹配"全身"、"全景"、"环境"等资产
   - 中景：匹配"正面"、"侧面"等资产
   - 近景/特写：匹配"面部特写"、"眼睛特写"等资产
   - 如果某主体没有对应视角的参考图，选择最接近的视角

4. 场景资产匹配（空间连续性优先，严格单场景原则）：
   - **关键原则：一个分镜头只能匹配一张场景图**
   - 特写镜头时，如果没有明确交代背景切换，应该继承上一个镜头的场景背景，保持画面一致性
   - 如果分镜描述涉及多个场景，只匹配当前镜头的主要场景，不要同时匹配多个场景资产
   - 根据场景描述中的关键词（如"客厅"、"街道"、"办公室"）匹配对应场景资产
   - 注意：人物在同一场景内的空间变化（如走动、转身）不代表场景切换，应保持同一场景资产

5. 语义理解：
   - 深度理解分镜描述的上下文和语义，识别人物、道具、场景等元素的所属关系
   - 理解隐含关系，如"他拿起钥匙"需结合上文判断"他"是谁

6. 所属关系识别：
   - 参考图名称包含"XX的XX物品"时，判断分镜中该物品是否属于该人物
   - 例如："江帆拿着钥匙"应匹配"江帆的钥匙"
   - 参考图名称包含"XX的左侧/右侧/背面"时，表示这是该主体的特定视角

7. 模糊匹配与包含关系：
   - 支持名称的模糊匹配，如"江帆"可匹配"江帆的正面"、"江帆的左侧"、"江帆的背面"等
   - 资产名称的任何部分与分镜描述相关都可以匹配

8. 画面丰富性：
   - 不仅仅是简单的关键词匹配，要让画面丰富
   - 合理推断场景中可能出现的所有相关资产
   - 即使分镜未明确提到，但在场景中合理出现的元素也应匹配

9. 精准优先：
   - 同一主体有多张参考图时，只选择最匹配当前分镜头的那一张，不要全部选择
   - 多个可能匹配时，优先选择语义最相关、视角最匹配的资产
   - 确保匹配的资产能真实丰富画面内容

请先详细说明你的分析思考过程，然后在最后严格按照以下JSON格式输出:
{"imageIndexes": [1, 2, 3]}

只返回需要使用的图片序号数组。''';
  }

  Future<FilmReferenceImageAnalysis> analyzeReferenceImage({
    required String apiUrl,
    required String apiKey,
    required String model,
    required FilmReferenceImageAnalysis referenceImage,
  }) async {
    final imageFile = File(referenceImage.imagePath);
    if (!await imageFile.exists()) {
      throw Exception('参考图不存在: ${referenceImage.imagePath}');
    }

    final imageBase64 = base64Encode(await imageFile.readAsBytes());
    final nameContext = StringBuffer()
      ..writeln('参考图名称/备注：${referenceImage.effectiveName}')
      ..writeln('文件名：${path.basename(referenceImage.imagePath)}');

    if (referenceImage.assetName.trim().isNotEmpty) {
      nameContext.writeln('所属资产名称：${referenceImage.assetName.trim()}');
    }
    if (referenceImage.assetCategory.trim().isNotEmpty) {
      nameContext.writeln('资产类别：${referenceImage.assetCategory.trim()}');
    }
    if (referenceImage.assetDescription.trim().isNotEmpty) {
      nameContext.writeln('资产说明：${referenceImage.assetDescription.trim()}');
    }
    if (referenceImage.imageDescription.trim().isNotEmpty) {
      nameContext.writeln('图片视图说明：${referenceImage.imageDescription.trim()}');
    }

    final raw = await _apiService.chatWithImages(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      textPrompt:
          '请解析这张用于影视分镜资产匹配的参考图。必须结合图片内容和以下名称信息综合判断：\n'
          '$nameContext\n'
          '输出要求：\n'
          '1. 明确它更像人物、道具、服装、场景还是其他资产。\n'
          '2. 如果名称/备注包含“某某人”“某某道具”“某某的物品”“某场景”等信息，最终描述必须保留这些身份、所属关系和用途。\n'
          '3. 描述可用于和分镜头内容匹配的关键特征：主体身份、外观、服装、动作姿态、道具用途、场景类型、视角、景别、颜色材质、醒目标识。\n'
          '4. 对多视图资产，请判断当前图是正面、侧面、背面、特写、全身、环境全景等哪类视图。\n'
          '5. 用紧凑 JSON 返回，不要使用 markdown 代码块，格式：'
          '{"category":"人物/道具/服装/场景/其他","nameHint":"结合名称后的身份或用途","visualSummary":"图片真实内容","matchKeywords":["关键词1","关键词2"],"shotMatchHint":"适合匹配哪些分镜内容"}',
      imageBase64List: [imageBase64],
      systemPrompt:
          '你是影视资产管理和视觉模型解析助手，负责把参考图转换成便于分镜匹配的资产画像。'
          '你必须同时尊重用户给图片起的名称/备注和图片真实视觉内容，尤其要保留人物名、道具名、场景名和所属关系。',
    );

    return referenceImage.copyWith(
      visualDescription: _compactPromptText(raw, maxLength: 1200),
    );
  }

  Future<String> _loadReadFullTextPrompt() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final promptPath = path.join(
        appDir.path,
        'data',
        'Settings',
        'read_full_text_prompt.txt',
      );
      final file = File(promptPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }

      final defaultContent = _getDefaultReadFullTextPrompt();
      await file.parent.create(recursive: true);
      await file.writeAsString(defaultContent);
      return defaultContent;
    } catch (e) {
      return _getDefaultReadFullTextPrompt();
    }
  }

  String _getDefaultReadFullTextPrompt() {
    return '''你是一位专业电影导演，请深度解析以下剧本。

剧本内容：
{{SCRIPT}}

请以专业导演的视角，详细分析：

1. 场景解析：逐场分析每一场戏的剧情发展
   - 人物心理变化和情感走向
   - 环境氛围营造（光线、色调、空间感）
   - 道具的象征意义和功能
   - 服装造型对人物性格的体现

2. 叙事结构：
   - 情节推进的节奏和转折点
   - 冲突设置和矛盾激化
   - 伏笔铺垫和呼应关系

3. 视觉元素：
   - 关键道具或事物如何贯穿全剧
   - 场景转换的逻辑和意义
   - 色彩、光影的情绪表达

4. 人物塑造：
   - 主要角色的性格特征和成长弧线
   - 人物关系的演变
   - 台词潜台词的深层含义

请提供详细、具体的分析，而非概括性描述。每个要点都要结合剧本具体内容展开论述。''';
  }

  Future<Map<String, int>> aiMatchAssets({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required Map<String, List<String>> assetInfo,
  }) async {
    final assetList = StringBuffer();
    int imageIndex = 1;
    final indexMap = <String, int>{};

    for (final cat in ['人物', '道具', '服装', '场景']) {
      final assets = assetInfo[cat] ?? [];
      for (final asset in assets) {
        assetList.writeln('Image$imageIndex: $cat - $asset');
        indexMap['$cat:$asset'] = imageIndex;
        imageIndex++;
      }
    }

    final matchPrompt =
        '''请分析以下分镜描述,判断其中提到的资产对应哪些参考图片。

参考图片列表:
$assetList

分镜描述:
$prompt

请严格按照以下JSON格式输出,不要有任何额外文字:
{"matches": [{"asset": "资产名称", "category": "类别", "imageIndex": 图片序号}]}

例如: {"matches": [{"asset": "江帆", "category": "人物", "imageIndex": 1}, {"asset": "水壶", "category": "道具", "imageIndex": 2}]}''';

    try {
      final content = await _apiService.chat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': matchPrompt},
        ],
      );
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final jsonData = jsonDecode(jsonMatch.group(0)!);
        final result = <String, int>{};
        for (final match in jsonData['matches']) {
          final key = '${match['category']}:${match['asset']}';
          result[key] = indexMap[key] ?? match['imageIndex'];
        }
        return result;
      }
    } catch (e) {
      debugPrint('AI匹配失败: $e');
    }

    return {};
  }

  Future<List<int>> aiMatchImagesByRemark({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required List<String> imageRemarks,
    String? shotType,
    String? sceneDescription,
    String? fullScript,
    String? scriptAnalysis,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in aiMatchImagesByRemarkStream(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      imageRemarks: imageRemarks,
      shotType: shotType,
      sceneDescription: sceneDescription,
      fullScript: fullScript,
      scriptAnalysis: scriptAnalysis,
    )) {
      buffer.write(chunk);
    }
    return parseMatchResult(buffer.toString());
  }

  Stream<String> aiMatchImagesByRemarkStream({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required List<String> imageRemarks,
    String? shotType,
    String? sceneDescription,
    String? fullScript,
    String? scriptAnalysis,
  }) async* {
    final imageList = StringBuffer();
    for (int i = 0; i < imageRemarks.length; i++) {
      imageList.writeln('Image${i + 1}: ${imageRemarks[i]}');
    }

    final contextInfo = StringBuffer();
    if (shotType != null && shotType.isNotEmpty) {
      contextInfo.writeln('镜头类型: $shotType');
    }
    if (sceneDescription != null && sceneDescription.isNotEmpty) {
      contextInfo.writeln('场景描述: $sceneDescription');
    }
    if (fullScript != null && fullScript.isNotEmpty) {
      contextInfo.writeln('\n完整剧情上下文:\n$fullScript');
    }
    if (scriptAnalysis != null && scriptAnalysis.isNotEmpty) {
      contextInfo.writeln('\n剧情详解（专业导演视角分析）:\n$scriptAnalysis');
    }

    String systemPrompt = await _loadMatchAssetPrompt();
    final matchPrompt = systemPrompt
        .replaceAll('{{IMAGE_LIST}}', imageList.toString())
        .replaceAll('{{CONTEXT_INFO}}', contextInfo.toString())
        .replaceAll('{{PROMPT}}', prompt);

    // 调试日志：输出匹配提示词
    debugPrint('=== 匹配资产提示词 ===');
    debugPrint('IMAGE_LIST: ${imageList.toString()}');
    debugPrint('CONTEXT_INFO: ${contextInfo.toString()}');
    debugPrint('PROMPT: $prompt');
    debugPrint('=== 完整提示词长度: ${matchPrompt.length} ===');

    try {
      final stream = _apiService.chatStream(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': matchPrompt},
        ],
      );

      await for (final chunk in stream) {
        yield chunk;
      }
    } catch (e) {
      yield '匹配失败: $e';
    }
  }

  Future<List<int>> parseMatchResult(String content) async {
    final markerIndex = content.lastIndexOf('imageIndexes');
    if (markerIndex != -1) {
      final jsonStart = content.lastIndexOf('{', markerIndex);
      if (jsonStart != -1) {
        final jsonEnd = _findMatchingBrace(content, jsonStart);
        if (jsonEnd != -1) {
          final parsed = _tryParseImageIndexes(
            content.substring(jsonStart, jsonEnd + 1),
          );
          if (parsed != null) return parsed;
        }
      }
    }

    try {
      final jsonMatches = RegExp(r'\{[\s\S]*?\}').allMatches(content).toList();
      for (final match in jsonMatches.reversed) {
        final parsed = _tryParseImageIndexes(match.group(0)!);
        if (parsed != null) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('解析匹配结果失败: $e');
    }
    return [];
  }

  int _findMatchingBrace(String content, int startIndex) {
    var depth = 0;
    var inString = false;
    var escaping = false;
    for (int i = startIndex; i < content.length; i++) {
      final char = content[i];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (char == '\\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  List<int>? _tryParseImageIndexes(String rawJson) {
    try {
      final jsonData = jsonDecode(rawJson);
      final indexes = jsonData['imageIndexes'];
      if (indexes is List) {
        return indexes.map((item) => int.parse(item.toString())).toList();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int getNextBatchNumber(String projectName) {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final projectDir = Directory(
        path.join(appDir.path, 'data', '分镜图', '$projectName-分镜图'),
      );
      if (!projectDir.existsSync()) return 1;

      final batches = projectDir
          .listSync()
          .whereType<Directory>()
          .where((d) => path.basename(d.path).contains('批次'))
          .length;

      return batches + 1;
    } catch (e) {
      return 1;
    }
  }

  Future<String> saveGeneratedImage({
    required String imageUrl,
    required String projectName,
    required int batchNumber,
    required int shotNumber,
  }) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final projectDir = path.join(
      appDir.path,
      'data',
      '分镜图',
      '$projectName-分镜图',
      '$projectName-批次$batchNumber',
    );

    await Directory(projectDir).create(recursive: true);

    final fileName =
        '$projectName-批次$batchNumber-镜头${shotNumber.toString().padLeft(3, '0')}.png';
    final filePath = path.join(projectDir, fileName);

    if (imageUrl.startsWith('http') || imageUrl.startsWith('https')) {
      final response = await _dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      await File(filePath).writeAsBytes(response.data);
    } else {
      String sourcePath = imageUrl;
      if (imageUrl.startsWith('data/output/') ||
          imageUrl.startsWith('data\\output\\')) {
        sourcePath = path.join(appDir.path, imageUrl);
      }

      final file = File(sourcePath);
      if (await file.exists()) {
        await file.copy(filePath);
      } else {
        throw Exception('Image source not found: $imageUrl');
      }
    }

    return filePath;
  }

  Future<String> analyzeScript({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String script,
  }) async {
    String systemPrompt = await _loadReadFullTextPrompt();
    final prompt = systemPrompt.replaceAll('{{SCRIPT}}', script);

    try {
      return await _apiService.chat(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
    } catch (e) {
      throw Exception('剧本分析失败: $e');
    }
  }

  List<Shot> parseStoryboardFile(String content) {
    final shots = <Shot>[];
    final shotBlocks = content
        .split('==========')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final regex = RegExp(r'\[([^\]]+)\][:：]\s*([\s\S]*?)(?=\n\[|$)');

    for (final block in shotBlocks) {
      final shotData = <String, String>{};
      final matches = regex.allMatches(block);

      for (final match in matches) {
        final key = match.group(1)!.trim();
        final value = match.group(2)!.trim();
        shotData[key] = value;
      }

      if (shotData.isNotEmpty) {
        shots.add(
          Shot(
            shotNumber: shotData['镜头序号'] ?? '',
            shotName: shotData['镜头名称'] ?? '',
            shotType: shotData['景别'] ?? '中景',
            cameraAngle: shotData['视角与摄影机'] ?? '',
            lighting: shotData['光影氛围'] ?? '',
            sceneDescription: shotData['场景基础描述'] ?? '',
            sceneDetails: shotData['场景细节描述'] ?? '',
            textInFrame: shotData['画面文字'] ?? '无',
            objectState: shotData['物体状态'] ?? '无',
            characterName: shotData['角色名称'] ?? '无',
            costume: shotData['服装化妆'] ?? '无',
            action: shotData['人物动作'] ?? '无',
            expression: shotData['人物表情'] ?? '无',
            props: shotData['使用道具'] ?? '无',
            movement: shotData['运镜'] ?? '固定镜头',
            prompt: shotData['画面描述'] ?? '',
          ),
        );
      }
    }

    return shots;
  }
}
