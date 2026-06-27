class TaskSubmitResult {
  final String taskId;
  final String status;
  final int? position;
  final DateTime? createdAt;

  const TaskSubmitResult({
    required this.taskId,
    this.status = 'queued',
    this.position,
    this.createdAt,
  });

  factory TaskSubmitResult.fromJson(Map<String, dynamic> json) =>
      TaskSubmitResult(
        taskId: json['task_id']?.toString() ?? json['taskId']?.toString() ?? '',
        status: json['status']?.toString() ?? 'queued',
        position:
            (json['position'] as num?)?.toInt() ??
            (json['queue_position'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

class VideoTaskProgress {
  final String taskId;
  final String status;
  final int currentStep;
  final int totalSteps;
  final double percentage;
  final int? etaSeconds;
  final int queuePosition;

  const VideoTaskProgress({
    required this.taskId,
    this.status = 'queued',
    this.currentStep = 0,
    this.totalSteps = 0,
    this.percentage = 0,
    this.etaSeconds,
    this.queuePosition = 0,
  });

  factory VideoTaskProgress.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] is Map<String, dynamic>
        ? json['progress'] as Map<String, dynamic>
        : json['progress'] is Map
        ? Map<String, dynamic>.from(json['progress'] as Map)
        : <String, dynamic>{};
    return VideoTaskProgress(
      taskId: json['task_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'queued',
      currentStep: (progress['current_step'] as num?)?.toInt() ?? 0,
      totalSteps: (progress['total_steps'] as num?)?.toInt() ?? 0,
      percentage: (progress['percentage'] as num?)?.toDouble() ?? 0,
      etaSeconds: (progress['eta_seconds'] as num?)?.toInt(),
      queuePosition: (json['queue_position'] as num?)?.toInt() ?? 0,
    );
  }
}

class ModelInfo {
  final String id;
  final String name;
  final String type;
  final String description;
  final bool loaded;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.type,
    this.description = '',
    this.loaded = false,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['id']?.toString() ?? '',
    type: json['type']?.toString() ?? 't2v',
    description: json['description']?.toString() ?? '',
    loaded: json['loaded'] == true,
  );
}

class ModelChoiceInfo {
  final String id;
  final String label;
  final String name;
  final String type;
  final String description;
  final bool loaded;

  const ModelChoiceInfo({
    required this.id,
    required this.label,
    required this.name,
    required this.type,
    this.description = '',
    this.loaded = false,
  });

  factory ModelChoiceInfo.fromJson(Map<String, dynamic> json) =>
      ModelChoiceInfo(
        id: json['id']?.toString() ?? '',
        label:
            json['label']?.toString() ??
            json['name']?.toString() ??
            json['id']?.toString() ??
            '',
        name: json['name']?.toString() ?? json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 't2v',
        description: json['description']?.toString() ?? '',
        loaded: json['loaded'] == true,
      );
}

class ModelBaseInfo {
  final String id;
  final String label;
  final List<ModelChoiceInfo> models;

  const ModelBaseInfo({
    required this.id,
    required this.label,
    required this.models,
  });

  factory ModelBaseInfo.fromJson(Map<String, dynamic> json) => ModelBaseInfo(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? json['id']?.toString() ?? '',
    models: ((json['models'] as List?) ?? const [])
        .map(
          (item) => ModelChoiceInfo.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
  );
}

class ModelFamilyInfo {
  final String id;
  final String label;
  final List<ModelBaseInfo> bases;

  const ModelFamilyInfo({
    required this.id,
    required this.label,
    required this.bases,
  });

  factory ModelFamilyInfo.fromJson(Map<String, dynamic> json) =>
      ModelFamilyInfo(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? json['id']?.toString() ?? '',
        bases: ((json['bases'] as List?) ?? const [])
            .map(
              (item) => ModelBaseInfo.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
      );
}

class ModelCatalog {
  final List<ModelInfo> models;
  final List<ModelFamilyInfo> t2vFamilies;
  final List<ModelFamilyInfo> i2vFamilies;
  final String? currentModelId;

  const ModelCatalog({
    required this.models,
    required this.t2vFamilies,
    required this.i2vFamilies,
    this.currentModelId,
  });

  factory ModelCatalog.fromJson(Map<String, dynamic> json) {
    final hierarchy = json['hierarchy'] is Map<String, dynamic>
        ? json['hierarchy'] as Map<String, dynamic>
        : json['hierarchy'] is Map
        ? Map<String, dynamic>.from(json['hierarchy'] as Map)
        : <String, dynamic>{};
    return ModelCatalog(
      models: ((json['models'] as List?) ?? const [])
          .map((item) => ModelInfo.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      t2vFamilies: ((hierarchy['t2v'] as List?) ?? const [])
          .map(
            (item) => ModelFamilyInfo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      i2vFamilies: ((hierarchy['i2v'] as List?) ?? const [])
          .map(
            (item) => ModelFamilyInfo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      currentModelId: json['current']?.toString(),
    );
  }

  ModelCatalog filterHiddenModels(Set<String> hiddenModelIds) {
    if (hiddenModelIds.isEmpty) {
      return this;
    }

    List<ModelFamilyInfo> filterFamilies(List<ModelFamilyInfo> families) {
      return families
          .map((family) {
            final filteredBases = family.bases
                .map((base) {
                  final filteredModels = base.models
                      .where((model) => !hiddenModelIds.contains(model.id))
                      .toList();
                  if (filteredModels.isEmpty) {
                    return null;
                  }
                  return ModelBaseInfo(
                    id: base.id,
                    label: base.label,
                    models: filteredModels,
                  );
                })
                .whereType<ModelBaseInfo>()
                .toList();
            if (filteredBases.isEmpty) {
              return null;
            }
            return ModelFamilyInfo(
              id: family.id,
              label: family.label,
              bases: filteredBases,
            );
          })
          .whereType<ModelFamilyInfo>()
          .toList();
    }

    return ModelCatalog(
      models: models
          .where((model) => !hiddenModelIds.contains(model.id))
          .toList(),
      t2vFamilies: filterFamilies(t2vFamilies),
      i2vFamilies: filterFamilies(i2vFamilies),
      currentModelId: hiddenModelIds.contains(currentModelId)
          ? null
          : currentModelId,
    );
  }
}

class VideoServerInfo {
  final String gpuName;
  final int queueLength;
  final bool isGenerating;
  final int? latency;

  const VideoServerInfo({
    this.gpuName = '',
    this.queueLength = 0,
    this.isGenerating = false,
    this.latency,
  });

  factory VideoServerInfo.fromJson(Map<String, dynamic> json) =>
      VideoServerInfo(
        gpuName: json['gpu_name']?.toString() ?? '',
        queueLength: (json['queue_length'] as num?)?.toInt() ?? 0,
        isGenerating: json['is_generating'] == true,
        latency: (json['latency'] as num?)?.toInt(),
      );
}
