import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_assistant_message.dart';
import '../models/uploaded_image.dart';
import '../models/skill.dart';
import '../providers/image_provider.dart';
import '../providers/session_provider.dart';
import '../services/ai_assistant_service.dart';
import '../services/skill_service.dart';

final skillListProvider = StateNotifierProvider<SkillListNotifier, List<Skill>>(
  (ref) {
    return SkillListNotifier(ref);
  },
);

class SkillListNotifier extends StateNotifier<List<Skill>> {
  final Ref _ref;

  SkillListNotifier(this._ref) : super([]) {
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    final skillService = _ref.read(skillServiceProvider);
    await skillService.initDirectories();
    await skillService.ensureBuiltinSkillsExist();
    final skills = await skillService.loadAllSkills();
    state = skills;
  }

  Future<void> reload() async {
    await _loadSkills();
  }

  Future<void> addUserSkill(Skill skill) async {
    final skillService = _ref.read(skillServiceProvider);
    await skillService.saveUserSkill(skill);
    await _loadSkills();
  }

  Future<void> deleteUserSkill(String skillId) async {
    final skillService = _ref.read(skillServiceProvider);
    await skillService.deleteUserSkill(skillId);
    await _loadSkills();
  }
}

final aiAssistantProvider =
    StateNotifierProvider<AiAssistantNotifier, AiAssistantState>((ref) {
      return AiAssistantNotifier(ref);
    });

class AiAssistantState {
  final bool isActive;
  final AssistantPhase phase;
  final List<AiAssistantMessage> messages;
  final List<SkillMatch> matchedSkills;
  final GenerationPlan? pendingPlan;
  final AiExecutionPlan? pendingExecutionPlan;
  final List<AiReferenceContext> referenceContexts;
  final bool isProcessing;
  final String? lastOriginalPrompt;
  final String? lastPolishedPrompt;
  final List<String> lastResultImages;

  AiAssistantState({
    this.isActive = false,
    this.phase = AssistantPhase.greeting,
    this.messages = const [],
    this.matchedSkills = const [],
    this.pendingPlan,
    this.pendingExecutionPlan,
    this.referenceContexts = const [],
    this.isProcessing = false,
    this.lastOriginalPrompt,
    this.lastPolishedPrompt,
    this.lastResultImages = const [],
  });

  AiAssistantState copyWith({
    bool? isActive,
    AssistantPhase? phase,
    List<AiAssistantMessage>? messages,
    List<SkillMatch>? matchedSkills,
    GenerationPlan? pendingPlan,
    AiExecutionPlan? pendingExecutionPlan,
    List<AiReferenceContext>? referenceContexts,
    bool? isProcessing,
    String? lastOriginalPrompt,
    String? lastPolishedPrompt,
    List<String>? lastResultImages,
    bool clearPendingPlan = false,
    bool clearPendingExecutionPlan = false,
  }) {
    return AiAssistantState(
      isActive: isActive ?? this.isActive,
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      matchedSkills: matchedSkills ?? this.matchedSkills,
      pendingPlan: clearPendingPlan ? null : (pendingPlan ?? this.pendingPlan),
      pendingExecutionPlan: clearPendingExecutionPlan
          ? null
          : (pendingExecutionPlan ?? this.pendingExecutionPlan),
      referenceContexts: referenceContexts ?? this.referenceContexts,
      isProcessing: isProcessing ?? this.isProcessing,
      lastOriginalPrompt: lastOriginalPrompt ?? this.lastOriginalPrompt,
      lastPolishedPrompt: lastPolishedPrompt ?? this.lastPolishedPrompt,
      lastResultImages: lastResultImages ?? this.lastResultImages,
    );
  }

  List<Map<String, String>> get chatHistory {
    final history = <Map<String, String>>[];
    for (final msg in messages) {
      if (msg.text != null && msg.text!.isNotEmpty) {
        history.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text!,
        });
      }
    }
    // keep only last 10 rounds
    if (history.length > 20) {
      return history.sublist(history.length - 20);
    }
    return history;
  }
}

class AiAssistantNotifier extends StateNotifier<AiAssistantState> {
  final Ref _ref;

