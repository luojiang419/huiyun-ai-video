import 'film_tab.dart';

class FilmProject {
  final String id;
  final String name;
  final String fullScript;
  final String scriptAnalysis;
  final List<FilmTab> tabs;
  final String currentTabId;

  FilmProject({
    required this.id,
    required this.name,
    this.fullScript = '',
    this.scriptAnalysis = '',
    this.tabs = const [],
    required this.currentTabId,
  });

  FilmProject copyWith({
    String? id,
    String? name,
    String? fullScript,
    String? scriptAnalysis,
    List<FilmTab>? tabs,
    String? currentTabId,
  }) {
    return FilmProject(
      id: id ?? this.id,
      name: name ?? this.name,
      fullScript: fullScript ?? this.fullScript,
      scriptAnalysis: scriptAnalysis ?? this.scriptAnalysis,
      tabs: tabs ?? this.tabs,
      currentTabId: currentTabId ?? this.currentTabId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fullScript': fullScript,
      'scriptAnalysis': scriptAnalysis,
      'tabs': tabs.map((t) => t.toJson()).toList(),
      'currentTabId': currentTabId,
    };
  }

  factory FilmProject.fromJson(Map<String, dynamic> json) {
    return FilmProject(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      fullScript: json['fullScript'] ?? '',
      scriptAnalysis: json['scriptAnalysis'] ?? '',
      tabs: (json['tabs'] as List?)?.map((t) => FilmTab.fromJson(t)).toList() ?? [],
      currentTabId: json['currentTabId'] ?? '',
    );
  }
}
