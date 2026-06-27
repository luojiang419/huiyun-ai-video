class ApiConfig {
  final String id;
  final String name;
  final String type;
  final String url;
  final String key;
  final String model;
  final bool isDefault;

  ApiConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.key,
    required this.model,
    required this.isDefault,
  });

  ApiConfig copyWith({
    String? id,
    String? name,
    String? type,
    String? url,
    String? key,
    String? model,
    bool? isDefault,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      key: key ?? this.key,
      model: model ?? this.model,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'key': key,
        'model': model,
        'isDefault': isDefault,
      };

  factory ApiConfig.fromJson(Map<String, dynamic> json) => ApiConfig(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        type: json['type'] ?? '',
        url: json['url'] ?? '',
        key: json['key'] ?? '',
        model: json['model'] ?? '',
        isDefault: json['isDefault'] ?? false,
      );
}
