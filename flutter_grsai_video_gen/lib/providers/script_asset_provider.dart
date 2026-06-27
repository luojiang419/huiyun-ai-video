import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset_extraction_model.dart';

final scriptAssetProvider = StateNotifierProvider<ScriptAssetNotifier, List<ScriptAssetExtraction>>((ref) {
  return ScriptAssetNotifier();
});

class ScriptAssetNotifier extends StateNotifier<List<ScriptAssetExtraction>> {
  ScriptAssetNotifier() : super([]);

  void setExtractions(List<ScriptAssetExtraction> extractions) {
    state = extractions;
  }

  void updateAsset(String sceneId, int assetIndex, ExtractedAsset updatedAsset) {
    state = [
      for (final extraction in state)
        if (extraction.sceneId == sceneId)
          ScriptAssetExtraction(
            sceneId: extraction.sceneId,
            sceneLocation: extraction.sceneLocation,
            assets: [
              for (int i = 0; i < extraction.assets.length; i++)
                if (i == assetIndex) updatedAsset else extraction.assets[i],
            ],
          )
        else
          extraction,
    ];
  }

  void clear() {
    state = [];
  }
}
