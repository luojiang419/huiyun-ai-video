import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局共享的图片生成参数，generate_screen 写入，其他页面读取
class GenerateParams {
  final String model;
  final String aspectRatio;
  final String imageSize;
  final String imageQuality;
  final int sampleSteps;

  const GenerateParams({
    this.model = 'gemini-3-pro-image-preview',
    this.aspectRatio = 'auto',
    this.imageSize = '1K',
    this.imageQuality = 'auto',
    this.sampleSteps = 30,
  });

  Map<String, dynamic> toJson() => {
    'model': model,
    'aspectRatio': aspectRatio,
    'imageSize': imageSize,
    'imageQuality': imageQuality,
    'sampleSteps': sampleSteps,
  };

  GenerateParams copyWith({
    String? model,
    String? aspectRatio,
    String? imageSize,
    String? imageQuality,
    int? sampleSteps,
  }) {
    return GenerateParams(
      model: model ?? this.model,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      imageSize: imageSize ?? this.imageSize,
      imageQuality: imageQuality ?? this.imageQuality,
      sampleSteps: sampleSteps ?? this.sampleSteps,
    );
  }
}

class GenerateParamsNotifier extends StateNotifier<GenerateParams> {
  GenerateParamsNotifier() : super(const GenerateParams());

  void setModel(String model) => state = state.copyWith(model: model);
  void setAspectRatio(String ratio) =>
      state = state.copyWith(aspectRatio: ratio);
  void setImageSize(String size) => state = state.copyWith(imageSize: size);
  void setImageQuality(String quality) =>
      state = state.copyWith(imageQuality: quality);
  void setSampleSteps(int sampleSteps) =>
      state = state.copyWith(sampleSteps: sampleSteps);
  void setAll(
    String model,
    String aspectRatio,
    String imageSize,
    String imageQuality,
    int sampleSteps,
  ) {
    state = GenerateParams(
      model: model,
      aspectRatio: aspectRatio,
      imageSize: imageSize,
      imageQuality: imageQuality,
      sampleSteps: sampleSteps,
    );
  }
}

final generateParamsProvider =
    StateNotifierProvider<GenerateParamsNotifier, GenerateParams>(
      (ref) => GenerateParamsNotifier(),
    );
