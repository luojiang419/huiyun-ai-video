import 'package:uuid/uuid.dart';

enum AssistantMessageType {
  text,
  greeting,
  confirmCard,
  generating,
  resultCard,
  skillSaveCard,
  modifyCard,
}

enum AssistantPhase {
  greeting,
  understanding,
  confirming,
  generating,
  reviewing,
  savingSkill,
  modifying,
}

class AiOption {
  final String id;
  final String label;
  final String icon;
  final String type; // primary, secondary, tag, danger
  final String action;
  final Map<String, dynamic> data;

  AiOption({
    required this.id,
    required this.label,
    this.icon = '',
    this.type = 'secondary',
    required this.action,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'icon': icon,
    'type': type,
    'action': action,
    'data': data,
  };

  factory AiOption.fromJson(Map<String, dynamic> json) => AiOption(
    id: json['id'] ?? '',
    label: json['label'] ?? '',
    icon: json['icon'] ?? '',
    type: json['type'] ?? 'secondary',
    action: json['action'] ?? '',
    data: json['data'] ?? {},
  );
}

class AiAssistantMessage {
  final String id;
  final AssistantMessageType type;
  final String? text;
  final bool isUser;
  final List<AiOption> options;
  final String? polishedPrompt;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? executionPlan;
  final List<String>? images;
  final String? analysis;
  final String? matchedSkillId;
  final String? matchedSkillName;
  final DateTime timestamp;

