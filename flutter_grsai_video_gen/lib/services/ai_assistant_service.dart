import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_assistant_message.dart';
import '../models/skill.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';
import '../providers/generate_params_provider.dart';
import '../providers/video_config_provider.dart';
import '../providers/video_node_provider.dart';
import 'skill_service.dart';

final aiAssistantServiceProvider = Provider((ref) => AiAssistantService(ref));

class AiAssistantService {
  final Ref _ref;

  AiAssistantService(this._ref);

  Future<String> buildCapabilityKnowledge({
    List<AiReferenceContext> referenceContexts = const [],
    String sessionContext = '',
  }) async {
    final configs = _ref.read(apiConfigsProvider);
    final imageConfigs = configs.where((c) => c.type == 'image').toList();
    final visionConfigs = configs.where((c) => c.type == 'vision').toList();
    final videoConfigs = configs.where((c) => c.type == 'video').toList();
    final generateParams = _ref.read(generateParamsProvider);
    final videoSettings = _ref.read(videoSettingsProvider);
    final videoNodes = _ref.read(videoNodesProvider);

    final buf = StringBuffer();
    buf.writeln('## 图片生成能力');
    buf.writeln('- `operation=image_generate`：纯文本生图或基于参考图继续生成/修改图片');
    buf.writeln('- `operation=image_edit`：如果用户明确说“基于当前图修改/扩图/保持主体再改”，优先使用这个操作');
    buf.writeln(
      '- 图片执行计划字段：mode, prompt, imageTasks, delayMs, maxConcurrency, autoExecute',
    );
    buf.writeln(
      '- 单个图片任务字段：operation, prompt, model, aspectRatio, imageSize, imageQuality, sampleSteps, referenceImageIds, referenceQuery, angleLabel',
    );
    buf.writeln(
      '- 当前图片页参数：model=${generateParams.model}, aspectRatio=${generateParams.aspectRatio}, imageSize=${generateParams.imageSize}, sampleSteps=${generateParams.sampleSteps}',
    );
    buf.writeln('- 可用图片比例：auto, 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3, 21:9');
    buf.writeln('- 可用图片尺寸：1K, 2K, 4K');
    buf.writeln('- 可用批量数量：1, 2, 4, 6, 8');
    final hasSessionContext = sessionContext.trim().isNotEmpty;
    if (referenceContexts.isEmpty) {
      buf.writeln('\n### 当前参考图上下文');
      if (hasSessionContext) {
        buf.writeln(
          '- 当前没有显式登记的参考图，但存在当前会话上下文；涉及“上一张/刚才那张/这张图”时，优先使用会话里的最近生成图。',
        );
      } else {
        buf.writeln('- 当前没有已选参考图；涉及“这张图/参考图/原图”的任务必须先提醒用户上传或选择参考图。');
      }
    } else {
      buf.writeln('\n### 当前参考图上下文');
      for (final refCtx in referenceContexts) {
        final desc = refCtx.description.trim().isEmpty
            ? '尚未分析'
            : refCtx.description.trim();
        buf.writeln(
          '- id=${refCtx.id} | name=${refCtx.name} | path=${refCtx.path} | description=$desc',
        );
      }
      buf.writeln(
        '- 多参考图时，请按用户描述自动匹配 referenceImageIds；无法精确匹配时使用当前最相关或最新选中的参考图。',
      );
    }
    buf.writeln('\n### 已配置图片API卡');
    for (final config in imageConfigs) {
      buf.writeln(
        '- ${config.name} | url=${config.url} | model=${config.model.isEmpty ? "未指定" : config.model} | 默认=${config.isDefault ? "是" : "否"}',
      );
    }
    buf.writeln('\n### 图片模型家族与调用方法');
    buf.writeln(
      '- `gemini-*`：走图片配置卡对应的 Gemini 图片接口（`v1beta/models/{model}:generateContent`），支持文本和参考图',
    );
    buf.writeln(
      '- `nano-banana*`：在 Grsai 配置下统一走 `/v1/api/generate`，支持文本和参考图；非 Grsai 卡仍兼容旧接口',
    );
    buf.writeln(
      '- `gpt-image-2`：优先走 `Grsai图片生成` / `/v1/api/generate`；若命中 OpenAI 兼容卡，则走 `/v1/images/generations` 或 `/v1/images/edits`',
    );
    buf.writeln('- `gpt-image-2-vip`：沿用 `gpt-image-2` 路由，但支持更高像素分辨率、更多比例和质量参数');
    buf.writeln(
      '- `z_image_*` / `z_image_base`：走本地 `Wan2GP bridge` 图像接口，适合本地 Z-Image 系列',
    );

    buf.writeln('\n## 视觉解析能力');
    buf.writeln('- AI助手自身可以使用普通文本模型；当用户发送参考图时，软件会调用默认视觉模型 API 解析图片。');
    if (visionConfigs.isEmpty) {
      buf.writeln('- 当前未配置视觉模型 API，图片解析会提示用户先到 API 配置中添加视觉模型。');
    } else {
      buf.writeln('### 已配置视觉模型API卡');
      for (final config in visionConfigs) {
        buf.writeln(
          '- ${config.name} | url=${config.url} | model=${config.model.isEmpty ? "未指定" : config.model} | 默认=${config.isDefault ? "是" : "否"}',
        );
      }
    }

    buf.writeln('\n## 视频生成能力');
    buf.writeln('- `operation=video_t2v`：纯文本生视频');
    buf.writeln('- `operation=video_i2v`：基于参考图/上一张图生视频');
    buf.writeln(
      '- 视频计划字段：videoModelName, videoTaskType, videoResolution, videoFrameNum, videoSampleSteps, videoGuideScale, videoShiftScale, videoSampleSolver, videoSeed, negativePrompt',
    );
    buf.writeln(
      '- 当前默认视频参数：model=${videoSettings.defaults.modelName}, taskType=${videoSettings.defaults.taskType}, resolution=${videoSettings.defaults.resolution}, frameNum=${videoSettings.defaults.frameNum}, sampleSteps=${videoSettings.defaults.sampleSteps}, guideScale=${videoSettings.defaults.guideScale}, shiftScale=${videoSettings.defaults.shiftScale}, solver=${videoSettings.defaults.sampleSolver}',
    );
    buf.writeln(
      '- `video_t2v` 通过视频节点 `/api/generate/t2v` 提交；`video_i2v` 通过 `/api/generate/i2v` 提交',
    );
    buf.writeln(
      '- 若用户要求“把当前图/上一张图做成视频”，优先使用 `video_i2v`；若用户没有给图而是直接描述动态画面，使用 `video_t2v`',
    );
    buf.writeln(
      '- `sourcePreference` 可选：selected_reference, latest_session_image, selected_or_latest',
    );

    if (videoConfigs.isNotEmpty) {
      buf.writeln('\n### 已配置视频API卡');
      for (final config in videoConfigs) {
        buf.writeln(
          '- ${config.name} | url=${config.url} | model=${config.model.isEmpty ? "未指定" : config.model} | 默认=${config.isDefault ? "是" : "否"}',
        );
      }
    }

    buf.writeln('\n### 可用视频节点');
    if (videoNodes.isEmpty) {
      buf.writeln(
        '- 当前无远程节点配置，可默认使用本地 `Wan2GP bridge`（http://127.0.0.1:${videoSettings.wan2gp.port}）',
      );
    } else {
      for (final node in videoNodes) {
        buf.writeln(
          '- ${node.name} | url=${node.effectiveApiUrl} | 在线=${node.isOnline ? "是" : "否"} | 默认=${node.isDefault ? "是" : "否"} | 队列=${node.queueLength}',
        );
      }
      buf.writeln('- 若未特别指定节点，系统会自动选择默认或在线节点；AI 只需产出视频计划，不必手动指定节点');
    }

    buf.writeln('\n## 交互与执行约束');
    buf.writeln('- 你可以自由与用户多轮交流，不要把所有需求都强行收敛成图片生成');
    buf.writeln('- 如果用户想咨询、比较、解释、规划，就正常对话，不必强行出 plan');
    buf.writeln('- 如果用户要求直接执行，就优先输出完整可执行 plan');
    buf.writeln('- 对图片修改/图生视频这类需求，默认可使用“当前已选参考图”或“当前会话最近生成图片”作为素材来源');
    if (hasSessionContext) {
      buf.writeln('\n## 当前会话上下文记忆');
      buf.writeln(sessionContext.trim());
    }
    return buf.toString();
  }

