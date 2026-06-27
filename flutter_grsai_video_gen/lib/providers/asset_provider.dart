import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../services/asset_service.dart';

final assetServiceProvider = Provider((ref) => AssetService());

final assetProvider = StateNotifierProvider<AssetNotifier, List<Asset>>((ref) {
  final service = ref.watch(assetServiceProvider);
  return AssetNotifier(service);
});

class AssetNotifier extends StateNotifier<List<Asset>> {
  final AssetService _service;

  AssetNotifier(this._service) : super([]) {
    loadAssets();
  }

  Future<void> loadAssets() async {
    final assets = await _service.loadAssets();
    state = assets;
  }

  Future<void> addAsset(Asset asset) async {
    await _service.addAsset(asset);
    // Reload or update state locally
    state = [...state, asset];
  }

  Future<void> updateAsset(Asset asset) async {
    await _service.updateAsset(asset);
    state = [
      for (final a in state)
        if (a.id == asset.id) asset else a,
    ];
  }

  Future<void> deleteAsset(String id) async {
    await _service.deleteAsset(id);
    state = state.where((a) => a.id != id).toList();
  }
}
