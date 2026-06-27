import 'shot.dart';
import 'film_scene_asset.dart';

class FilmTab {
  final String id;
  final String name;
  final List<Shot> shots;
  final Map<int, String> shotStatus;
  final Map<int, String?> shotImages;
  final Map<int, int> shotTimer;
  final List<String> referenceImages;
  final Map<int, String> imageRemarks;
  final Map<int, String> slotAssetIds; // 槽位关联的资产ID
  final List<FilmSceneAsset> sceneAssets;
  final String selectedModel;
  final String selectedAspectRatio;
  final String selectedImageSize;
  final bool isSplitting;
  final String thoughtProcess;

  FilmTab({
    required this.id,
    required this.name,
    this.shots = const [],
    this.shotStatus = const {},
    this.shotImages = const {},
    this.shotTimer = const {},
    List<String>? referenceImages,
    this.imageRemarks = const {},
    this.slotAssetIds = const {},
    this.sceneAssets = const [],
    this.selectedModel = 'nano-banana-fast',
    this.selectedAspectRatio = '16:9',
    this.selectedImageSize = '1K',
    this.isSplitting = false,
    this.thoughtProcess = '',
  }) : referenceImages = referenceImages ?? List.generate(14, (_) => '');

  FilmTab copyWith({
    String? id,
    String? name,
    List<Shot>? shots,
    Map<int, String>? shotStatus,
    Map<int, String?>? shotImages,
    Map<int, int>? shotTimer,
    List<String>? referenceImages,
    Map<int, String>? imageRemarks,
    Map<int, String>? slotAssetIds,
    List<FilmSceneAsset>? sceneAssets,
    String? selectedModel,
    String? selectedAspectRatio,
    String? selectedImageSize,
    bool? isSplitting,
    String? thoughtProcess,
  }) {
    return FilmTab(
      id: id ?? this.id,
      name: name ?? this.name,
      shots: shots ?? this.shots,
      shotStatus: shotStatus ?? this.shotStatus,
      shotImages: shotImages ?? this.shotImages,
      shotTimer: shotTimer ?? this.shotTimer,
      referenceImages: referenceImages ?? this.referenceImages,
      imageRemarks: imageRemarks ?? this.imageRemarks,
      slotAssetIds: slotAssetIds ?? this.slotAssetIds,
      sceneAssets: sceneAssets ?? this.sceneAssets,
      selectedModel: selectedModel ?? this.selectedModel,
      selectedAspectRatio: selectedAspectRatio ?? this.selectedAspectRatio,
      selectedImageSize: selectedImageSize ?? this.selectedImageSize,
      isSplitting: isSplitting ?? this.isSplitting,
      thoughtProcess: thoughtProcess ?? this.thoughtProcess,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shots': shots.map((s) => s.toJson()).toList(),
      'shotStatus': shotStatus.map((k, v) => MapEntry(k.toString(), v)),
      'shotImages': shotImages.map((k, v) => MapEntry(k.toString(), v)),
      'shotTimer': shotTimer.map((k, v) => MapEntry(k.toString(), v)),
      'referenceImages': referenceImages,
      'imageRemarks': imageRemarks.map((k, v) => MapEntry(k.toString(), v)),
      'slotAssetIds': slotAssetIds.map((k, v) => MapEntry(k.toString(), v)),
      'sceneAssets': sceneAssets.map((asset) => asset.toJson()).toList(),
      'selectedModel': selectedModel,
      'selectedAspectRatio': selectedAspectRatio,
      'selectedImageSize': selectedImageSize,
      'isSplitting': isSplitting,
      'thoughtProcess': thoughtProcess,
    };
  }

  factory FilmTab.fromJson(Map<String, dynamic> json) {
    return FilmTab(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      shots:
          (json['shots'] as List?)?.map((s) => Shot.fromJson(s)).toList() ?? [],
      shotStatus:
          (json['shotStatus'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k.toString()), v.toString()),
          ) ??
          {},
      shotImages:
          (json['shotImages'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k.toString()), v?.toString()),
          ) ??
          {},
      shotTimer:
          (json['shotTimer'] as Map?)?.map(
            (k, v) =>
                MapEntry(int.parse(k.toString()), int.parse(v.toString())),
          ) ??
          {},
      referenceImages:
          (json['referenceImages'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          List.generate(14, (_) => ''),
      imageRemarks:
          (json['imageRemarks'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k.toString()), v.toString()),
          ) ??
          {},
      slotAssetIds:
          (json['slotAssetIds'] as Map?)?.map(
            (k, v) => MapEntry(int.parse(k.toString()), v.toString()),
          ) ??
          {},
      sceneAssets:
          (json['sceneAssets'] as List?)
              ?.whereType<Map>()
              .map(
                (asset) =>
                    FilmSceneAsset.fromJson(Map<String, dynamic>.from(asset)),
              )
              .toList() ??
          const [],
      selectedModel: json['selectedModel'] ?? 'nano-banana-fast',
      selectedAspectRatio: json['selectedAspectRatio'] ?? '16:9',
      selectedImageSize: json['selectedImageSize'] ?? '1K',
      isSplitting: json['isSplitting'] ?? false,
      thoughtProcess: json['thoughtProcess'] ?? '',
    );
  }
}
