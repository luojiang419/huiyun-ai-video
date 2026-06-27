import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/film_project.dart';
import '../models/film_tab.dart';
import '../models/film_scene_asset.dart';
import '../models/shot.dart';

class FilmProjectState {
  final FilmProject? currentProject;
  final bool isGenerating;
  final bool isSplitting;
  final int successCount;
  final int failedCount;
  final String thoughtProcess;

  FilmProjectState({
    this.currentProject,
    this.isGenerating = false,
    this.isSplitting = false,
    this.successCount = 0,
    this.failedCount = 0,
    this.thoughtProcess = '',
  });

  FilmProjectState copyWith({
    FilmProject? currentProject,
    bool? isGenerating,
    bool? isSplitting,
    int? successCount,
    int? failedCount,
    String? thoughtProcess,
  }) {
    return FilmProjectState(
      currentProject: currentProject ?? this.currentProject,
      isGenerating: isGenerating ?? this.isGenerating,
      isSplitting: isSplitting ?? this.isSplitting,
      successCount: successCount ?? this.successCount,
      failedCount: failedCount ?? this.failedCount,
      thoughtProcess: thoughtProcess ?? this.thoughtProcess,
    );
  }

  FilmTab? get currentTab {
    if (currentProject == null) return null;
    return currentProject!.tabs.firstWhere(
      (tab) => tab.id == currentProject!.currentTabId,
      orElse: () => currentProject!.tabs.isNotEmpty
          ? currentProject!.tabs.first
          : FilmTab(id: '', name: ''),
    );
  }
}

class FilmProjectNotifier extends StateNotifier<FilmProjectState> {
  final _uuid = const Uuid();

  FilmProjectNotifier() : super(FilmProjectState());

  void createProject(String name, String storyboardName) {
    final projectId = _uuid.v4();
    final tabId = _uuid.v4();
    final tab = FilmTab(id: tabId, name: '默认标签');
    final project = FilmProject(
      id: projectId,
      name: storyboardName,
      tabs: [tab],
      currentTabId: tabId,
    );
    state = state.copyWith(currentProject: project);
  }

  void loadProject(FilmProject project) {
    state = state.copyWith(currentProject: project);
  }

  void updateFullScript(String script) {
    if (state.currentProject == null) return;
    final updated = state.currentProject!.copyWith(fullScript: script);
    state = state.copyWith(currentProject: updated);
  }

  void updateScriptAnalysis(String analysis) {
    if (state.currentProject == null) return;
    final updated = state.currentProject!.copyWith(scriptAnalysis: analysis);
    state = state.copyWith(currentProject: updated);
  }

  void addTab(String name) {
    if (state.currentProject == null) return;
    final tabId = _uuid.v4();
    final newTab = FilmTab(id: tabId, name: name);
    final tabs = [...state.currentProject!.tabs, newTab];
    final updated = state.currentProject!.copyWith(
      tabs: tabs,
      currentTabId: tabId,
    );
    state = state.copyWith(currentProject: updated);
  }

  void removeTab(String tabId) {
    if (state.currentProject == null) return;
    final tabs = state.currentProject!.tabs
        .where((t) => t.id != tabId)
        .toList();
    if (tabs.isEmpty) return;

    String newCurrentId = state.currentProject!.currentTabId;
    if (newCurrentId == tabId) {
      newCurrentId = tabs.first.id;
    }

    final updated = state.currentProject!.copyWith(
      tabs: tabs,
      currentTabId: newCurrentId,
    );
    state = state.copyWith(currentProject: updated);
  }

  void switchTab(String tabId) {
    if (state.currentProject == null) return;
    final updated = state.currentProject!.copyWith(currentTabId: tabId);
    state = state.copyWith(currentProject: updated);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (state.currentProject == null) return;
    final tabs = List<FilmTab>.from(state.currentProject!.tabs);
    if (oldIndex < newIndex) newIndex--;
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    final updated = state.currentProject!.copyWith(tabs: tabs);
    state = state.copyWith(currentProject: updated);
  }

  void updateTabName(String tabId, String name) {
    if (state.currentProject == null) return;
    final tabs = state.currentProject!.tabs.map((t) {
      if (t.id == tabId) return t.copyWith(name: name);
      return t;
    }).toList();
    final updated = state.currentProject!.copyWith(tabs: tabs);
    state = state.copyWith(currentProject: updated);
  }

