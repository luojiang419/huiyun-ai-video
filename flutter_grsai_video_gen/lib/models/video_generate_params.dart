class VideoGenerateParams {
  final String prompt;
  final String negativePrompt;
  final String resolution;
  final int frameNum;
  final int sampleSteps;
  final double guideScale;
  final double shiftScale;
  final int seed;
  final String sampleSolver;
  final String taskType;
  final String modelName;
  final Map<String, dynamic> advancedSettings;

  const VideoGenerateParams({
    this.prompt = '',
    this.negativePrompt = '',
    this.resolution = '1280*720',
    this.frameNum = 81,
    this.sampleSteps = 50,
    this.guideScale = 5.0,
    this.shiftScale = 5.0,
    this.seed = -1,
    this.sampleSolver = 'unipc',
    this.taskType = 't2v-A14B',
    this.modelName = 't2v-a14b',
    this.advancedSettings = const {},
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'resolution': resolution,
      'frame_num': frameNum,
      'sample_steps': sampleSteps,
      'guide_scale': guideScale,
      'shift_scale': shiftScale,
      'seed': seed,
      'sample_solver': sampleSolver,
      'task_type': taskType,
      'model_name': modelName,
    };
    json.addAll(advancedSettings);
    return json;
  }

  factory VideoGenerateParams.fromJson(Map<String, dynamic> json) =>
      VideoGenerateParams(
        prompt: json['prompt']?.toString() ?? '',
        negativePrompt: json['negative_prompt']?.toString() ?? '',
        resolution: json['resolution']?.toString() ?? '1280*720',
        frameNum: (json['frame_num'] as num?)?.toInt() ?? 81,
        sampleSteps: (json['sample_steps'] as num?)?.toInt() ?? 50,
        guideScale: (json['guide_scale'] as num?)?.toDouble() ?? 5.0,
        shiftScale: (json['shift_scale'] as num?)?.toDouble() ?? 5.0,
        seed: (json['seed'] as num?)?.toInt() ?? -1,
        sampleSolver: json['sample_solver']?.toString() ?? 'unipc',
        taskType: json['task_type']?.toString() ?? 't2v-A14B',
        modelName: json['model_name']?.toString() ?? 't2v-a14b',
        advancedSettings: Map<String, dynamic>.from(json)
          ..remove('prompt')
          ..remove('negative_prompt')
          ..remove('resolution')
          ..remove('frame_num')
          ..remove('sample_steps')
          ..remove('guide_scale')
          ..remove('shift_scale')
          ..remove('seed')
          ..remove('sample_solver')
          ..remove('task_type')
          ..remove('model_name'),
      );

  VideoGenerateParams copyWith({
    String? prompt,
    String? negativePrompt,
    String? resolution,
    int? frameNum,
    int? sampleSteps,
    double? guideScale,
    double? shiftScale,
    int? seed,
    String? sampleSolver,
    String? taskType,
    String? modelName,
    Map<String, dynamic>? advancedSettings,
  }) {
    return VideoGenerateParams(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      resolution: resolution ?? this.resolution,
      frameNum: frameNum ?? this.frameNum,
      sampleSteps: sampleSteps ?? this.sampleSteps,
      guideScale: guideScale ?? this.guideScale,
      shiftScale: shiftScale ?? this.shiftScale,
      seed: seed ?? this.seed,
      sampleSolver: sampleSolver ?? this.sampleSolver,
      taskType: taskType ?? this.taskType,
      modelName: modelName ?? this.modelName,
      advancedSettings: advancedSettings ?? this.advancedSettings,
    );
  }
}
