class Shot {
  final String shotNumber;
  final String shotName;
  final String shotType;
  final String cameraAngle;
  final String lighting;
  final String sceneDescription;
  final String sceneDetails;
  final String textInFrame;
  final String objectState;
  final String characterName;
  final String costume;
  final String action;
  final String expression;
  final String props;
  final String prompt;
  final String movement;
  final List<String> characters;
  final String? summary;
  String? imagePath;
  final List<String> referenceImagePaths;
  final Map<String, String>? assetRemarks;
  final List<String> manualReferenceImages;

  Shot({
    this.shotNumber = '',
    this.shotName = '',
    required this.shotType,
    this.cameraAngle = '',
    this.lighting = '',
    this.sceneDescription = '',
    this.sceneDetails = '',
    this.textInFrame = '无',
    this.objectState = '无',
    this.characterName = '无',
    this.costume = '无',
    this.action = '无',
    this.expression = '无',
    this.props = '无',
    required this.prompt,
    required this.movement,
    this.characters = const [],
    this.summary,
    this.imagePath,
    this.referenceImagePaths = const [],
    this.assetRemarks,
    this.manualReferenceImages = const [],
  });

  factory Shot.fromJson(Map<String, dynamic> json) {
    return Shot(
      shotNumber: json['shotNumber'] ?? '',
      shotName: json['shotName'] ?? '',
      shotType: json['shotType'] ?? '中景',
      cameraAngle: json['cameraAngle'] ?? '',
      lighting: json['lighting'] ?? '',
      sceneDescription: json['sceneDescription'] ?? '',
      sceneDetails: json['sceneDetails'] ?? '',
      textInFrame: json['textInFrame'] ?? '无',
      objectState: json['objectState'] ?? '无',
      characterName: json['characterName'] ?? '无',
      costume: json['costume'] ?? '无',
      action: json['action'] ?? '无',
      expression: json['expression'] ?? '无',
      props: json['props'] ?? '无',
      movement: json['movement'] ?? '固定镜头',
      prompt: json['prompt'] ?? '',
      characters: json['characters'] != null
          ? List<String>.from(json['characters'])
          : [],
      summary: json['summary'],
      imagePath: json['imagePath'],
      referenceImagePaths: json['referenceImagePaths'] != null
          ? List<String>.from(json['referenceImagePaths'])
          : [],
      assetRemarks: json['assetRemarks'] != null
          ? Map<String, String>.from(json['assetRemarks'])
          : null,
      manualReferenceImages: json['manualReferenceImages'] != null
          ? List<String>.from(json['manualReferenceImages'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shotNumber': shotNumber,
      'shotName': shotName,
      'shotType': shotType,
      'cameraAngle': cameraAngle,
      'lighting': lighting,
      'sceneDescription': sceneDescription,
      'sceneDetails': sceneDetails,
      'textInFrame': textInFrame,
      'objectState': objectState,
      'characterName': characterName,
      'costume': costume,
      'action': action,
      'expression': expression,
      'props': props,
      'movement': movement,
      'prompt': prompt,
      'characters': characters,
      'summary': summary,
      'imagePath': imagePath,
      'referenceImagePaths': referenceImagePaths,
      'assetRemarks': assetRemarks,
      'manualReferenceImages': manualReferenceImages,
    };
  }

  Shot copyWith({
    String? shotNumber,
    String? shotName,
    String? shotType,
    String? cameraAngle,
    String? lighting,
    String? sceneDescription,
    String? sceneDetails,
    String? textInFrame,
    String? objectState,
    String? characterName,
    String? costume,
    String? action,
    String? expression,
    String? props,
    String? prompt,
    String? movement,
    List<String>? characters,
    String? summary,
    String? imagePath,
    List<String>? referenceImagePaths,
    Map<String, String>? assetRemarks,
    List<String>? manualReferenceImages,
  }) {
    return Shot(
      shotNumber: shotNumber ?? this.shotNumber,
      shotName: shotName ?? this.shotName,
      shotType: shotType ?? this.shotType,
      cameraAngle: cameraAngle ?? this.cameraAngle,
      lighting: lighting ?? this.lighting,
      sceneDescription: sceneDescription ?? this.sceneDescription,
      sceneDetails: sceneDetails ?? this.sceneDetails,
      textInFrame: textInFrame ?? this.textInFrame,
      objectState: objectState ?? this.objectState,
      characterName: characterName ?? this.characterName,
      costume: costume ?? this.costume,
      action: action ?? this.action,
      expression: expression ?? this.expression,
      props: props ?? this.props,
      movement: movement ?? this.movement,
      prompt: prompt ?? this.prompt,
      characters: characters ?? this.characters,
      summary: summary ?? this.summary,
      imagePath: imagePath ?? this.imagePath,
      referenceImagePaths: referenceImagePaths ?? this.referenceImagePaths,
      assetRemarks: assetRemarks ?? this.assetRemarks,
      manualReferenceImages: manualReferenceImages ?? this.manualReferenceImages,
    );
  }
}