  void updateCurrentTabShots(List<Shot> shots) {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(shots: shots);
    _updateTab(updatedTab);
  }

  void updateCurrentTabShotStatus(int index, String status) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newStatus = Map<int, String>.from(state.currentTab!.shotStatus);
    newStatus[index] = status;
    final updatedTab = state.currentTab!.copyWith(shotStatus: newStatus);
    _updateTab(updatedTab);
  }

  void updateCurrentTabShotImage(int index, String? imagePath) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newImages = Map<int, String?>.from(state.currentTab!.shotImages);
    newImages[index] = imagePath;
    final updatedTab = state.currentTab!.copyWith(shotImages: newImages);
    _updateTab(updatedTab);
  }

  void updateCurrentTabReferenceImage(int index, String path) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newImages = List<String>.from(state.currentTab!.referenceImages);
    newImages[index] = path;
    final updatedTab = state.currentTab!.copyWith(referenceImages: newImages);
    _updateTab(updatedTab);
  }

  void updateCurrentTabImageRemark(int index, String remark) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newRemarks = Map<int, String>.from(state.currentTab!.imageRemarks);
    newRemarks[index] = remark;
    final updatedTab = state.currentTab!.copyWith(imageRemarks: newRemarks);
    _updateTab(updatedTab);
  }

  void updateCurrentTabSlotAssetId(int index, String? assetId) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newIds = Map<int, String>.from(state.currentTab!.slotAssetIds);
    if (assetId == null || assetId.isEmpty) {
      newIds.remove(index);
    } else {
      newIds[index] = assetId;
    }
    final updatedTab = state.currentTab!.copyWith(slotAssetIds: newIds);
    _updateTab(updatedTab);
  }

  void updateCurrentTabSceneAssets(List<FilmSceneAsset> sceneAssets) {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(sceneAssets: sceneAssets);
    _updateTab(updatedTab);
  }

  void updateCurrentTabShotTimer(int index, int seconds) {
    if (state.currentProject == null || state.currentTab == null) return;
    final newTimer = Map<int, int>.from(state.currentTab!.shotTimer);
    newTimer[index] = seconds;
    final updatedTab = state.currentTab!.copyWith(shotTimer: newTimer);
    _updateTab(updatedTab);
  }

  void updateCurrentTabSettings({
    String? selectedModel,
    String? selectedAspectRatio,
    String? selectedImageSize,
  }) {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(
      selectedModel: selectedModel,
      selectedAspectRatio: selectedAspectRatio,
      selectedImageSize: selectedImageSize,
    );
    _updateTab(updatedTab);
  }

  void _updateTab(FilmTab updatedTab) {
    if (state.currentProject == null) return;
    final tabs = state.currentProject!.tabs.map((t) {
      if (t.id == updatedTab.id) return updatedTab;
      return t;
    }).toList();
    final updated = state.currentProject!.copyWith(tabs: tabs);
    state = state.copyWith(currentProject: updated);
  }

  void startGeneration() {
    state = state.copyWith(isGenerating: true, successCount: 0, failedCount: 0);
  }

  void finishGeneration() {
    state = state.copyWith(isGenerating: false);
  }

  void incrementSuccess() {
    state = state.copyWith(successCount: state.successCount + 1);
  }

  void incrementFailed() {
    state = state.copyWith(failedCount: state.failedCount + 1);
  }

  void startSplitting() {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(
      isSplitting: true,
      thoughtProcess: '',
    );
    _updateTab(updatedTab);
  }

  void finishSplitting() {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(isSplitting: false);
    _updateTab(updatedTab);
  }

  void updateThoughtProcess(String chunk) {
    if (state.currentProject == null || state.currentTab == null) return;
    final updatedTab = state.currentTab!.copyWith(
      thoughtProcess: state.currentTab!.thoughtProcess + chunk,
    );
    _updateTab(updatedTab);
  }

  void clearProject() {
    state = FilmProjectState();
  }
}

final filmProjectProvider =
    StateNotifierProvider<FilmProjectNotifier, FilmProjectState>((ref) {
      return FilmProjectNotifier();
    });
