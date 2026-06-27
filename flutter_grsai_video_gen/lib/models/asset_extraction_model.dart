class ScriptAssetExtraction {
  final String sceneId;
  final String sceneLocation;
  final List<ExtractedAsset> assets;

  ScriptAssetExtraction({
    required this.sceneId,
    required this.sceneLocation,
    required this.assets,
  });

  factory ScriptAssetExtraction.fromJson(Map<String, dynamic> json) {
    return ScriptAssetExtraction(
      sceneId: json['scene_id'] ?? '',
      sceneLocation: json['scene_location'] ?? '',
      assets: (json['assets'] as List?)
              ?.map((e) => ExtractedAsset.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ExtractedAsset {
  final String type;
  final String name;
  final String label;
  final String description;
  final String reasoning;

  bool isSelected;
  List<String> referenceImages;
  List<String> generatedImageUrls;
  bool isGenerating;

  ExtractedAsset({
    required this.type,
    required this.name,
    required this.label,
    required this.description,
    required this.reasoning,
    this.isSelected = true,
    List<String>? referenceImages,
    List<String>? generatedImageUrls,
    this.isGenerating = false,
  }) : referenceImages = referenceImages ?? [],
       generatedImageUrls = generatedImageUrls ?? [];

  factory ExtractedAsset.fromJson(Map<String, dynamic> json) {
    return ExtractedAsset(
      type: json['type'] ?? 'prop',
      name: json['name'] ?? '',
      label: json['label'] ?? '',
      description: json['description'] ?? '',
      reasoning: json['reasoning'] ?? '',
    );
  }

  ExtractedAsset copyWith({
    String? type,
    String? name,
    String? label,
    String? description,
    String? reasoning,
    bool? isSelected,
    List<String>? referenceImages,
    List<String>? generatedImageUrls,
    bool? isGenerating,
  }) {
    return ExtractedAsset(
      type: type ?? this.type,
      name: name ?? this.name,
      label: label ?? this.label,
      description: description ?? this.description,
      reasoning: reasoning ?? this.reasoning,
      isSelected: isSelected ?? this.isSelected,
      referenceImages: referenceImages ?? this.referenceImages,
      generatedImageUrls: generatedImageUrls ?? this.generatedImageUrls,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}
