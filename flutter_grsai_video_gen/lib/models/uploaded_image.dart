import 'dart:typed_data';

class UploadedImage {
  final String id;
  final String name;
  final String path;
  final String base64;
  final Uint8List bytes;

  UploadedImage({
    required this.id,
    required this.name,
    required this.path,
    required this.base64,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'base64': base64,
      };

  factory UploadedImage.fromJson(Map<String, dynamic> json) => UploadedImage(
        id: json['id'],
        name: json['name'],
        path: json['path'],
        base64: json['base64'],
        bytes: Uint8List(0),
      );
}
