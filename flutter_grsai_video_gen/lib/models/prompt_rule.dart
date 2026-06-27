class PromptRule {
  final String id;
  final String name;
  final String filePath;
  String content;

  PromptRule({
    required this.id,
    required this.name,
    required this.filePath,
    required this.content,
  });

  PromptRule copyWith({String? content}) {
    return PromptRule(
      id: id,
      name: name,
      filePath: filePath,
      content: content ?? this.content,
    );
  }
}
