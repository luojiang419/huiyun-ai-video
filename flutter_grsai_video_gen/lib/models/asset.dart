/// 资产的单张参考图片
class AssetRefImage {
  final String path;
  final String name;
  final String description;

  AssetRefImage({
    required this.path,
    this.name = '',
    this.description = '',
  });

  factory AssetRefImage.fromJson(Map<String, dynamic> json) {
    return AssetRefImage(
      path: json['path'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'description': description,
    };
  }

  AssetRefImage copyWith({
    String? path,
    String? name,
    String? description,
  }) {
    return AssetRefImage(
      path: path ?? this.path,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }
}

class Asset {
  final String id;
  final String name;
  final String category;
  final String imagePath; // 主图路径（向后兼容）
  final String description;
  final List<AssetRefImage> images; // 附加参考图列表

  Asset({
    required this.id,
    required this.name,
    required this.category,
    required this.imagePath,
    this.description = '',
    this.images = const [],
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    // 解析附加图片列表
    List<AssetRefImage> images = [];
    if (json['images'] != null) {
      images = (json['images'] as List)
          .map((e) => AssetRefImage.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return Asset(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      imagePath: json['imagePath'] as String,
      description: json['description'] as String? ?? '',
      images: images,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'imagePath': imagePath,
      'description': description,
      'images': images.map((e) => e.toJson()).toList(),
    };
  }

  /// 获取所有图片（主图 + 附加图），用于匹配时遍历
  List<AssetRefImage> get allImages {
    final list = <AssetRefImage>[
      AssetRefImage(path: imagePath, name: name, description: description),
    ];
    list.addAll(images);
    return list;
  }

  Asset copyWith({
    String? id,
    String? name,
    String? category,
    String? imagePath,
    String? description,
    List<AssetRefImage>? images,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      imagePath: imagePath ?? this.imagePath,
      description: description ?? this.description,
      images: images ?? this.images,
    );
  }
}