  AiAssistantMessage({
    String? id,
    required this.type,
    this.text,
    this.isUser = false,
    this.options = const [],
    this.polishedPrompt,
    this.plan,
    this.executionPlan,
    this.images,
    this.analysis,
    this.matchedSkillId,
    this.matchedSkillName,
    DateTime? timestamp,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'isUser': isUser,
    'options': options.map((o) => o.toJson()).toList(),
    'polishedPrompt': polishedPrompt,
    'plan': plan,
    'executionPlan': executionPlan,
    'images': images,
    'analysis': analysis,
    'matchedSkillId': matchedSkillId,
    'matchedSkillName': matchedSkillName,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AiAssistantMessage.fromJson(Map<String, dynamic> json) {
    return AiAssistantMessage(
      id: json['id'],
      type: AssistantMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssistantMessageType.text,
      ),
      text: json['text'],
      isUser: json['isUser'] ?? false,
      options: json['options'] != null
          ? (json['options'] as List).map((o) => AiOption.fromJson(o)).toList()
          : [],
      polishedPrompt: json['polishedPrompt'],
      plan: json['plan'] != null
          ? Map<String, dynamic>.from(json['plan'])
          : null,
      executionPlan: json['executionPlan'] != null
          ? Map<String, dynamic>.from(json['executionPlan'])
          : null,
      images: json['images'] != null ? List<String>.from(json['images']) : null,
      analysis: json['analysis'],
      matchedSkillId: json['matchedSkillId'],
      matchedSkillName: json['matchedSkillName'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }
}

class AiReferenceContext {
  final String id;
  final String name;
  final String path;
  final String description;
  final List<String> tags;
  final DateTime updatedAt;

  AiReferenceContext({
    required this.id,
    required this.name,
    required this.path,
    this.description = '',
    this.tags = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  AiReferenceContext copyWith({
    String? id,
    String? name,
    String? path,
    String? description,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return AiReferenceContext(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'description': description,
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AiReferenceContext.fromJson(Map<String, dynamic> json) {
    return AiReferenceContext(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tags: _readStringList(json['tags']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class AiImageTaskPlan {
  final String id;
  final String operation;
  final String prompt;
  final String model;
  final String aspectRatio;
  final String imageSize;
  final String imageQuality;
  final int? sampleSteps;
  final List<String> referenceImageIds;
  final String referenceQuery;
  final String angleLabel;
  final int batchCount;

  AiImageTaskPlan({
    String? id,
    this.operation = 'image_generate',
    required this.prompt,
    this.model = '',
    this.aspectRatio = '',
    this.imageSize = '',
    this.imageQuality = '',
    this.sampleSteps,
    this.referenceImageIds = const [],
    this.referenceQuery = '',
    this.angleLabel = '',
    this.batchCount = 1,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'operation': operation,
    'prompt': prompt,
    if (model.isNotEmpty) 'model': model,
    if (aspectRatio.isNotEmpty) 'aspectRatio': aspectRatio,
    if (imageSize.isNotEmpty) 'imageSize': imageSize,
    if (imageQuality.isNotEmpty) 'imageQuality': imageQuality,
    if (sampleSteps != null) 'sampleSteps': sampleSteps,
    'referenceImageIds': referenceImageIds,
    if (referenceQuery.isNotEmpty) 'referenceQuery': referenceQuery,
    if (angleLabel.isNotEmpty) 'angleLabel': angleLabel,
    'batchCount': batchCount,
  };

  factory AiImageTaskPlan.fromJson(Map<String, dynamic> json) {
    return AiImageTaskPlan(
      id: json['id']?.toString(),
      operation: json['operation']?.toString() ?? 'image_generate',
      prompt: json['prompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      aspectRatio: json['aspectRatio']?.toString() ?? '',
      imageSize: json['imageSize']?.toString() ?? '',
      imageQuality: json['imageQuality']?.toString() ?? '',
      sampleSteps: _readNullableInt(json['sampleSteps']),
      referenceImageIds: _readStringList(
        json['referenceImageIds'] ?? json['reference_image_ids'],
      ),
      referenceQuery:
          json['referenceQuery']?.toString() ??
          json['reference_query']?.toString() ??
          '',
      angleLabel:
          json['angleLabel']?.toString() ??
          json['angle_label']?.toString() ??
          '',
      batchCount: _readInt(json['batchCount'], 1),
    );
  }
}

class AiExecutionPlan {
  final String mode;
  final String prompt;
  final List<AiImageTaskPlan> imageTasks;
  final String script;
  final String reply;
  final int delayMs;
  final int maxConcurrency;
  final bool autoExecute;
  final String? reason;

  AiExecutionPlan({
    required this.mode,
    this.prompt = '',
    this.imageTasks = const [],
    this.script = '',
    this.reply = '',
    this.delayMs = 800,
    this.maxConcurrency = 3,
    this.autoExecute = true,
    this.reason,
  });

  bool get isImageMode =>
      mode == 'image_generate' || mode == 'image_edit' || mode == 'multi_angle';
  bool get isStoryboardMode => mode == 'storyboard';

  Map<String, dynamic> toJson() => {
    'mode': mode,
    if (prompt.isNotEmpty) 'prompt': prompt,
    'imageTasks': imageTasks.map((t) => t.toJson()).toList(),
    if (script.isNotEmpty) 'script': script,
    if (reply.isNotEmpty) 'reply': reply,
    'delayMs': delayMs,
    'maxConcurrency': maxConcurrency,
    'autoExecute': autoExecute,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };

  factory AiExecutionPlan.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['imageTasks'] ?? json['image_tasks'] ?? json['tasks'];
    final tasks = rawTasks is List
        ? rawTasks
              .whereType<Map>()
              .map(
                (e) => AiImageTaskPlan.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <AiImageTaskPlan>[];
    return AiExecutionPlan(
      mode:
          json['mode']?.toString() ??
          json['operation']?.toString() ??
          'image_generate',
      prompt: json['prompt']?.toString() ?? '',
      imageTasks: tasks,
      script: json['script']?.toString() ?? '',
      reply: json['reply']?.toString() ?? '',
      delayMs: _readInt(json['delayMs'] ?? json['delay_ms'], 800),
      maxConcurrency: _readInt(
        json['maxConcurrency'] ?? json['max_concurrency'],
        3,
      ),
      autoExecute: json['autoExecute'] is bool
          ? json['autoExecute'] as bool
          : json['auto_execute'] is bool
          ? json['auto_execute'] as bool
          : true,
      reason: json['reason']?.toString(),
    );
  }
}

class GenerationPlan {
  final String operation;
  final String prompt;
  final String model;
  final String aspectRatio;
  final String imageSize;
  final int batchCount;
  final String negativePrompt;
  final String videoResolution;
  final int videoFrameNum;
  final int videoSampleSteps;
  final double videoGuideScale;
  final double videoShiftScale;
  final int videoSeed;
  final String videoSampleSolver;
  final String videoTaskType;
  final String videoModelName;
  final String sourcePreference;
  final String? skillId;
  final String? skillName;

  GenerationPlan({
    this.operation = 'image_generate',
    required this.prompt,
    required this.model,
    required this.aspectRatio,
    required this.imageSize,
    this.batchCount = 1,
    this.negativePrompt = '',
    this.videoResolution = '1280*720',
    this.videoFrameNum = 81,
    this.videoSampleSteps = 50,
    this.videoGuideScale = 5.0,
    this.videoShiftScale = 5.0,
    this.videoSeed = -1,
    this.videoSampleSolver = 'unipc',
    this.videoTaskType = 't2v-A14B',
    this.videoModelName = 't2v-a14b',
    this.sourcePreference = 'selected_or_latest',
    this.skillId,
    this.skillName,
  });

  factory GenerationPlan.fromJson(Map<String, dynamic> json) => GenerationPlan(
    operation: json['operation'] ?? 'image_generate',
    prompt: json['prompt'] ?? '',
    model: json['model'] ?? '',
    aspectRatio: json['aspectRatio'] ?? '16:9',
    imageSize: json['imageSize'] ?? '2K',
    batchCount: _readInt(json['batchCount'], 1),
    negativePrompt: json['negativePrompt'] ?? '',
    videoResolution: json['videoResolution'] ?? '1280*720',
    videoFrameNum: _readInt(json['videoFrameNum'], 81),
    videoSampleSteps: _readInt(json['videoSampleSteps'], 50),
    videoGuideScale: (json['videoGuideScale'] as num?)?.toDouble() ?? 5.0,
    videoShiftScale: (json['videoShiftScale'] as num?)?.toDouble() ?? 5.0,
    videoSeed: _readInt(json['videoSeed'], -1),
    videoSampleSolver: json['videoSampleSolver'] ?? 'unipc',
    videoTaskType: json['videoTaskType'] ?? 't2v-A14B',
    videoModelName: json['videoModelName'] ?? 't2v-a14b',
    sourcePreference: json['sourcePreference'] ?? 'selected_or_latest',
    skillId: json['skillId'],
    skillName: json['skillName'],
  );

  GenerationPlan copyWith({
    String? operation,
    String? prompt,
    String? model,
    String? aspectRatio,
    String? imageSize,
    int? batchCount,
    String? negativePrompt,
    String? videoResolution,
    int? videoFrameNum,
    int? videoSampleSteps,
    double? videoGuideScale,
    double? videoShiftScale,
    int? videoSeed,
    String? videoSampleSolver,
    String? videoTaskType,
    String? videoModelName,
    String? sourcePreference,
    String? skillId,
    String? skillName,
  }) {
    return GenerationPlan(
      operation: operation ?? this.operation,
      prompt: prompt ?? this.prompt,
      model: model ?? this.model,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      imageSize: imageSize ?? this.imageSize,
      batchCount: batchCount ?? this.batchCount,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      videoResolution: videoResolution ?? this.videoResolution,
      videoFrameNum: videoFrameNum ?? this.videoFrameNum,
      videoSampleSteps: videoSampleSteps ?? this.videoSampleSteps,
      videoGuideScale: videoGuideScale ?? this.videoGuideScale,
      videoShiftScale: videoShiftScale ?? this.videoShiftScale,
      videoSeed: videoSeed ?? this.videoSeed,
      videoSampleSolver: videoSampleSolver ?? this.videoSampleSolver,
      videoTaskType: videoTaskType ?? this.videoTaskType,
      videoModelName: videoModelName ?? this.videoModelName,
      sourcePreference: sourcePreference ?? this.sourcePreference,
      skillId: skillId ?? this.skillId,
      skillName: skillName ?? this.skillName,
    );
  }

  Map<String, dynamic> toJson() => {
    'operation': operation,
    'prompt': prompt,
    'model': model,
    'aspectRatio': aspectRatio,
    'imageSize': imageSize,
    'batchCount': batchCount,
    if (negativePrompt.isNotEmpty) 'negativePrompt': negativePrompt,
    'videoResolution': videoResolution,
    'videoFrameNum': videoFrameNum,
    'videoSampleSteps': videoSampleSteps,
    'videoGuideScale': videoGuideScale,
    'videoShiftScale': videoShiftScale,
    'videoSeed': videoSeed,
    'videoSampleSolver': videoSampleSolver,
    'videoTaskType': videoTaskType,
    'videoModelName': videoModelName,
    'sourcePreference': sourcePreference,
    if (skillId != null) 'skillId': skillId,
    if (skillName != null) 'skillName': skillName,
  };
}

class AiAssistantResponse {
  final String replyText;
  final AssistantPhase phase;
  final List<AiOption> options;
  final GenerationPlan? plan;
  final AiExecutionPlan? executionPlan;

  AiAssistantResponse({
    required this.replyText,
    required this.phase,
    this.options = const [],
    this.plan,
    this.executionPlan,
  });
}

class SkillSaveRequest {
  final String name;
  final String category;
  final List<String> tags;
  final String originalPrompt;
  final String polishedPrompt;
  final String model;
  final String aspectRatio;
  final String imageSize;
  final List<String> resultImages;

  SkillSaveRequest({
    required this.name,
    required this.category,
    required this.tags,
    required this.originalPrompt,
    required this.polishedPrompt,
    required this.model,
    required this.aspectRatio,
    required this.imageSize,
    this.resultImages = const [],
  });
}

int _readInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _readNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _readStringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return const [];
}