  Future<String> buildSkillsKnowledge(List<Skill> matchedSkills) async {
    if (matchedSkills.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## 当前匹配的专业技能：');
    for (final skill in matchedSkills) {
      buf.writeln('\n### 技能：${skill.icon} ${skill.name}');
      buf.writeln('分类：${skill.category}');
      buf.writeln('标签：${skill.tags.join('、')}');
      if (skill.knowledgeBase.isNotEmpty) {
        buf.writeln('\n${skill.knowledgeBase}');
      }
      if (skill.polishRules.isNotEmpty) {
        buf.writeln('\n润色规则：');
        for (final rule in skill.polishRules) {
          buf.writeln('- $rule');
        }
      }
      if (skill.examples.isNotEmpty) {
        buf.writeln('\n范例：');
        for (final ex in skill.examples) {
          buf.writeln('- 输入："${ex.input}"');
          buf.writeln('  输出："${ex.output}"');
        }
      }
      if (skill.promptTemplates.isNotEmpty) {
        buf.writeln('\n提示词模板：');
        for (final t in skill.promptTemplates) {
          buf.writeln('- ${t.name}：${t.template}');
        }
      }
    }
    return buf.toString();
  }

  String _buildSystemPrompt({
    required String capabilityKnowledge,
    required String skillsKnowledge,
  }) {
    return '''你是一位专业的多媒体创作助手，同时具备以下专业能力：摄影大师、影视导演、电商视觉设计师、概念艺术家、视频分镜设计师。

## 你的职责
1. 理解用户的图片生成、图片修改、文生视频、图生视频、创意策划、参数调整等需求
2. 在需要执行时，把用户需求转化为高质量、可直接提交的执行方案
3. 选择最合适的模型、接口方法和参数
4. 在用户原意基础上润色提示词，增强画面表现力和动态表现力
5. 允许自由多轮对话，不要把所有问题都限制成单一的图片生成流程

## 你掌握的软件能力知识
$capabilityKnowledge

$skillsKnowledge

## 输出规范（重要！必须严格遵守）
你的回复必须是纯JSON格式，不要包含任何其他文字、不要用markdown代码块包裹。
直接输出JSON对象，不要输出```json和```。

## 交互策略（重要）
1. 默认自由对话。咨询、解释、比较、规划类问题只回复自然文本，不要输出执行计划。
2. 用户表达明确执行意图时，不要要求确认，直接输出 `executionPlan`，`autoExecute` 为 true。
3. 如果任务需要参考图但当前没有参考图，只回复缺少什么素材，不要输出 `executionPlan`。
4. 普通图片生成/修改必须优先使用“当前图片页参数”，不要擅自换模型；用户明确要求换模型时才填写 model。
5. 多角度任务：mode 使用 `multi_angle`，如果用户没说数量，默认 4 个角度；用户指定数量时按指定数量拆成多个 imageTasks。
6. 剧本/脚本连续画面：mode 使用 `storyboard`，script 放用户的剧本/脚本原文，后续由软件内分镜规则拆解并生成。
7. 多参考图时，优先根据当前参考图上下文里的 id、name、description 自动填写 referenceImageIds；无法确定时填写 referenceQuery 描述你需要的素材。
8. 图片修改、基于参考图、多角度都必须携带 referenceImageIds 或 referenceQuery。
9. 必须主动利用“当前会话上下文记忆”。用户说“上一张、刚才那张、这张图、继续、同样风格、再来一组”时，不要当作全新孤立需求；优先结合最近生成图、当前参考图和上一轮提示词来产出执行计划。

JSON 顶层字段：
- reply: 给用户看的自然回复
- phase: 通常使用 understanding；执行计划也使用 understanding，软件会自动提交
- options: 默认为空数组，除非确实需要让用户继续选择
- executionPlan: 执行型任务使用
- plan: 仅视频任务或旧兼容路径使用

executionPlan 字段：
- mode: image_generate / image_edit / multi_angle / storyboard
- prompt: 总提示词或任务概述
- imageTasks: 图片任务数组，storyboard 可为空
- script: storyboard 模式必填
- delayMs: 默认 800
- maxConcurrency: 默认 3
- autoExecute: true

imageTasks 字段：
- operation: image_generate 或 image_edit
- prompt: 可直接提交给图片模型的完整提示词
- model/aspectRatio/imageSize/imageQuality/sampleSteps: 默认留空，表示使用当前图片页参数
- referenceImageIds: 需要使用的参考图 id 数组
- referenceQuery: 当你知道需要什么图但不确定 id 时填写，如“男人参考图”“街道背景图”
- angleLabel: 多角度任务填写，如“正面”“左侧”“背面”“俯拍”

示例：普通生图
{"reply":"我会按当前模型直接生成一张城市夜景。","phase":"understanding","options":[],"executionPlan":{"mode":"image_generate","prompt":"电影感城市夜景，高楼霓虹，雨后街道反光，纵深构图","imageTasks":[{"operation":"image_generate","prompt":"电影感城市夜景，高楼霓虹，雨后街道反光，纵深构图"}],"delayMs":800,"maxConcurrency":3,"autoExecute":true}}

示例：多角度参考图
{"reply":"我会基于当前参考图生成 4 个角度。","phase":"understanding","options":[],"executionPlan":{"mode":"multi_angle","prompt":"保持参考图主体一致，生成多角度视图","imageTasks":[{"operation":"image_edit","prompt":"保持参考图主体身份、服装和材质一致，正面视角，电影感写实","referenceImageIds":["ref-id"],"angleLabel":"正面"},{"operation":"image_edit","prompt":"保持参考图主体身份、服装和材质一致，左侧视角，电影感写实","referenceImageIds":["ref-id"],"angleLabel":"左侧"}],"delayMs":800,"maxConcurrency":3,"autoExecute":true}}

示例：剧本连续画面
{"reply":"我会先按软件内分镜规则拆解这段情节，再连续生成分镜画面。","phase":"understanding","options":[],"executionPlan":{"mode":"storyboard","prompt":"男人走在街道上突然晕倒的连续分镜","script":"一个男人走在街道上，突然晕倒。","delayMs":800,"maxConcurrency":3,"autoExecute":true}}

## 润色规则
- 永远只描述"希望看到什么"，不写"不要什么"
- 所有描述必须清晰、具体、可视觉化、无矛盾
- 图片重点覆盖：主体、环境、光线、构图、风格
- 视频重点覆盖：主体动作、镜头运动、节奏、环境动态、光影变化、情绪推进
- 保持用户原始意图不变，补充细节服务于原始需求''';
  }

  Future<AiAssistantResponse> processUserInput({
    required String userInput,
    required List<Map<String, String>> chatHistory,
    required List<SkillMatch> matchedSkills,
    List<AiReferenceContext> referenceContexts = const [],
    String sessionContext = '',
  }) async {
    final capabilityKnowledge = await buildCapabilityKnowledge(
      referenceContexts: referenceContexts,
      sessionContext: sessionContext,
    );
    final skillsKnowledge = await buildSkillsKnowledge(
      matchedSkills.map((m) => m.skill).toList(),
    );
    final systemPrompt = _buildSystemPrompt(
      capabilityKnowledge: capabilityKnowledge,
      skillsKnowledge: skillsKnowledge,
    );

    final configs = _ref.read(apiConfigsProvider);
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isEmpty) {
      return AiAssistantResponse(
        replyText: '未配置聊天API，请先在设置中配置聊天模型。',
        phase: AssistantPhase.understanding,
        options: [],
      );
    }

    final chatConfig = chatConfigs.firstWhere(
      (c) => c.isDefault,
      orElse: () => chatConfigs.first,
    );

    final apiService = _ref.read(apiServiceProvider);

    final messages = <Map<String, String>>[
      ...chatHistory,
      {'role': 'user', 'content': userInput},
    ];

    String rawResponse;
    try {
      rawResponse = await apiService.chat(
        apiUrl: chatConfig.url,
        apiKey: chatConfig.key,
        model: chatConfig.model,
        systemPrompt: systemPrompt,
        messages: messages,
      );
    } catch (e) {
      return AiAssistantResponse(
        replyText: 'AI助手请求失败：$e',
        phase: AssistantPhase.understanding,
        options: [
          AiOption(
            id: 'retry',
            label: '重试',
            icon: '🔄',
            type: 'secondary',
            action: 'continue_chat',
          ),
        ],
      );
    }

    final parsed = _parseAiResponse(rawResponse);
    if (parsed.executionPlan != null || parsed.plan != null) {
      return parsed;
    }

    if (_isLikelyGenerationIntent(userInput)) {
      final inferredOperation = _inferRequestedOperation(userInput);
      final fallbackExecutionPlan = _buildFallbackExecutionPlan(
        userInput,
        operation: inferredOperation,
        referenceContexts: referenceContexts,
      );
      if (fallbackExecutionPlan == null) {
        return AiAssistantResponse(
          replyText: '这个操作需要参考图。请先上传或选择参考图，我拿到素材后就能继续执行。',
          phase: AssistantPhase.understanding,
          options: [],
        );
      }
      return AiAssistantResponse(
        replyText: parsed.replyText.isNotEmpty
            ? '${parsed.replyText}\n\n我已按你的描述自动生成可执行方案。'
            : '我已理解你的需求，并自动生成可执行方案。',
        phase: AssistantPhase.understanding,
        options: [],
        executionPlan: fallbackExecutionPlan,
      );
    }

    return parsed;
  }

