import 'package:uuid/uuid.dart';

class Message {
  final String id;
  final String type;
  final String text;
  final List<String> images;
  final List<String> videos;
  final Map<String, dynamic>? params;

  Message({
    String? id,
    required this.type,
    required this.text,
    required this.images,
    this.videos = const [],
    this.params,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'text': text,
    'images': images,
    'videos': videos,
    if (params != null) 'params': params,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    type: json['type'],
    text: json['text'],
    images: List<String>.from(json['images']),
    videos: json['videos'] != null
        ? List<String>.from(json['videos'])
        : const [],
    params: json['params'] as Map<String, dynamic>?,
  );
}
