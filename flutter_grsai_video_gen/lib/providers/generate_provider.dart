import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider((ref) => ApiService());

final generateProgressProvider = StateProvider<GenerateProgress?>((ref) => null);

final isGeneratingProvider = StateProvider<bool>((ref) => false);

final generateTimerProvider = StateNotifierProvider<GenerateTimerNotifier, int?>((ref) {
  return GenerateTimerNotifier();
});

class GenerateTimerNotifier extends StateNotifier<int?> {
  Timer? _timer;
  DateTime? _startTime;

  GenerateTimerNotifier() : super(null);

  void start() {
    _startTime = DateTime.now();
    state = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        state = DateTime.now().difference(_startTime!).inSeconds;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