  AiAssistantNotifier(this._ref) : super(AiAssistantState());

  void activateAssistant() {
    final skills = _ref.read(skillListProvider);
    final service = _ref.read(aiAssistantServiceProvider);
    final greeting = service.buildGreetingMessage(skills.length);

    state = AiAssistantState(
      isActive: true,
      phase: AssistantPhase.greeting,
      messages: [greeting],
    );
  }

  void deactivateAssistant() {
    state = AiAssistantState(isActive: false);
  }

  AiReferenceContext registerReferenceImage(UploadedImage image) {
    return _upsertReferenceContext(
      id: image.id,
      name: image.name,
      path: image.path,
    );
  }

  AiReferenceContext _upsertReferenceContext({
    required String id,
    required String name,
    required String path,
    String description = '',
  }) {
    final stableId = id.trim().isNotEmpty ? id.trim() : name.trim();
    final existing = state.referenceContexts.where((ctx) {
      if (path.trim().isNotEmpty && ctx.path == path) return true;
      return ctx.id == stableId || ctx.name == name;
    }).toList();
    final nextContext = existing.isNotEmpty
        ? existing.first.copyWith(
            id: existing.first.id.isNotEmpty ? existing.first.id : stableId,
            name: name,
            path: path.isNotEmpty ? path : existing.first.path,
            description: description.isNotEmpty
                ? description
                : existing.first.description,
            updatedAt: DateTime.now(),
          )
        : AiReferenceContext(
            id: stableId,
            name: name,
            path: path,
            description: description,
          );
    state = state.copyWith(
      referenceContexts: _replaceReferenceContext(
        state.referenceContexts,
        nextContext,
      ),
    );
    return nextContext;
  }

  List<AiReferenceContext> _replaceReferenceContext(
    List<AiReferenceContext> contexts,
    AiReferenceContext nextContext,
  ) {
    final next = <AiReferenceContext>[];
    var replaced = false;
    for (final ctx in contexts) {
      final samePath =
          nextContext.path.isNotEmpty && ctx.path == nextContext.path;
      final sameId = ctx.id == nextContext.id;
      if (samePath || sameId) {
        if (!replaced) {
          next.add(nextContext);
          replaced = true;
        }
        continue;
      }
      next.add(ctx);
    }
    if (!replaced) {
      next.add(nextContext);
    }
    return next;
  }

  Future<void> sendMessage(String userInput) async {
    state = state.copyWith(isProcessing: true);

    // add user message
    final userMsg = AiAssistantMessage(
      type: AssistantMessageType.text,
      text: userInput,
      isUser: true,
    );

    // match skills
    final skillService = _ref.read(skillServiceProvider);
    final matches = await skillService.matchSkills(userInput);

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      matchedSkills: matches,
    );

