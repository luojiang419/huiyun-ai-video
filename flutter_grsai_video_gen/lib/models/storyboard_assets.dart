class StoryboardAssets {
  final List<String> characters;
  final List<String> props;
  final List<String> costumes;
  final List<String> scenes;
  final String atmosphere;

  StoryboardAssets({
    this.characters = const [],
    this.props = const [],
    this.costumes = const [],
    this.scenes = const [],
    this.atmosphere = '',
  });

  factory StoryboardAssets.fromJson(Map<String, dynamic> json) {
    return StoryboardAssets(
      characters: json['characters'] != null ? List<String>.from(json['characters']) : [],
      props: json['props'] != null ? List<String>.from(json['props']) : [],
      costumes: json['costumes'] != null ? List<String>.from(json['costumes']) : [],
      scenes: json['scenes'] != null ? List<String>.from(json['scenes']) : [],
      atmosphere: json['atmosphere'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characters': characters,
      'props': props,
      'costumes': costumes,
      'scenes': scenes,
      'atmosphere': atmosphere,
    };
  }

  String toFormattedString() {
    return '''# 项目资产统计
人物：${characters.isEmpty ? '无' : characters.join('、')}
关键道具：${props.isEmpty ? '无' : props.join('、')}
服装：${costumes.isEmpty ? '无' : costumes.join('、')}
场景：${scenes.isEmpty ? '无' : scenes.join('、')}
氛围：${atmosphere.isEmpty ? '无' : atmosphere}''';
  }

  static StoryboardAssets parseFromString(String content) {
    final lines = content.split('\n');
    final characters = <String>[];
    final props = <String>[];
    final costumes = <String>[];
    final scenes = <String>[];
    String atmosphere = '';

    for (final line in lines) {
      if (line.startsWith('人物：')) {
        final value = line.substring(3).trim();
        if (value != '无') characters.addAll(value.split('、').map((e) => e.trim()));
      } else if (line.startsWith('关键道具：')) {
        final value = line.substring(5).trim();
        if (value != '无') props.addAll(value.split('、').map((e) => e.trim()));
      } else if (line.startsWith('服装：')) {
        final value = line.substring(3).trim();
        if (value != '无') costumes.addAll(value.split('、').map((e) => e.trim()));
      } else if (line.startsWith('场景：')) {
        final value = line.substring(3).trim();
        if (value != '无') scenes.addAll(value.split('、').map((e) => e.trim()));
      } else if (line.startsWith('氛围：')) {
        atmosphere = line.substring(3).trim();
        if (atmosphere == '无') atmosphere = '';
      }
    }

    return StoryboardAssets(
      characters: characters,
      props: props,
      costumes: costumes,
      scenes: scenes,
      atmosphere: atmosphere,
    );
  }
}
