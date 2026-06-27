import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/config_file_service.dart';
import '../services/file_service.dart';

final configFileServiceProvider = Provider<ConfigFileService>((ref) {
  return ConfigFileService();
});

final fileServiceProvider = Provider<FileService>((ref) {
  return FileService();
});
