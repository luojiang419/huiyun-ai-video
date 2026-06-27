import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/storyboard_service.dart';
import '../models/shot.dart';
import '../providers/generate_provider.dart'; // Import apiServiceProvider

class FilmWorkshopState {
  final bool isGenerating;
  final bool isSplitting;
  final int successCount;
  final int failedCount;
  final Map<int, String> shotStatus;
  final Map<int, String?> shotImages;
  final Map<int, int> shotTimer;
  final List<Shot> shots;
  final String thoughtProcess;

  FilmWorkshopState({
    this.isGenerating = false,
    this.isSplitting = false,
    this.successCount = 0,
    this.failedCount = 0,
    this.shotStatus = const {},
    this.shotImages = const {},
    this.shotTimer = const {},
    this.shots = const [],
    this.thoughtProcess = '',
  });

  FilmWorkshopState copyWith({
    bool? isGenerating,
    bool? isSplitting,
    int? successCount,
    int? failedCount,
    Map<int, String>? shotStatus,
    Map<int, String?>? shotImages,
    Map<int, int>? shotTimer,
    List<Shot>? shots,
    String? thoughtProcess,
  }) {
    return FilmWorkshopState(
      isGenerating: isGenerating ?? this.isGenerating,
      isSplitting: isSplitting ?? this.isSplitting,
      successCount: successCount ?? this.successCount,
      failedCount: failedCount ?? this.failedCount,
      shotStatus: shotStatus ?? this.shotStatus,
      shotImages: shotImages ?? this.shotImages,
      shotTimer: shotTimer ?? this.shotTimer,
      shots: shots ?? this.shots,
      thoughtProcess: thoughtProcess ?? this.thoughtProcess,
    );
  }
}

class FilmWorkshopNotifier extends StateNotifier<FilmWorkshopState> {
  final ApiService _apiService;
  Timer? _timer;
  late final StoryboardService _storyboardService;

  FilmWorkshopNotifier(this._apiService) : super(FilmWorkshopState()) {
    _storyboardService = StoryboardService(_apiService);
  }

  void setShots(List<Shot> shots) {
    state = state.copyWith(shots: shots);
  }

  void updateShot(int index, Shot shot) {
    final newShots = List<Shot>.from(state.shots);
    newShots[index] = shot;
    state = state.copyWith(shots: newShots);
  }

  void removeShot(int index) {
    final newShots = List<Shot>.from(state.shots);
    newShots.removeAt(index);

    final newStatus = Map<int, String>.from(state.shotStatus)..remove(index);
    final newImages = Map<int, String?>.from(state.shotImages)..remove(index);
    final newTimer = Map<int, int>.from(state.shotTimer)..remove(index);

    final adjustedStatus = <int, String>{};
    final adjustedImages = <int, String?>{};
    final adjustedTimer = <int, int>{};

    newStatus.forEach((key, value) {
      if (key > index) adjustedStatus[key - 1] = value;
      else if (key < index) adjustedStatus[key] = value;
    });

    newImages.forEach((key, value) {
      if (key > index) adjustedImages[key - 1] = value;
      else if (key < index) adjustedImages[key] = value;
    });

    newTimer.forEach((key, value) {
      if (key > index) adjustedTimer[key - 1] = value;
      else if (key < index) adjustedTimer[key] = value;
    });

    state = state.copyWith(
      shots: newShots,
      shotStatus: adjustedStatus,
      shotImages: adjustedImages,
      shotTimer: adjustedTimer,
    );
  }

  void addShot(Shot shot) {
    final newShots = List<Shot>.from(state.shots)..add(shot);
    state = state.copyWith(shots: newShots);
  }

  void clearShots() {
    state = FilmWorkshopState();
  }

  void startGeneration(List<int> indices) {
    state = state.copyWith(
      isGenerating: true,
      successCount: 0,
      failedCount: 0,
    );
    
    // Start global timer if not running
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newTimers = Map<int, int>.from(state.shotTimer);
      bool anyRunning = false;
      
      state.shotStatus.forEach((index, status) {
        if (status == '生成中') {
          newTimers[index] = (newTimers[index] ?? 0) + 1;
          anyRunning = true;
        }
      });

      if (anyRunning) {
        state = state.copyWith(shotTimer: newTimers);
      } else {
        timer.cancel();
        _timer = null;
      }
    });
  }

  void updateShotStatus(int index, String status) {
    final newStatus = Map<int, String>.from(state.shotStatus);
    newStatus[index] = status;
    
    final newTimer = Map<int, int>.from(state.shotTimer);
    if (status == '生成中') {
      newTimer[index] = 0;
    }

    state = state.copyWith(
      shotStatus: newStatus,
      shotTimer: newTimer,
    );
  }

  void updateShotImage(int index, String? imagePath) {
    final newImages = Map<int, String?>.from(state.shotImages);
    newImages[index] = imagePath;
    state = state.copyWith(shotImages: newImages);
  }

  void incrementSuccess() {
    state = state.copyWith(successCount: state.successCount + 1);
  }

  void incrementFailed() {
    state = state.copyWith(failedCount: state.failedCount + 1);
  }

  void finishGeneration() {
    state = state.copyWith(isGenerating: false);
    _timer?.cancel();
    _timer = null;
    
    // Stop timers for all shots
    final newTimer = Map<int, int>.from(state.shotTimer);
    newTimer.clear(); // Or remove only completed ones, but finishGeneration implies all done
    state = state.copyWith(shotTimer: newTimer);
  }

  void loadState({
    required List<Shot> shots,
    required Map<int, String> status,
    required Map<int, String?> images,
    required Map<int, int> timer,
  }) {
    state = state.copyWith(
      shots: shots,
      shotStatus: status,
      shotImages: images,
      shotTimer: timer,
      successCount: status.values.where((s) => s == '已完成').length,
      failedCount: status.values.where((s) => s == '失败').length,
    );
  }

  Future<void> splitScript({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String script,
    required String aspectRatio,
    required String fullScript,
    String scriptAnalysis = '',
    required Function(String) onSuccess,
    required Function(String) onError,
  }) async {
    state = state.copyWith(isSplitting: true, thoughtProcess: '');

    try {
      final shots = await _storyboardService.splitScript(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        script: script,
        artStyle: '',
        worldView: '',
        aspectRatio: aspectRatio,
        assets: [],
        fullScript: fullScript,
        scriptAnalysis: scriptAnalysis,
        onProgress: (chunk) {
          state = state.copyWith(thoughtProcess: state.thoughtProcess + chunk);
        },
      );

      final statusMap = <int, String>{};
      for (int i = 0; i < shots.length; i++) {
        statusMap[i] = '待生成';
      }

      state = state.copyWith(
        shots: shots,
        shotStatus: statusMap,
        shotImages: {},
        shotTimer: {},
        isSplitting: false,
      );

      onSuccess('拆解完成，共${shots.length}个镜头');
    } catch (e) {
      state = state.copyWith(isSplitting: false);
      onError('拆解失败: $e');
    }
  }
}

final filmWorkshopProvider = StateNotifierProvider<FilmWorkshopNotifier, FilmWorkshopState>((ref) {
  return FilmWorkshopNotifier(ref.watch(apiServiceProvider));
});
