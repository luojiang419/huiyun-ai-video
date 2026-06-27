import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/asset_extraction_model.dart';
import 'api_service.dart';

class AssetExtractionService {
  final ApiService _apiService;

  AssetExtractionService(this._apiService);

  Future<String> _loadSystemPrompt() async {
    try {
      final appDir = Directory.current;

      // 尝试多个可能的路径（开发环境和编译后环境）
      final possiblePaths = [
        path.join(appDir.path, 'data', 'Settings', 'asset_extraction_system_prompt.txt'),
        path.join(appDir.path, 'flutter_grsai_video_gen', 'data', 'Settings', 'asset_extraction_system_prompt.txt'),
      ];

      for (final promptPath in possiblePaths) {
        final file = File(promptPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            return content;
          }
        }
      }

      // 如果文件加载失败，返回硬编码的默认提示词
      return _getDefaultSystemPrompt();
    } catch (e) {
      debugPrint('Error loading asset extraction prompt: $e');
      return _getDefaultSystemPrompt();
    }
  }

  String _getDefaultSystemPrompt() {
    return '''# 角色定义
你是电影工业顶级的**美术指导 (Production Designer)** 和 **造型指导 (Costume Designer)**。你拥有极其敏锐的视觉拆解能力，能够从文学剧本中还原出精确的视觉设定。

# 核心任务
你的任务是分析用户输入的剧本，按**场次 (Scene)** 拆解出所有关键的视觉资产。
你需要特别关注**时空连续性 (Continuity)**：人物的造型（服装、发型、妆容、道具）必须随着剧情发展、时间推移、环境变化而做出**符合逻辑的改变**。

# 拆解维度

## 1. 角色造型 (Character Look) - **最重要**
不要只提取人名！必须提取**该人物在当前场次的具体造型**。
- **服装**：上衣、裤子/裙子、外套、材质、颜色、磨损程度。
- **鞋履**：款式、颜色、状态（如：沾满泥土的皮鞋）。
- **发型**：长短、颜色、发型状态（如：被雨淋湿的刘海、凌乱的起床头）。
- **妆容/状态**：面部特征、伤痕、汗水、污渍、情绪对外貌的影响。
- **随身道具**：手里拿的、身上背的。

**时空逻辑示例**：
- 第一场（清晨/卧室）：主角张三 -> 穿灰色睡衣，头发蓬乱，睡眼惺忪。
- 第五场（上午/公司）：主角张三 -> 换上了深蓝色西装，梳着整齐背头，戴金丝眼镜。
- 第十场（深夜/雨中打斗）：主角张三 -> 西装湿透且撕裂，眼镜丢失，脸上有多处淤青，头发湿漉漉地贴在额头。

## 2. 场景 (Scene)
- **环境**：具体的地点（如：充满赛博朋克风格的霓虹街道、维多利亚时期的书房）。
- **氛围**：光影、色调、天气（如：阴郁的蓝调、温暖的夕阳）。

## 3. 关键道具 (Prop)
- **物品**：对剧情有推动作用的物体（如：一把生锈的左轮手枪、一份机密文件）。
- **车辆/生物**：具体的型号、颜色、状态。

# 输出格式 (JSON)
必须严格输出为 **JSON 格式**，不要包含任何 Markdown 代码块标记（如 ```json）。结构如下：

[
  {
    "scene_id": "场次号 (如: 第1场)",
    "scene_location": "场景名 (如: 卧室)",
    "assets": [
      {
        "type": "character",
        "name": "人物名 (如: 张三)",
        "label": "简短造型标签 (如: 张三_睡衣版)",
        "description": "视觉描述 Prompt，包含服装、发型、妆容等细节。使用中文，描写要极具画面感。",
        "reasoning": "简述为什么是这个造型（如：因为是刚起床）"
      },
      {
        "type": "scene",
        "name": "场景名",
        "label": "场景标签",
        "description": "场景视觉描述 Prompt",
        "reasoning": "场景分析"
      },
      {
        "type": "prop",
        "name": "道具名",
        "label": "道具标签",
        "description": "道具视觉描述 Prompt",
        "reasoning": "道具分析"
      }
    ]
  }
]

# 执行指令
1.  **通读全文**：理解故事的时间线和人物经历。
2.  **按场拆解**：逐场分析。
3.  **推演造型**：如果剧本没写具体衣服，请根据**时间点**（早上/晚上）、**场合**（家/公司/战场）、**人物身份**（警察/乞丐）进行**最合理的推断**。
4.  **保持连贯**：确保伤口、污渍等状态在后续场次中得到继承（除非经过了治疗或清洗）。
5.  **输出 JSON**：直接输出 JSON 数据。''';
  }

  Future<List<ScriptAssetExtraction>> extractAssets({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String script,
    Function(String)? onProgress,
  }) async {
    final systemPrompt = await _loadSystemPrompt();

    final userPrompt = '''请分析以下剧本：
$script

请严格按照 JSON 格式输出拆解结果。''';

    final buffer = StringBuffer();

    try {
      final stream = _apiService.chatStream(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        systemPrompt: systemPrompt,
        messages: [{'role': 'user', 'content': userPrompt}],
      );

      await for (final chunk in stream) {
        buffer.write(chunk);
        onProgress?.call(chunk);
      }
    } catch (e) {
      debugPrint('Stream Error: $e');
      throw Exception('AI 请求失败: $e');
    }

    final content = buffer.toString();
    debugPrint('=== AI Extraction Result ===');
    debugPrint(content);

    if (content.trim().isEmpty) {
      throw Exception('AI 返回内容为空，请检查网络或 API 配置');
    }

    try {
      final jsonMatch = RegExp(r'\[\s*\{[\s\S]*\}\s*\]').firstMatch(content);
      final jsonStr = jsonMatch?.group(0) ?? content;

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => ScriptAssetExtraction.fromJson(e)).toList();
    } catch (e) {
      debugPrint('JSON Parsing Error: $e');
      debugPrint('Content: $content');
      throw Exception('AI 返回的数据格式不正确，无法解析为资产列表。\n原始内容: ${content.substring(0, content.length > 200 ? 200 : content.length)}...');
    }
  }
}
