import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/compute_node.dart';
import '../services/config_file_service.dart';
import '../services/video_api_service.dart';
import 'core_services_provider.dart';

final videoNodesProvider =
    StateNotifierProvider<VideoNodeNotifier, List<ComputeNode>>((ref) {
      return VideoNodeNotifier(ref.read(configFileServiceProvider));
    });

class VideoNodeNotifier extends StateNotifier<List<ComputeNode>> {
  final ConfigFileService _configService;

  VideoNodeNotifier(this._configService) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _configService.loadVideoNodes();
  }

  Future<void> reload() async => _load();

  Future<void> addNode(ComputeNode node) async {
    state = [...state, node];
    await _configService.saveVideoNodes(state);
  }

  Future<void> createNode({
    required String name,
    required String publicUrl,
    String? remark,
  }) async {
    await addNode(
      ComputeNode(
        id: const Uuid().v4(),
        name: name,
        publicUrl: _normalizeBaseUrl(publicUrl),
        remark: remark,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateNode(ComputeNode node) async {
    state = [
      for (final item in state)
        if (item.id == node.id) node else item,
    ];
    await _configService.saveVideoNodes(state);
  }

  Future<void> deleteNode(String id) async {
    state = state.where((node) => node.id != id).toList();
    await _configService.saveVideoNodes(state);
  }

  Future<void> setDefault(String id) async {
    state = [for (final node in state) node.copyWith(isDefault: node.id == id)];
    await _configService.saveVideoNodes(state);
  }

  Future<ComputeNode> testConnection(ComputeNode node) async {
    final service = VideoApiService(baseUrl: node.effectiveApiUrl);
    final online = await service.healthCheck();
    ComputeNode updated = node.copyWith(isOnline: online);
    if (online) {
      try {
        final info = await service.getServerInfo();
        updated = updated.copyWith(
          isGenerating: info.isGenerating,
          queueLength: info.queueLength,
          gpuName: info.gpuName.isEmpty ? null : info.gpuName,
          latency: info.latency,
        );
      } catch (_) {
        // ignore
      }
    }
    await updateNode(updated);
    return updated;
  }

  Future<void> refreshStatuses() async {
    final updated = <ComputeNode>[];
    for (final node in state) {
      try {
        final service = VideoApiService(baseUrl: node.effectiveApiUrl);
        final online = await service.healthCheck();
        if (!online) {
          updated.add(
            node.copyWith(
              isOnline: false,
              isGenerating: false,
              queueLength: 0,
              latency: null,
              gpuName: null,
            ),
          );
          continue;
        }
        final info = await service.getServerInfo();
        updated.add(
          node.copyWith(
            isOnline: true,
            isGenerating: info.isGenerating,
            queueLength: info.queueLength,
            latency: info.latency,
            gpuName: info.gpuName.isEmpty ? null : info.gpuName,
          ),
        );
      } catch (_) {
        updated.add(
          node.copyWith(
            isOnline: false,
            isGenerating: false,
            queueLength: 0,
            latency: null,
            gpuName: null,
          ),
        );
      }
    }
    state = updated;
    await _configService.saveVideoNodes(state);
  }

  String _normalizeBaseUrl(String input) {
    var value = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'http://$value';
  }
}