  AiAssistantResponse _parseAiResponse(String raw) {
    try {
      String jsonStr = raw.trim();

      // try multiple strategies to extract JSON
      Map<String, dynamic>? data;

      // strategy 1: direct parse
      data = _tryParseJson(jsonStr);

      // strategy 2: remove markdown code block
      if (data == null && jsonStr.contains('```')) {
        var inner = jsonStr;
        // remove ```json ... ``` or ``` ... ```
        inner = inner.replaceAll(RegExp(r'```\w*\n?'), '');
        inner = inner.replaceAll(RegExp(r'```'), '');
        data = _tryParseJson(inner.trim());
      }

      // strategy 3: find first { and last }
      if (data == null) {
        final first = jsonStr.indexOf('{');
        final last = jsonStr.lastIndexOf('}');
        if (first >= 0 && last > first) {
          data = _tryParseJson(jsonStr.substring(first, last + 1));
        }
      }

      if (data == null) {
        return _buildFallbackResponse(raw);
      }

      final replyText = data['reply'] as String? ?? '';
      final phaseStr = (data['phase'] as String? ?? 'understanding')
          .toLowerCase();
      final phase = AssistantPhase.values.firstWhere(
        (p) => p.name == phaseStr,
        orElse: () => AssistantPhase.understanding,
      );

      final options = <AiOption>[];
      if (data['options'] != null) {
        try {
          for (final opt in data['options'] as List) {
            if (opt is Map<String, dynamic>) {
              options.add(AiOption.fromJson(opt));
            } else if (opt is Map) {
              options.add(AiOption.fromJson(Map<String, dynamic>.from(opt)));
            }
          }
        } catch (_) {}
      }

      AiExecutionPlan? executionPlan;
      final rawExecutionPlan = data['executionPlan'] ?? data['execution_plan'];
      if (rawExecutionPlan != null) {
        try {
          executionPlan = AiExecutionPlan.fromJson(
            Map<String, dynamic>.from(rawExecutionPlan as Map),
          );
        } catch (_) {}
      }

      GenerationPlan? plan;
      if (data['plan'] != null) {
        try {
          plan = GenerationPlan.fromJson(
            Map<String, dynamic>.from(data['plan'] as Map),
          );
        } catch (_) {}
      }

      plan = _normalizePlan(plan);
      executionPlan = _normalizeExecutionPlan(executionPlan);
      if (executionPlan == null &&
          plan != null &&
          !_isVideoOperation(plan.operation)) {
        executionPlan = _executionPlanFromGenerationPlan(plan);
      }
      final normalizedPhase = executionPlan != null
          ? AssistantPhase.understanding
          : plan != null && phase == AssistantPhase.understanding
          ? AssistantPhase.confirming
          : phase;

      // ensure minimum options
      if (options.isEmpty) {
        if (executionPlan != null) {
          // Direct execution plans should stay conversational and not render
          // a confirmation card.
        } else if (plan != null) {
          options.addAll([
            AiOption(
              id: 'confirm',
              label: '确认生成',
              icon: '✅',
              type: 'primary',
              action: 'confirm',
            ),
            AiOption(
              id: 'modify',
              label: '调整提示词',
              icon: '✏️',
              type: 'secondary',
              action: 'modify',
            ),
          ]);
        } else {
          options.add(
            AiOption(
              id: 'continue',
              label: '继续对话',
              icon: '💬',
              type: 'secondary',
              action: 'continue_chat',
            ),
          );
        }
      }

      return AiAssistantResponse(
        replyText: replyText,
        phase: normalizedPhase,
        options: options,
        plan: plan,
        executionPlan: executionPlan,
      );
    } catch (e) {
      return _buildFallbackResponse(raw);
    }
  }