    // build chat history for AI context
    final chatHistory = <Map<String, String>>[];
    for (final msg in state.messages) {
      if (msg.type == AssistantMessageType.text && msg.text != null) {
        chatHistory.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text!,
        });
      }
    }

    // call AI
    final service = _ref.read(aiAssistantServiceProvider);
    final response = await service.processUserInput(
      userInput: userInput,
      chatHistory: chatHistory,
      matchedSkills: matches,
      referenceContexts: state.referenceContexts,
      sessionContext: _buildSessionContextSummary(),
    );

    // build AI response message
    AssistantMessageType msgType;
    if (response.executionPlan != null) {
      msgType = AssistantMessageType.text;
    } else {
      switch (response.phase) {
        case AssistantPhase.confirming:
          msgType = AssistantMessageType.confirmCard;
          break;
        case AssistantPhase.reviewing:
          msgType = AssistantMessageType.resultCard;
          break;
        case AssistantPhase.modifying:
          msgType = AssistantMessageType.modifyCard;
          break;
        default:
          msgType = AssistantMessageType.text;
      }
    }

    final aiMsg = AiAssistantMessage(
      type: msgType,
      text: response.replyText,
      options: response.options,
      polishedPrompt: response.plan?.prompt,
      plan: response.plan?.toJson(),
      executionPlan: response.executionPlan?.toJson(),
      matchedSkillId: response.plan?.skillId,
      matchedSkillName: response.plan?.skillName,
    );

    state = state.copyWith(
      isProcessing: false,
      phase: response.phase,
      messages: [...state.messages, aiMsg],
      pendingPlan: response.plan,
      pendingExecutionPlan: response.executionPlan,
      clearPendingExecutionPlan: response.executionPlan == null,
      lastOriginalPrompt: userInput,
      lastPolishedPrompt:
          response.executionPlan?.prompt ?? response.plan?.prompt,
    );
  }

  /// Send image(s) to AI for analysis
  Future<void> sendImage(
    String imageBase64,
    String imageName, {
    String? imagePath,
    String? imageId,
  }) async {
    final registeredContext = _upsertReferenceContext(
      id: imageId ?? imagePath ?? imageName,
      name: imageName,
      path: imagePath ?? '',
    );
    state = state.copyWith(isProcessing: true);

    // add user message showing the image
    final userMsg = AiAssistantMessage(
      type: AssistantMessageType.text,
      text: '发送了参考图：$imageName',
      isUser: true,
    );

    state = state.copyWith(messages: [...state.messages, userMsg]);

    // call AI image analysis
    final service = _ref.read(aiAssistantServiceProvider);
    final chatHistory = <Map<String, String>>[];
    for (final msg in state.messages) {
      if (msg.type == AssistantMessageType.text && msg.text != null) {
        chatHistory.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text!,
        });
      }
    }

    final response = await service.analyzeImage(
      imageBase64: imageBase64,
      chatHistory: chatHistory,
    );
    final updatedContext = registeredContext.copyWith(
      description: response.replyText,
      updatedAt: DateTime.now(),
    );

    // if AI returned a prompt suggestion, save it as pending plan
    GenerationPlan? plan;
    if (response.plan != null) {
      plan = response.plan;
    } else {
      // check if options contain a prompt_from_image data
      for (final opt in response.options) {
        final suggestedPrompt = opt.data['prompt_from_image'] as String?;
        if (suggestedPrompt != null) {
          plan = GenerationPlan(
            prompt: suggestedPrompt,
            model: '',
            aspectRatio: '',
            imageSize: '',
          );
          break;
        }
      }
    }

    final aiMsg = AiAssistantMessage(
      type: AssistantMessageType.text,
      text: response.replyText,
      options: response.options,
      polishedPrompt: plan?.prompt,
      plan: plan?.toJson(),
      executionPlan: response.executionPlan?.toJson(),
    );

    state = state.copyWith(
      isProcessing: false,
      phase: response.phase,
      messages: [...state.messages, aiMsg],
      pendingPlan: plan,
      pendingExecutionPlan: response.executionPlan,
      clearPendingExecutionPlan: response.executionPlan == null,
      referenceContexts: _replaceReferenceContext(
        state.referenceContexts,
        updatedContext,
      ),
      lastOriginalPrompt: '图片分析：$imageName',
      lastPolishedPrompt: plan?.prompt,
    );
  }

  Future<void> handleOptionClick(AiOption option) async {
    switch (option.action) {
      case 'select_category':
        final categoryId = option.data['categoryId'] as String?;
        if (categoryId == null) break;

        // load skills for this category and present them directly
        final skillService = _ref.read(skillServiceProvider);
        final categorySkills = await skillService.getSkillsByCategory(
          categoryId,
        );
        final categoryNames = {
          'film_tv': '影视制作',
          'portrait': '人物肖像',
          'scene_concept': '场景概念',
          'commercial': '商业摄影',
          'nature': '自然风光',
          'artistic': '艺术风格',
          'special': '特殊场景',
        };
        final catName = categoryNames[categoryId] ?? categoryId;

        final skillList = categorySkills.isNotEmpty
            ? categorySkills.map((s) => '${s.icon} ${s.name}').join('、')
            : '暂无';

        final skillOptions = <AiOption>[
          AiOption(
            id: 'free_input',
            label: '自由描述',
            icon: '💡',
            type: 'secondary',
            action: 'continue_chat',
          ),
        ];

        // add each skill as a clickable option
        for (final skill in categorySkills.take(6)) {
          skillOptions.add(
            AiOption(
              id: 'use_skill_${skill.id}',
              label: skill.name,
              icon: skill.icon,
              type: 'tag',
              action: 'use_skill',
              data: {'skillId': skill.id, 'skillName': skill.name},
            ),
          );
        }

        final msg = AiAssistantMessage(
          type: AssistantMessageType.text,
          text:
              '你选择了「$catName」分类，该分类下有以下技能：\n$skillList\n\n请选择一个技能开始，或者直接描述你的需求。',
          options: skillOptions,
        );

        state = state.copyWith(
          phase: AssistantPhase.understanding,
          messages: [...state.messages, msg],
        );
        break;

      case 'use_skill':
        final skillId = option.data['skillId'] as String?;
        final skillName = option.data['skillName'] as String?;
        if (skillId != null && skillName != null) {
          await sendMessage('请使用$skillName技能帮助我完成当前创作需求');
        }
        break;

      case 'confirm':
        state = state.copyWith(phase: AssistantPhase.generating);
        break;

      case 'modify':
        state = state.copyWith(phase: AssistantPhase.modifying);
        // add a prompt message locally instead of calling AI
        final modifyMsg = AiAssistantMessage(
          type: AssistantMessageType.text,
          text: '请告诉我你想调整的地方：可以是主体、风格、色调、构图，也可以是动作、运镜、节奏和氛围。',
          options: [
            AiOption(
              id: 'mod_style',
              label: '换种风格',
              icon: '🎭',
              type: 'tag',
              action: 'continue_chat',
            ),
            AiOption(
              id: 'mod_color',
              label: '调整色调',
              icon: '🎨',
              type: 'tag',
              action: 'continue_chat',
            ),
            AiOption(
              id: 'mod_composition',
              label: '改变构图',
              icon: '📐',
              type: 'tag',
              action: 'continue_chat',
            ),
            AiOption(
              id: 'mod_light',
              label: '调整光线',
              icon: '💡',
              type: 'tag',
              action: 'continue_chat',
            ),
            AiOption(
              id: 'mod_motion',
              label: '调整动态/运镜',
              icon: '🎬',
              type: 'tag',
              action: 'continue_chat',
            ),
            AiOption(
              id: 'mod_redo',
              label: '重新生成',
              icon: '🔄',
              type: 'secondary',
              action: 'regenerate',
            ),
          ],
        );
        state = state.copyWith(
          messages: [...state.messages, modifyMsg],
          isProcessing: false,
        );
        break;

      case 'regenerate':
        // regenerate with same plan
        final plan = state.pendingPlan;
        if (plan != null) {
          state = state.copyWith(phase: AssistantPhase.generating);
          // this will be handled by generate_screen via confirm action
          final confirmMsg = AiAssistantMessage(
            type: AssistantMessageType.confirmCard,
            text: '正在重新生成...',
            polishedPrompt: plan.prompt,
            plan: plan.toJson(),
            options: [
              AiOption(
                id: 'confirm_regen',
                label: '确认重新生成',
                icon: '✅',
                type: 'primary',
                action: 'confirm',
              ),
            ],
          );
          state = state.copyWith(
            messages: [...state.messages, confirmMsg],
            isProcessing: false,
          );
        }
        break;

      case 'satisfied':
        state = state.copyWith(
          phase: AssistantPhase.greeting,
          clearPendingPlan: true,
          clearPendingExecutionPlan: true,
          messages: [
            ...state.messages,
            AiAssistantMessage(
              type: AssistantMessageType.text,
              text: '太好了！有什么新的创作需求吗？',
              options: [
                AiOption(
                  id: 'new_${DateTime.now().millisecondsSinceEpoch}',
                  label: '开始新创作',
                  icon: '✨',
                  type: 'secondary',
                  action: 'continue_chat',
                ),
              ],
            ),
          ],
        );
        break;

      case 'save_skill':
        state = state.copyWith(phase: AssistantPhase.savingSkill);
        break;

      case 'view_skills':
        // handled by UI layer
        break;

      case 'change_param':
        final currentPlan = state.pendingPlan;
        final paramMsg = AiAssistantMessage(
          type: AssistantMessageType.text,
          text: '请选择要调整的参数：',
          options: [
            AiOption(
              id: 'param_ratio_169',
              label: '16:9',
              icon: '📐',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'aspectRatio', 'value': '16:9'},
            ),
            AiOption(
              id: 'param_ratio_11',
              label: '1:1',
              icon: '📐',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'aspectRatio', 'value': '1:1'},
            ),
            AiOption(
              id: 'param_ratio_916',
              label: '9:16',
              icon: '📐',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'aspectRatio', 'value': '9:16'},
            ),
            AiOption(
              id: 'param_size_1k',
              label: '1K',
              icon: '📏',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'imageSize', 'value': '1K'},
            ),
            AiOption(
              id: 'param_size_2k',
              label: '2K',
              icon: '📏',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'imageSize', 'value': '2K'},
            ),
            AiOption(
              id: 'param_size_4k',
              label: '4K',
              icon: '📏',
              type: 'tag',
              action: 'update_param',
              data: {'key': 'imageSize', 'value': '4K'},
            ),
            if (currentPlan != null)
              AiOption(
                id: 'param_done',
                label: '确认生成',
                icon: '✅',
                type: 'primary',
                action: 'confirm',
              ),
          ],
        );
        state = state.copyWith(
          messages: [...state.messages, paramMsg],
          isProcessing: false,
        );
        break;

      case 'update_param':
        final key = option.data['key'] as String?;
        final value = option.data['value'] as String?;
        if (key != null && value != null && state.pendingPlan != null) {
          final oldPlan = state.pendingPlan!;
          final newPlan = GenerationPlan(
            operation: oldPlan.operation,
            prompt: oldPlan.prompt,
            model: oldPlan.model,
            aspectRatio: key == 'aspectRatio' ? value : oldPlan.aspectRatio,
            imageSize: key == 'imageSize' ? value : oldPlan.imageSize,
            batchCount: oldPlan.batchCount,
            negativePrompt: oldPlan.negativePrompt,
            videoResolution: oldPlan.videoResolution,
            videoFrameNum: oldPlan.videoFrameNum,
            videoSampleSteps: oldPlan.videoSampleSteps,
            videoGuideScale: oldPlan.videoGuideScale,
            videoShiftScale: oldPlan.videoShiftScale,
            videoSeed: oldPlan.videoSeed,
            videoSampleSolver: oldPlan.videoSampleSolver,
            videoTaskType: oldPlan.videoTaskType,
            videoModelName: oldPlan.videoModelName,
            sourcePreference: oldPlan.sourcePreference,
            skillId: oldPlan.skillId,
            skillName: oldPlan.skillName,
          );
          state = state.copyWith(
            pendingPlan: newPlan,
            messages: [
              ...state.messages,
              AiAssistantMessage(
                type: AssistantMessageType.text,
                text: '已将 $key 更新为 $value',
                options: [
                  AiOption(
                    id: 'param_more',
                    label: '继续调整',
                    icon: '⚙️',
                    type: 'secondary',
                    action: 'change_param',
                  ),
                  AiOption(
                    id: 'param_confirm',
                    label: '确认生成',
                    icon: '✅',
                    type: 'primary',
                    action: 'confirm',
                  ),
                ],
              ),
            ],
          );
        }
        break;

      case 'satisfied_save':
        state = state.copyWith(phase: AssistantPhase.savingSkill);
        break;

      case 'satisfied_continue':
        state = state.copyWith(
          phase: AssistantPhase.greeting,
          clearPendingPlan: true,
          clearPendingExecutionPlan: true,
          messages: [
            ...state.messages,
            AiAssistantMessage(
              type: AssistantMessageType.text,
              text: '有什么新的创作需求吗？',
              options: [
                AiOption(
                  id: 'new_req',
                  label: '继续新创作',
                  icon: '✨',
                  type: 'secondary',
                  action: 'continue_chat',
                ),
              ],
            ),
          ],
        );
        break;

      case 'unsatisfied':
        // regenerate directly without calling AI
        final existingPlan = state.pendingPlan;
        if (existingPlan != null) {
          state = state.copyWith(phase: AssistantPhase.generating);
          final regenMsg = AiAssistantMessage(
            type: AssistantMessageType.confirmCard,
            text: '好的，正在重新生成...',
            polishedPrompt: existingPlan.prompt,
            plan: existingPlan.toJson(),
            options: [
              AiOption(
                id: 'confirm_regen2',
                label: '确认重新生成',
                icon: '✅',
                type: 'primary',
                action: 'confirm',
              ),
            ],
          );
          state = state.copyWith(
            messages: [...state.messages, regenMsg],
            isProcessing: false,
          );
        }
        break;

      case 'continue_chat':
      default:
        // just wait for next user input
        break;
    }
  }

  void addGenerationResult(List<String> imagePaths) {
    final service = _ref.read(aiAssistantServiceProvider);
    final satisfactionMsg = service.buildSatisfactionQuery(imagePaths);
    var nextReferenceContexts = state.referenceContexts;
    for (var i = 0; i < imagePaths.length; i++) {
      final imagePath = imagePaths[i].trim();
      if (imagePath.isEmpty) continue;
      final prompt = state.lastPolishedPrompt ?? state.lastOriginalPrompt ?? '';
      final description = [
        '当前会话生成结果图',
        '本次结果第${i + 1}张',
        if (prompt.trim().isNotEmpty) '生成提示词：${_compactText(prompt, 240)}',
      ].join('；');
      nextReferenceContexts = _replaceReferenceContext(
        nextReferenceContexts,
        AiReferenceContext(
          id: imagePath,
          name: _fileNameFromPath(imagePath),
          path: imagePath,
          description: description,
          tags: const ['generated', 'session-result'],
        ),
      );
    }

    state = state.copyWith(
      phase: AssistantPhase.reviewing,
      messages: [...state.messages, satisfactionMsg],
      referenceContexts: nextReferenceContexts,
      lastResultImages: imagePaths,
      isProcessing: false,
    );
  }

  void addLocalMessage(
    AiAssistantMessage message, {
    AssistantPhase? phase,
    bool? isProcessing,
  }) {
    state = state.copyWith(
      phase: phase,
      isProcessing: isProcessing,
      messages: [...state.messages, message],
    );
  }

  void deleteMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((msg) => msg.id != messageId).toList(),
    );
  }

  void removeImageFromMessage(String messageId, String imagePath) {
    final nextMessages = <AiAssistantMessage>[];
    for (final message in state.messages) {
      if (message.id != messageId) {
        nextMessages.add(message);
        continue;
      }
      final updatedImages = (message.images ?? const <String>[])
          .where((img) => img != imagePath)
          .toList();
      if (updatedImages.isEmpty &&
          (message.text == null || message.text!.trim().isEmpty)) {
        continue;
      }
      nextMessages.add(
        AiAssistantMessage(
          id: message.id,
          type: message.type,
          text: message.text,
          isUser: message.isUser,
          options: message.options,
          polishedPrompt: message.polishedPrompt,
          plan: message.plan,
          executionPlan: message.executionPlan,
          images: updatedImages.isEmpty ? null : updatedImages,
          analysis: message.analysis,
          matchedSkillId: message.matchedSkillId,
          matchedSkillName: message.matchedSkillName,
          timestamp: message.timestamp,
        ),
      );
    }
    state = state.copyWith(messages: nextMessages);
  }

  Future<void> saveSkill({
    required String name,
    required String category,
    required List<String> tags,
  }) async {
    final plan = state.pendingPlan;
    if (plan == null) return;

    final service = _ref.read(aiAssistantServiceProvider);
    await service.saveUserSkillFromGeneration(
      name: name,
      category: category,
      tags: tags,
      originalPrompt: state.lastOriginalPrompt ?? '',
      polishedPrompt: state.lastPolishedPrompt ?? plan.prompt,
      model: plan.model,
      aspectRatio: plan.aspectRatio,
      imageSize: plan.imageSize,
      resultImages: state.lastResultImages,
    );

    // reload skills
    await _ref.read(skillListProvider.notifier).reload();

    state = state.copyWith(
      phase: AssistantPhase.greeting,
      clearPendingPlan: true,
      clearPendingExecutionPlan: true,
      messages: [
        ...state.messages,
        AiAssistantMessage(
          type: AssistantMessageType.skillSaveCard,
          text: '✅ 技能「$name」已保存到技能库！下次类似需求会自动匹配调用。',
          options: [
            AiOption(
              id: 'continue_after_save',
              label: '继续新创作',
              icon: '✨',
              type: 'secondary',
              action: 'continue_chat',
            ),
          ],
        ),
      ],
    );
  }

  void clearMessages() {
    state = state.copyWith(messages: []);
  }

  String _buildSessionContextSummary() {
    final lines = <String>[];
    final session = _ref.read(currentSessionProvider);
    if (session != null) {
      lines.add('当前会话：${session.name}');
      final recentMessages = session.messages
          .where(
            (message) =>
                message.text.trim().isNotEmpty ||
                message.images.isNotEmpty ||
                message.videos.isNotEmpty,
          )
          .toList();
      final start = recentMessages.length > 8 ? recentMessages.length - 8 : 0;
      if (recentMessages.isNotEmpty) {
        lines.add('最近会话消息：');
        for (var i = start; i < recentMessages.length; i++) {
          final message = recentMessages[i];
          final role = message.type == 'user' ? '用户' : '生成结果';
          final parts = <String>[];
          final prompt = message.params?['prompt']?.toString();
          final text = prompt?.trim().isNotEmpty == true
              ? prompt!
              : message.text;
          if (text.trim().isNotEmpty) {
            parts.add(_compactText(text, 260));
          }
          if (message.images.isNotEmpty) {
            parts.add('图片=${message.images.map(_fileNameFromPath).join("、")}');
          }
          if (message.videos.isNotEmpty) {
            parts.add('视频=${message.videos.map(_fileNameFromPath).join("、")}');
          }
          if (message.params != null) {
            final model = message.params!['model']?.toString();
            final ratio = message.params!['aspectRatio']?.toString();
            final size = message.params!['imageSize']?.toString();
            final paramParts = [
              if (model != null && model.isNotEmpty) 'model=$model',
              if (ratio != null && ratio.isNotEmpty) 'ratio=$ratio',
              if (size != null && size.isNotEmpty) 'size=$size',
            ];
            if (paramParts.isNotEmpty) {
              parts.add(paramParts.join(' | '));
            }
          }
          if (parts.isNotEmpty) {
            lines.add('- $role：${parts.join('；')}');
          }
        }
      }

      final recentImages = <String>[];
      for (final message in session.messages.reversed) {
        for (final imagePath in message.images.reversed) {
          if (!recentImages.contains(imagePath)) {
            recentImages.add(imagePath);
          }
          if (recentImages.length >= 6) break;
        }
        if (recentImages.length >= 6) break;
      }
      if (recentImages.isNotEmpty) {
        lines.add('最近生成图（用户说“上一张/刚才那张/这张图”时优先参考）：');
        for (var i = 0; i < recentImages.length; i++) {
          lines.add(
            '- recentImage${i + 1}: name=${_fileNameFromPath(recentImages[i])} | path=${recentImages[i]}',
          );
        }
      }
    }

    final selectedImages = _ref.read(selectedImagesProvider);
    if (selectedImages.isNotEmpty) {
      lines.add('当前已选参考图：');
      for (var i = 0; i < selectedImages.length; i++) {
        final image = selectedImages[i];
        lines.add(
          '- selectedImage${i + 1}: id=${image.id} | name=${image.name} | path=${image.path}',
        );
      }
    }

    if (state.referenceContexts.isNotEmpty) {
      lines.add('AI助手已登记参考图记忆：');
      for (final context in state.referenceContexts.take(8)) {
        lines.add(
          '- id=${context.id} | name=${context.name} | path=${context.path} | description=${_compactText(context.description, 220)}',
        );
      }
    }

    if (lines.isEmpty) return '';
    lines.add('理解规则：后续提到上一张、刚才生成、这张图、该参考图、第N张时，优先结合上述会话与参考图记忆，不要割裂上下文。');
    return lines.join('\n');
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  String _compactText(String text, int maxLength) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }
}
