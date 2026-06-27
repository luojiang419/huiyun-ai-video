import 'video_generate_params.dart';
import 'video_task.dart';

class VideoItem {
  final String id;
  final String taskId;
  final String localPath;
  final String fileName;
  final int fileSize;
  final String resolution;
  final String prompt;
  final String? thumbnailPath;
  final VideoTaskType type;
  final String? nodeName;
  final DateTime createdAt;
  final String? sourceImagePath;
  final VideoGenerateParams? paramsSnapshot;
  final bool isFavorite;
  final DateTime? favoritedAt;

  const VideoItem({
    required this.id,
    required this.taskId,
    required this.localPath,
    required this.fileName,
    required this.prompt,
    required this.type,
    required this.createdAt,
    this.fileSize = 0,
    this.resolution = '',
    this.thumbnailPath,
    this.nodeName,
    this.sourceImagePath,
    this.paramsSnapshot,
    this.isFavorite = false,
    this.favoritedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'localPath': localPath,
    'fileName': fileName,
    'fileSize': fileSize,
    'resolution': resolution,
    'prompt': prompt,
    'thumbnailPath': thumbnailPath,
    'type': type.name,
    'nodeName': nodeName,
    'createdAt': createdAt.toIso8601String(),
    'sourceImagePath': sourceImagePath,
    'paramsSnapshot': paramsSnapshot?.toJson(),
    'isFavorite': isFavorite,
    'favoritedAt': favoritedAt?.toIso8601String(),
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: json['id']?.toString() ?? '',
    taskId: json['taskId']?.toString() ?? '',
    localPath: json['localPath']?.toString() ?? '',
    fileName: json['fileName']?.toString() ?? '',
    fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    resolution: json['resolution']?.toString() ?? '',
    prompt: json['prompt']?.toString() ?? '',
    thumbnailPath: json['thumbnailPath']?.toString(),
    type: VideoTaskType.values.byName(json['type']?.toString() ?? 't2v'),
    nodeName: json['nodeName']?.toString(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    sourceImagePath: json['sourceImagePath']?.toString(),
    paramsSnapshot: json['paramsSnapshot'] is Map<String, dynamic>
        ? VideoGenerateParams.fromJson(json['paramsSnapshot'])
        : json['paramsSnapshot'] is Map
        ? VideoGenerateParams.fromJson(
            Map<String, dynamic>.from(json['paramsSnapshot'] as Map),
          )
        : null,
    isFavorite: json['isFavorite'] == true,
    favoritedAt: DateTime.tryParse(json['favoritedAt']?.toString() ?? ''),
  );

  VideoItem copyWith({
    String? localPath,
    String? fileName,
    int? fileSize,
    String? resolution,
    String? prompt,
    String? thumbnailPath,
    String? nodeName,
    String? sourceImagePath,
    VideoGenerateParams? paramsSnapshot,
    bool? isFavorite,
    DateTime? favoritedAt,
  }) {
    return VideoItem(
      id: id,
      taskId: taskId,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      resolution: resolution ?? this.resolution,
      prompt: prompt ?? this.prompt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      type: type,
      nodeName: nodeName ?? this.nodeName,
      createdAt: createdAt,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      paramsSnapshot: paramsSnapshot ?? this.paramsSnapshot,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAt: favoritedAt ?? this.favoritedAt,
    );
  }
}