  Map<String, dynamic>? _tryParseJson(String str) {
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  AiAssistantResponse _buildFallbackResponse(String raw) {
    // clean up raw text for display
    var cleanText = raw.trim();
    // remove JSON artifacts if partially parsed
    cleanText = cleanText
        .replaceAll(RegExp(r'^[\s{}\[\]"]+'), '')
        .replaceAll(RegExp(r'[\s{}\[\]"]+$'), '')
        .trim();

    final hasKeywords = cleanText.contains('提示词') || cleanText.contains('生成');

    return AiAssistantResponse(
      replyText: cleanText.isNotEmpty ? cleanText : raw,
      phase: AssistantPhase.understanding,
      options: [
        AiOption(
          id: 'continue',
          label: hasKeywords ? '确认生成' : '继续对话',
          icon: hasKeywords ? '✅' : '💬',
          type: hasKeywords ? 'primary' : 'secondary',
          action: hasKeywords ? 'confirm' : 'continue_chat',
        ),
      ],
    );
  }

  GenerationPlan? _normalizePlan(GenerationPlan? plan) {
    if (plan == null) return null;
    final prompt = plan.prompt.trim();
    if (prompt.isEmpty) return null;

    const validOperations = {
      'image_generate',
      'image_edit',
      'video_t2v',
      'video_i2v',
    };
    final validRatios = {
      'auto',
      '1:1',
      '16:9',
      '9:16',
      '4:3',
      '3:4',
      '3:2',
      '2:3',
      '21:9',
    };
    final validSizes = {'1K', '2K', '4K'};
    final validVideoResolutions = {
      '1280*720',
      '720*1280',
      '1024*1024',
      '960*720',
      '720*960',
      '960*640',
      '640*960',
    };
    final validSourcePreferences = {
      'selected_reference',
      'latest_session_image',
      'selected_or_latest',
    };

    final operation = validOperations.contains(plan.operation)
        ? plan.operation
        : _inferRequestedOperation(prompt);
    final aspectRatio = validRatios.contains(plan.aspectRatio)
        ? plan.aspectRatio
        : '16:9';
    final imageSize = validSizes.contains(plan.imageSize)
        ? plan.imageSize
        : '2K';
    final batchCount = [1, 2, 4, 6, 8].contains(plan.batchCount)
        ? plan.batchCount
        : 1;
    final videoResolution = validVideoResolutions.contains(plan.videoResolution)
        ? plan.videoResolution
        : _inferVideoResolutionFromAspectRatio(aspectRatio);
    final videoFrameNum = plan.videoFrameNum > 0 ? plan.videoFrameNum : 81;
    final videoSampleSteps = plan.videoSampleSteps > 0
        ? plan.videoSampleSteps
        : 50;
    final sourcePreference =
        validSourcePreferences.contains(plan.sourcePreference)
        ? plan.sourcePreference
        : 'selected_or_latest';

    return GenerationPlan(
      operation: operation,
      prompt: prompt,
      model: plan.model,
      aspectRatio: aspectRatio,
      imageSize: imageSize,
      batchCount: batchCount,
      negativePrompt: plan.negativePrompt.trim(),
      videoResolution: videoResolution,
      videoFrameNum: videoFrameNum,
      videoSampleSteps: videoSampleSteps,
      videoGuideScale: plan.videoGuideScale <= 0 ? 5.0 : plan.videoGuideScale,
      videoShiftScale: plan.videoShiftScale <= 0 ? 5.0 : plan.videoShiftScale,
      videoSeed: plan.videoSeed,
      videoSampleSolver: plan.videoSampleSolver.trim().isEmpty
          ? 'unipc'
          : plan.videoSampleSolver.trim(),
      videoTaskType: plan.videoTaskType.trim().isEmpty
          ? (operation == 'video_i2v' ? 'i2v-A14B' : 't2v-A14B')
          : plan.videoTaskType.trim(),
      videoModelName: plan.videoModelName.trim().isEmpty
          ? (operation == 'video_i2v' ? 'i2v-a14b' : 't2v-a14b')
          : plan.videoModelName.trim(),
      sourcePreference: sourcePreference,
      skillId: plan.skillId,
      skillName: plan.skillName,
    );
  }

  AiExecutionPlan? _normalizeExecutionPlan(AiExecutionPlan? plan) {
    if (plan == null) return null;
    const validModes = {
      'image_generate',
      'image_edit',
      'multi_angle',
      'storyboard',
    };
    final mode = validModes.contains(plan.mode) ? plan.mode : 'image_generate';
    final delayMs = plan.delayMs < 0
        ? 800
        : plan.delayMs > 5000
        ? 5000
        : plan.delayMs;
    final maxConcurrency = plan.maxConcurrency < 1
        ? 1
        : plan.maxConcurrency > 5
        ? 5
        : plan.maxConcurrency;

    if (mode == 'storyboard') {
      final script = plan.script.trim().isNotEmpty
          ? plan.script.trim()
          : plan.prompt.trim();
      if (script.isEmpty) return null;
      return AiExecutionPlan(
        mode: mode,
        prompt: plan.prompt.trim(),
        script: script,
        reply: plan.reply.trim(),
        delayMs: delayMs,
        maxConcurrency: maxConcurrency,
        autoExecute: plan.autoExecute,
        reason: plan.reason,
      );
    }

    final tasks = plan.imageTasks
        .map(_normalizeImageTask)
        .where((task) => task.prompt.trim().isNotEmpty)
        .toList();

    if (mode == 'multi_angle') {
      final angleTasks = tasks.isEmpty
          ? _buildDefaultAngleTasks(plan.prompt, const [])
          : tasks;
      return AiExecutionPlan(
        mode: mode,
        prompt: plan.prompt.trim(),
        imageTasks: angleTasks,
        reply: plan.reply.trim(),
        delayMs: delayMs,
        maxConcurrency: maxConcurrency,
        autoExecute: plan.autoExecute,
        reason: plan.reason,
      );
    }

    final prompt = plan.prompt.trim();
    final imageTasks = tasks.isNotEmpty
        ? tasks
        : prompt.isNotEmpty
        ? [
            AiImageTaskPlan(
              operation: mode == 'image_edit' ? 'image_edit' : 'image_generate',
              prompt: prompt,
            ),
          ]
        : <AiImageTaskPlan>[];
    if (imageTasks.isEmpty) return null;

    return AiExecutionPlan(
      mode: mode,
      prompt: prompt,
      imageTasks: imageTasks,
      reply: plan.reply.trim(),
      delayMs: delayMs,
      maxConcurrency: maxConcurrency,
      autoExecute: plan.autoExecute,
      reason: plan.reason,
    );
  }

  AiImageTaskPlan _normalizeImageTask(AiImageTaskPlan task) {
    final operation = task.operation == 'image_edit'
        ? 'image_edit'
        : 'image_generate';
    final batchCount = task.batchCount < 1
        ? 1
        : task.batchCount > 20
        ? 20
        : task.batchCount;
    return AiImageTaskPlan(
      id: task.id,
      operation: operation,
      prompt: task.prompt.trim(),
      model: task.model.trim(),
      aspectRatio: task.aspectRatio.trim(),
      imageSize: task.imageSize.trim(),
      imageQuality: task.imageQuality.trim(),
      sampleSteps: task.sampleSteps,
      referenceImageIds: task.referenceImageIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      referenceQuery: task.referenceQuery.trim(),
      angleLabel: task.angleLabel.trim(),
      batchCount: batchCount,
    );
  }

  AiExecutionPlan _executionPlanFromGenerationPlan(GenerationPlan plan) {
    final operation = plan.operation == 'image_edit'
        ? 'image_edit'
        : 'image_generate';
    return AiExecutionPlan(
      mode: operation,
      prompt: plan.prompt,
      imageTasks: [
        AiImageTaskPlan(
          operation: operation,
          prompt: plan.prompt,
          model: plan.model,
          aspectRatio: plan.aspectRatio,
          imageSize: plan.imageSize,
          batchCount: plan.batchCount,
        ),
      ],
    );
  }

  AiExecutionPlan? _buildFallbackExecutionPlan(
    String userInput, {
    required String operation,
    required List<AiReferenceContext> referenceContexts,
  }) {
    final prompt = userInput.trim();
    if (prompt.isEmpty) return null;
    final refIds = referenceContexts.map((r) => r.id).toList();

    if (operation == 'multi_angle') {
      if (refIds.isEmpty) return null;
      final count = _extractRequestedCount(prompt) ?? 4;
      return AiExecutionPlan(
        mode: 'multi_angle',
        prompt: prompt,
        imageTasks: _buildDefaultAngleTasks(
          prompt,
          refIds.take(1).toList(),
          count: count,
        ),
      );
    }

    if (operation == 'storyboard') {
      return AiExecutionPlan(
        mode: 'storyboard',
        prompt: prompt,
        script: prompt,
      );
    }

    if (operation == 'image_edit' && refIds.isEmpty) {
      return null;
    }

    return AiExecutionPlan(
      mode: operation == 'image_edit' ? 'image_edit' : 'image_generate',
      prompt: prompt,
      imageTasks: [
        AiImageTaskPlan(
          operation: operation == 'image_edit'
              ? 'image_edit'
              : 'image_generate',
          prompt: prompt,
          referenceImageIds: operation == 'image_edit'
              ? refIds.take(1).toList()
              : const [],
        ),
      ],
    );
  }

  List<AiImageTaskPlan> _buildDefaultAngleTasks(
    String basePrompt,
    List<String> referenceIds, {
    int count = 4,
  }) {
    final labels = [
      '正面',
      '左侧',
      '右侧',
      '背面',
      '正面俯拍',
      '正面仰拍',
      '左后侧',
      '右后侧',
      '全景俯拍',
      '近景特写',
      '低角度仰拍',
      '高角度俯拍',
      '三分之二侧面',
      '背面远景',
      '正侧面近景',
      '环境全景',
      '肩后视角',
      '半身正面',
      '半身侧面',
      '动态抓拍',
    ];
    final safeCount = count < 1
        ? 4
        : count > 20
        ? 20
        : count;
    return labels.take(safeCount).map((label) {
      return AiImageTaskPlan(
        operation: 'image_edit',
        prompt: '保持参考图主体身份、外观、服装、材质和核心特征一致，$label，电影感写实，主体清晰，结构稳定。$basePrompt',
        referenceImageIds: referenceIds,
        angleLabel: label,
      );
    }).toList();
  }

  int? _extractRequestedCount(String text) {
    final digitMatch = RegExp(r'(\d+)\s*(张|个|幅|组)?').firstMatch(text);
    if (digitMatch != null) {
      return int.tryParse(digitMatch.group(1)!);
    }
    const cnDigits = {
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    for (final entry in cnDigits.entries) {
      if (text.contains('${entry.key}张') ||
          text.contains('${entry.key}个') ||
          text.contains('${entry.key}幅')) {
        return entry.value;
      }
    }
    return null;
  }

  bool _isVideoOperation(String operation) {
    return operation == 'video_t2v' || operation == 'video_i2v';
  }

  bool _isLikelyGenerationIntent(String userInput) {
    final text = userInput.trim().toLowerCase();
    if (text.isEmpty) return false;

    const generationKeywords = [
      '生成',
      '画',
      '做一张',
      '做图',
      '生成图',
      '出图',
      '连续画面',
      '分镜',
      '剧本',
      '脚本',
      '多角度',
      '角度',
      '修改',
      '重绘',
      '图片',
      '海报',
      '插画',
      'render',
      'create',
      'generate',
      'image',
      'poster',
    ];
    const consultingKeywords = [
      '为什么',
      '怎么',
      '教程',
      '原理',
      '区别',
      '解释',
      '是什么',
      'what is',
      'how to',
      'difference',
    ];

    final hasGenerationKeyword = generationKeywords.any(text.contains);
    final hasConsultingKeyword = consultingKeywords.any(text.contains);
    return hasGenerationKeyword && !hasConsultingKeyword;
  }

  String _inferRequestedOperation(String userInput) {
    final text = userInput.trim().toLowerCase();
    const storyboardKeywords = ['剧本', '脚本', '分镜', '连续画面', '连续的画面', '镜头图片'];
    const multiAngleKeywords = ['多角度', '不同角度', '各个角度', '角度图', '正面', '背面', '侧面'];
    const videoKeywords = ['视频', '动起来', '动画', '运镜', 'video'];
    const imageEditKeywords = ['修改', '保持', '基于', '扩图', '重绘', '换背景', '换风格'];
    if (storyboardKeywords.any(text.contains)) {
      return 'storyboard';
    }
    if (multiAngleKeywords.any(text.contains)) {
      return 'multi_angle';
    }
    if (videoKeywords.any(text.contains)) {
      const imageSourceKeywords = ['上一张', '当前图', '这张图', '参考图', '原图', 'image'];
      if (imageSourceKeywords.any(text.contains)) {
        return 'video_i2v';
      }
      return 'video_t2v';
    }
    if (imageEditKeywords.any(text.contains)) {
      return 'image_edit';
    }
    return 'image_generate';
  }

  String _inferVideoResolutionFromAspectRatio(String aspectRatio) {
    switch (aspectRatio) {
      case '9:16':
        return '720*1280';
      case '1:1':
        return '1024*1024';
      case '4:3':
        return '960*720';
      case '3:4':
        return '720*960';
      case '3:2':
        return '960*640';
      case '2:3':
        return '640*960';
      default:
        return '1280*720';
    }
  }

  String _buildRecentChatContext(List<Map<String, String>> chatHistory) {
    final recent = chatHistory
        .where((message) => (message['content'] ?? '').trim().isNotEmpty)
        .toList();
    if (recent.isEmpty) {
      return '';
    }
    return recent
        .skip(recent.length > 6 ? recent.length - 6 : 0)
        .map((message) {
          final role = message['role'] == 'assistant' ? 'AI助手' : '用户';
          return '$role：${message['content']!.trim()}';
        })
        .join('\n');
  }

  /// Analyze image(s) sent by user and return AI description + options
  Future<AiAssistantResponse> analyzeImage({
    required String imageBase64,
    required List<Map<String, String>> chatHistory,
  }) async {
    final configs = _ref.read(apiConfigsProvider);
    final visionConfigs = configs.where((c) => c.type == 'vision').toList();
    if (visionConfigs.isEmpty) {
      return AiAssistantResponse(
        replyText: '未配置视觉模型API，无法解析图片。请先在 API 配置中添加并设为默认视觉模型。',
        phase: AssistantPhase.understanding,
      );
    }

    final visionConfig = visionConfigs.firstWhere(
      (c) => c.isDefault,
      orElse: () => visionConfigs.first,
    );

    final apiService = _ref.read(apiServiceProvider);
    final recentContext = _buildRecentChatContext(chatHistory);

    try {
      final rawResponse = await apiService.chatWithImages(
        apiUrl: visionConfig.url,
        apiKey: visionConfig.key,
        model: visionConfig.model,
        textPrompt:
            '${recentContext.isEmpty ? "" : "最近对话上下文：\n$recentContext\n\n"}'
            '请仔细分析这张图片，从以下维度进行专业描述：\n\n'
            '1. 画面内容：主体是什么？人物/物体/场景的详细描述\n'
            '2. 构图方式：采用了什么构图手法\n'
            '3. 光影效果：光源方向、色温、明暗对比\n'
            '4. 色彩风格：主色调、色彩搭配\n'
            '5. 画面风格：写实/动漫/油画/摄影等风格\n'
            '6. 技术参数推测：可能的景别、焦距、角度\n\n'
            '请在详细解析后，明确询问用户下一步要执行的操作。\n'
            '如果你能根据图片直接给出可执行的生成方案，也可以在选项里提供。\n'
            '请以JSON格式回复，格式如下（不要用markdown代码块）：\n'
            '{"reply": "你的图片详细分析，并询问下一步操作","phase": "understanding",'
            '"options": [{"id":"gen_similar","label":"生成类似风格","icon":"🎨","type":"primary","action":"gen_similar",'
            '"data":{"prompt_from_image":"基于图片内容生成的提示词"}},'
            '{"id":"gen_modify","label":"修改这张图片","icon":"✏️","type":"secondary","action":"gen_modify",'
            '"data":{"prompt_from_image":"在保留主体的前提下对原图风格和细节进行修改的提示词"}},'
            '{"id":"gen_video","label":"做成视频","icon":"🎬","type":"secondary","action":"gen_video",'
            '"data":{"prompt_from_image":"基于原图做图生视频的动态提示词"}},'
            '{"id":"gen_extend","label":"扩展画面","icon":"🖼️","type":"secondary","action":"gen_extend",'
            '"data":{"prompt_from_image":"基于原图进行画面扩展与补全的提示词"}},'
            '{"id":"analyze_more","label":"深入分析","icon":"🔍","type":"secondary","action":"continue_chat"}]}',
        imageBase64List: [imageBase64],
        systemPrompt:
            '你是一位专业的AI图像分析助手，具备摄影大师和影视导演的专业眼光。'
            '你的任务是分析用户上传的图片，给出专业的画面分析，并提供可行的后续操作建议。'
            '所有图片描述必须清晰具体，适合用于AI图片生成。'
            '请优先详细分析画面，然后询问用户下一步操作；你也可以同时给出图片生成、图片修改、图生视频的可执行建议。',
      );

      return _parseAiResponse(rawResponse);
    } catch (e) {
      return AiAssistantResponse(
        replyText: '图片分析失败：$e',
        phase: AssistantPhase.understanding,
        options: [
          AiOption(
            id: 'retry',
            label: '重试',
            icon: '🔄',
            type: 'secondary',
            action: 'continue_chat',
          ),
        ],
      );
    }
  }

  AiAssistantMessage buildGreetingMessage(int skillCount) {
    return AiAssistantMessage(
      type: AssistantMessageType.greeting,
      text:
          '你好，我是你的AI创作助手。你可以直接描述想做什么，我会按当前图片页模型和参数自动执行；也可以先聊天、拆剧本、做多角度参考图。\n\n我已掌握 $skillCount 项专业技能。',
      options: [
        AiOption(
          id: 'free_input',
          label: '自由创作',
          icon: '',
          type: 'secondary',
          action: 'continue_chat',
        ),
        AiOption(
          id: 'view_skills',
          label: '查看技能库',
          icon: '',
          type: 'secondary',
          action: 'view_skills',
        ),
      ],
    );
  }

  AiAssistantMessage buildSatisfactionQuery(List<String> imagePaths) {
    return AiAssistantMessage(
      type: AssistantMessageType.resultCard,
      text: '生成完成！对这次结果满意吗？',
      images: imagePaths,
      options: [
        AiOption(
          id: 'satisfied_save',
          label: '满意，保存为技能',
          icon: '😊',
          type: 'primary',
          action: 'save_skill',
        ),
        AiOption(
          id: 'satisfied_continue',
          label: '满意，继续新需求',
          icon: '😊',
          type: 'secondary',
          action: 'satisfied',
        ),
        AiOption(
          id: 'partial_modify',
          label: '部分满意，微调修改',
          icon: '🔧',
          type: 'secondary',
          action: 'modify',
        ),
        AiOption(
          id: 'unsatisfied',
          label: '不满意，重新生成',
          icon: '❌',
          type: 'danger',
          action: 'regenerate',
        ),
        AiOption(
          id: 'post_keep_subject_night',
          label: '保持主体换成电影夜景',
          type: 'secondary',
          action: 'post_generation_intent',
          data: {'prompt': '保持主体换成电影夜景'},
        ),
        AiOption(
          id: 'post_same_style_4',
          label: '同风格再来 4 张',
          type: 'secondary',
          action: 'post_generation_intent',
          data: {'prompt': '同风格再来 4 张'},
        ),
        AiOption(
          id: 'post_character_angles',
          label: '生成角色多角度',
          type: 'secondary',
          action: 'post_generation_intent',
          data: {'prompt': '生成角色多角度'},
        ),
        AiOption(
          id: 'post_storyboard',
          label: '做成连续分镜',
          type: 'secondary',
          action: 'post_generation_intent',
          data: {'prompt': '做成连续分镜'},
        ),
      ],
    );
  }

  Future<Skill> saveUserSkillFromGeneration({
    required String name,
    required String category,
    required List<String> tags,
    required String originalPrompt,
    required String polishedPrompt,
    required String model,
    required String aspectRatio,
    required String imageSize,
    required List<String> resultImages,
  }) async {
    final skillService = _ref.read(skillServiceProvider);
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';

    final skill = Skill(
      id: id,
      name: name,
      icon: '📚',
      category: category,
      tags: tags,
      description: '用户自学习技能：$name',
      source: 'user',
      createdAt: DateTime.now().toIso8601String(),
      learnedFrom: LearnedFrom(
        originalPrompt: originalPrompt,
        polishedPrompt: polishedPrompt,
        model: model,
        aspectRatio: aspectRatio,
        imageSize: imageSize,
        resultImages: resultImages,
        satisfactionScore: 5,
      ),
      usageCount: 0,
      rating: 5,
      promptTemplates: [],
      knowledgeBase: '',
      defaultParams: {
        'model': model,
        'aspectRatio': aspectRatio,
        'imageSize': imageSize,
        'batchCount': 1,
      },
      polishRules: [],
      examples: [SkillExample(input: originalPrompt, output: polishedPrompt)],
    );

    return skillService.saveUserSkill(skill);
  }
}
