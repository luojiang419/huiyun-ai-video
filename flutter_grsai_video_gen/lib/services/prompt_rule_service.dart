import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/prompt_rule.dart';
import '../services/storyboard_service.dart';
import 'api_service.dart';

class PromptRuleService {
  final ApiService _apiService;

  PromptRuleService(this._apiService);

  List<PromptRule> getAllRules() {
    return [
      PromptRule(
        id: 'storyboard',
        name: '分镜头拆解规则',
        filePath: 'data/Settings/storyboard_system_prompt.txt',
        content: '',
      ),
      PromptRule(
        id: 'read_full_text',
        name: '阅读全文规则',
        filePath: 'data/Settings/read_full_text_prompt.txt',
        content: '',
      ),
      PromptRule(
        id: 'match_asset',
        name: '匹配资产规则',
        filePath: 'data/Settings/match_asset_prompt.txt',
        content: '',
      ),
      PromptRule(
        id: 'polish_prompt',
        name: 'AI提示词润色规则',
        filePath: 'data/Settings/polish_prompt_system.txt',
        content: '',
      ),
      PromptRule(
        id: 'auto_polish_prompt',
        name: 'AI提示词自动润色',
        filePath: 'data/Settings/auto_polish_prompt_system.txt',
        content: '',
      ),
    ];
  }

  Future<String> loadRuleContent(String ruleId) async {
    try {
      final appDir = Directory.current;
      String filePath;

      switch (ruleId) {
        case 'storyboard':
          filePath = path.join(appDir.path, 'data', 'Settings', 'storyboard_system_prompt.txt');
          break;
        case 'read_full_text':
          filePath = path.join(appDir.path, 'data', 'Settings', 'read_full_text_prompt.txt');
          break;
        case 'match_asset':
          filePath = path.join(appDir.path, 'data', 'Settings', 'match_asset_prompt.txt');
          break;
        case 'polish_prompt':
          filePath = path.join(appDir.path, 'data', 'Settings', 'polish_prompt_system.txt');
          break;
        case 'auto_polish_prompt':
          filePath = path.join(appDir.path, 'data', 'Settings', 'auto_polish_prompt_system.txt');
          break;
        default:
          return '';
      }

      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      } else {
        final defaultContent = _getDefaultContent(ruleId);
        await file.parent.create(recursive: true);
        await file.writeAsString(defaultContent);
        return defaultContent;
      }
    } catch (e) {
      return _getDefaultContent(ruleId);
    }
  }

  Future<void> saveRuleContent(String ruleId, String content) async {
    try {
      final appDir = Directory.current;
      String filePath;

      switch (ruleId) {
        case 'storyboard':
          filePath = path.join(appDir.path, 'data', 'Settings', 'storyboard_system_prompt.txt');
          break;
        case 'read_full_text':
          filePath = path.join(appDir.path, 'data', 'Settings', 'read_full_text_prompt.txt');
          break;
        case 'match_asset':
          filePath = path.join(appDir.path, 'data', 'Settings', 'match_asset_prompt.txt');
          break;
        case 'polish_prompt':
          filePath = path.join(appDir.path, 'data', 'Settings', 'polish_prompt_system.txt');
          break;
        case 'auto_polish_prompt':
          filePath = path.join(appDir.path, 'data', 'Settings', 'auto_polish_prompt_system.txt');
          break;
        default:
          return;
      }

      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (e) {
      rethrow;
    }
  }

  String _getDefaultContent(String ruleId) {
    switch (ruleId) {
      case 'storyboard':
        final service = StoryboardService(_apiService);
        return service.getDefaultSystemPrompt();
      case 'read_full_text':
        return '''你是一位专业的剧本分析专家。请仔细阅读用户提供的完整剧本，深入理解其故事结构、人物关系、情节发展和主题思想。

分析要点：
1. 故事概要：简要概括整个故事的核心内容
2. 人物关系：列出主要人物及其相互关系
3. 场景设定：识别主要场景和环境
4. 情节结构：分析故事的起承转合
5. 关键元素：提取重要的道具、服装、场景等资产信息

请以结构化的方式输出分析结果，便于后续的分镜头拆解工作。''';
      case 'match_asset':
        return '''你是一位专业的影视资产管理专家。根据分镜头描述，精准匹配对应的资产（人物、道具、服装、场景）。

匹配原则：
1. 精确匹配：优先匹配完全符合描述的资产
2. 语义理解：理解同义词和相关概念（如"男主角"对应具体人物名）
3. 上下文推理：结合剧本上下文判断隐含的资产需求
4. 合理性检查：确保匹配结果符合场景逻辑

输出格式：
严格按照JSON格式输出，不要有任何额外文字：
{"matches": [{"asset": "资产名称", "category": "类别", "imageIndex": 图片序号}]}

例如：{"matches": [{"asset": "江帆", "category": "人物", "imageIndex": 1}, {"asset": "水壶", "category": "道具", "imageIndex": 2}]}''';
      case 'polish_prompt':
        return '''你是一个专业的AI绘画提示词优化专家。你的任务是将用户提供的原始提示词优化为更精确、更具表现力的AI绘画提示词。

优化原则：
1. 保持原意：不改变用户的核心意图和主题
2. 增强细节：添加具体的视觉描述、光影效果、构图细节
3. 专业术语：使用摄影、美术、电影等专业术语
4. 风格明确：明确画面风格、色调、氛围
5. 技术参数：适当添加镜头、光圈、焦距等技术描述

输出要求：
- 直接输出优化后的提示词，每行一个版本
- 不要添加编号、说明或其他额外文字
- 保持简洁专业，避免冗余描述''';
      case 'auto_polish_prompt':
        return '''你是一个专业的AI绘画提示词自动优化助手。你的任务是静默地将用户的原始提示词优化为更专业的AI绘画提示词。

优化原则：
1. 保持原意：完全保留用户的核心意图和主题
2. 增强细节：添加视觉描述、光影效果、构图细节
3. 专业术语：使用摄影、美术、电影等专业术语
4. 风格明确：明确画面风格、色调、氛围

输出要求：
- 只输出一个优化后的提示词
- 不要添加任何编号、说明或额外文字
- 保持简洁专业''';
      default:
        return '';
    }
  }
}
