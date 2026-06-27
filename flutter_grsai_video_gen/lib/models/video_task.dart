import 'video_generate_params.dart';

enum VideoTaskType { t2v, i2v }

enum VideoTaskStatus { queued, running, completed, failed, cancelled }

class VideoTask {
  final String id;
  final VideoTaskType type;
  final VideoGenerateParams params;
  final String? imagePath;
  final String? assignedNodeId;
  final String? assignedNodeName;
  final int currentStep;
  final int totalSteps;
  final int? etaSeconds;
  final VideoTaskStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? resultVideoPath;
  final String? videoUrl;
  final int? fileSize;
  final int? seedUsed;
  final String? errorMessage;
  final String? sessionName;
  final String? sessionMessageId;

  const VideoTask({
    required this.id,
    required this.type,
    required this.params,
    required this.createdAt,
    this.imagePath,
    this.assignedNodeId,
    this.assignedNodeName,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.etaSeconds,
    this.status = VideoTaskStatus.queued,
    this.startedAt,
    this.completedAt,
    this.resultVideoPath,
    this.videoUrl,
    this.fileSize,
    this.seedUsed,
    this.errorMessage,
    this.sessionName,
    this.sessionMessageId,
  });

  double get progressPercent =>
      totalSteps > 0 ? (currentStep / totalSteps) * 100 : 0;

  VideoTask copyWith({
    String? imagePath,
    String? assignedNodeId,
    String? assignedNodeName,
    int? currentStep,
    int? totalSteps,
    int? etaSeconds,
    VideoTaskStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? resultVideoPath,
    String? videoUrl,
    int? fileSize,
    int? seedUsed,
    String? errorMessage,
    String? sessionName,
    String? sessionMessageId,
  }) {
    return VideoTask(
      id: id,
      type: type,
      params: params,
      createdAt: createdAt,
      imagePath: imagePath ?? this.imagePath,
      assignedNodeId: assignedNodeId ?? this.assignedNodeId,
      assignedNodeName: assignedNodeName ?? this.assignedNodeName,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      resultVideoPath: resultVideoPath ?? this.resultVideoPath,
      videoUrl: videoUrl ?? this.videoUrl,
      fileSize: fileSize ?? this.fileSize,
      seedUsed: seedUsed ?? this.seedUsed,
      errorMessage: errorMessage ?? this.errorMessage,
      sessionName: sessionName ?? this.sessionName,
      sessionMessageId: sessionMessageId ?? this.sessionMessageId,
    );
  }
}
