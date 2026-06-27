import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeneratedImage {
  final String path;
  final DateTime timestamp;

  GeneratedImage({required this.path, required this.timestamp});
}

final generatedImagesProvider = StateNotifierProvider<GeneratedImagesNotifier, List<GeneratedImage>>((ref) {
  return GeneratedImagesNotifier();
});

class GeneratedImagesNotifier extends StateNotifier<List<GeneratedImage>> {
  GeneratedImagesNotifier() : super([]);

  void addImage(String path) {
    state = [...state, GeneratedImage(path: path, timestamp: DateTime.now())];
  }

  Future<void> loadImagesFromFolder() async {
    // 这里需要实现从 output 文件夹加载图片的逻辑
    // 由于 Provider 不能直接访问 Service (除非注入)，我们可以在 UI 层调用 Service 后把结果传进来
    // 或者在这里做简单的文件扫描
    // 考虑到依赖注入，这里先不做复杂实现，而是提供一个 setImages 方法供外部调用
  }

  void setImages(List<GeneratedImage> images) {
    state = images;
  }

  void clearImages() {
    state = [];
  }
}
