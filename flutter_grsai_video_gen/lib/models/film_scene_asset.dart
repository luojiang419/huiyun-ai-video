class FilmSceneAssetView {
  final String name;
  final String prompt;
  final String description;

  const FilmSceneAssetView({
    required this.name,
    required this.prompt,
    required this.description,
  });
}

class FilmSceneAssetViews {
  static const front = '正面';
  static const left = '左侧';
  static const right = '右侧';
  static const left45 = '45度左侧';
  static const right45 = '45度右侧';
  static const back = '背面';

  static const List<FilmSceneAssetView> all = [
    FilmSceneAssetView(
      name: front,
      prompt: 'front view, facing camera, clear full subject design',
      description: '正面视图',
    ),
    FilmSceneAssetView(
      name: left,
      prompt: 'left side view, profile view from the left',
      description: '左侧视图',
    ),
    FilmSceneAssetView(
      name: right,
      prompt: 'right side view, profile view from the right',
      description: '右侧视图',
    ),
    FilmSceneAssetView(
      name: left45,
      prompt: 'three-quarter left view, 45 degree angle from the left front',
      description: '45度左侧视图',
    ),
    FilmSceneAssetView(
      name: right45,
      prompt: 'three-quarter right view, 45 degree angle from the right front',
      description: '45度右侧视图',
    ),
    FilmSceneAssetView(
      name: back,
      prompt: 'back view, seen from behind',
      description: '背面视图',
    ),
  ];

  static List<String> get names => all.map((view) => view.name).toList();

  static List<FilmSceneAssetView> requiredForCategory(String category) {
    if (category == 'Scene') {
      return [all.first];
    }
    return all;
  }

  static bool appliesToCategory(String category, String viewName) {
    return requiredForCategory(category).any((view) => view.name == viewName);
  }

  static List<FilmSceneAssetView> buildGenerationSequence(
    String category, {
    String? onlyViewName,
    bool hasFrontImage = false,
  }) {
    final availableViews = requiredForCategory(category);
    final normalizedOnlyViewName =
        onlyViewName != null && !appliesToCategory(category, onlyViewName)
        ? front
        : onlyViewName;
    if (normalizedOnlyViewName == null) {
      return availableViews;
    }

    final targetViews = availableViews
        .where((view) => view.name == normalizedOnlyViewName)
        .toList();
    if (targetViews.isEmpty) {
      return [availableViews.first];
    }
    if (normalizedOnlyViewName != front && !hasFrontImage) {
      return [availableViews.first, ...targetViews];
    }
    return targetViews;
  }
}

class FilmSceneAsset {
  final String id;
  final String name;
  final String category;
  final String description;
  final List<int> sourceShotIndexes;
  final bool selected;
  final String status;
  final Map<String, String> viewImages;
  final Map<String, String> viewStatus;
  final Map<String, String> viewErrors;
  final String? assetId;

  const FilmSceneAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.sourceShotIndexes = const [],
    this.selected = true,
    this.status = '待生成',
    this.viewImages = const {},
    this.viewStatus = const {},
    this.viewErrors = const {},
    this.assetId,
  });

  factory FilmSceneAsset.fromJson(Map<String, dynamic> json) {
    return FilmSceneAsset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Other',
      description: json['description']?.toString() ?? '',
      sourceShotIndexes:
          (json['sourceShotIndexes'] as List?)
              ?.map((item) => int.tryParse(item.toString()))
              .whereType<int>()
              .toList() ??
          const [],
      selected: json['selected'] as bool? ?? true,
      status: json['status']?.toString() ?? '待生成',
      viewImages:
          (json['viewImages'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
      viewStatus:
          (json['viewStatus'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
      viewErrors:
          (json['viewErrors'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
      assetId: json['assetId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'description': description,
      'sourceShotIndexes': sourceShotIndexes,
      'selected': selected,
      'status': status,
      'viewImages': viewImages,
      'viewStatus': viewStatus,
      'viewErrors': viewErrors,
      'assetId': assetId,
    };
  }

  FilmSceneAsset copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    List<int>? sourceShotIndexes,
    bool? selected,
    String? status,
    Map<String, String>? viewImages,
    Map<String, String>? viewStatus,
    Map<String, String>? viewErrors,
    String? assetId,
    bool clearAssetId = false,
  }) {
    return FilmSceneAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      sourceShotIndexes: sourceShotIndexes ?? this.sourceShotIndexes,
      selected: selected ?? this.selected,
      status: status ?? this.status,
      viewImages: viewImages ?? this.viewImages,
      viewStatus: viewStatus ?? this.viewStatus,
      viewErrors: viewErrors ?? this.viewErrors,
      assetId: clearAssetId ? null : assetId ?? this.assetId,
    );
  }

  bool get isComplete => FilmSceneAssetViews.requiredForCategory(
    category,
  ).every((view) => viewImages[view.name]?.isNotEmpty == true);
}
