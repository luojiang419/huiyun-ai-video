import 'dart:convert';
import 'dart:io';

class PromptTemplate {
  final String name;
  final String template;
  final String aspectRatio;
  final String imageSize;

  PromptTemplate({
    required this.name,
    required this.template,
    this.aspectRatio = '16:9',
    this.imageSize = '2K',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'template': template,
        'aspectRatio': aspectRatio,
        'imageSize': imageSize,
      };

  factory PromptTemplate.fromJson(Map<String, dynamic> json) => PromptTemplate(
        name: json['name'] ?? '',
        template: json['template'] ?? '',
        aspectRatio: json['aspectRatio'] ?? '16:9',
        imageSize: json['imageSize'] ?? '2K',
      );
}

class SkillExample {
  final String input;
  final String output;

  SkillExample({required this.input, required this.output});

  Map<String, dynamic> toJson() => {
        'input': input,
        'output': output,
      };

  factory SkillExample.fromJson(Map<String, dynamic> json) => SkillExample(
        input: json['input'] ?? '',
        output: json['output'] ?? '',
      );
}

class LearnedFrom {
  final String? sessionId;
  final String? originalPrompt;
  final String? polishedPrompt;
  final String? finalPrompt;
  final String? model;
  final String? aspectRatio;
  final String? imageSize;
  final List<String> resultImages;
  final int satisfactionScore;
  final List<dynamic> modificationHistory;

  LearnedFrom({
    this.sessionId,
    this.originalPrompt,
    this.polishedPrompt,
    this.finalPrompt,
    this.model,
    this.aspectRatio,
    this.imageSize,
    this.resultImages = const [],
    this.satisfactionScore = 5,
    this.modificationHistory = const [],
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'originalPrompt': originalPrompt,
        'polishedPrompt': polishedPrompt,
        'finalPrompt': finalPrompt,
        'model': model,
        'aspectRatio': aspectRatio,
        'imageSize': imageSize,
        'resultImages': resultImages,
        'satisfactionScore': satisfactionScore,
        'modificationHistory': modificationHistory,
      };

  factory LearnedFrom.fromJson(Map<String, dynamic> json) => LearnedFrom(
        sessionId: json['sessionId'],
        originalPrompt: json['originalPrompt'],
        polishedPrompt: json['polishedPrompt'],
        finalPrompt: json['finalPrompt'],
        model: json['model'],
        aspectRatio: json['aspectRatio'],
        imageSize: json['imageSize'],
        resultImages: json['resultImages'] != null
            ? List<String>.from(json['resultImages'])
            : [],
        satisfactionScore: json['satisfactionScore'] ?? 5,
        modificationHistory: json['modificationHistory'] ?? [],
      );
}

class Skill {
  final String id;
  final String name;
  final String icon;
  final String category;
  final List<String> tags;
  final String description;
  final String source; // 'builtin' or 'user'
  final String? createdAt;
  final LearnedFrom? learnedFrom;
  int usageCount;
  int rating;
  final List<PromptTemplate> promptTemplates;
  final String knowledgeBase;
  final Map<String, dynamic> defaultParams;
  final List<String> polishRules;
  final List<SkillExample> examples;

  Skill({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.tags,
    required this.description,
    required this.source,
    this.createdAt,
    this.learnedFrom,
    this.usageCount = 0,
    this.rating = 5,
    this.promptTemplates = const [],
    this.knowledgeBase = '',
    this.defaultParams = const {},
    this.polishRules = const [],
    this.examples = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'category': category,
        'tags': tags,
        'description': description,
        'source': source,
        'createdAt': createdAt,
        if (learnedFrom != null) 'learnedFrom': learnedFrom!.toJson(),
        'usageCount': usageCount,
        'rating': rating,
        'promptTemplates': promptTemplates.map((t) => t.toJson()).toList(),
        'knowledgeBase': knowledgeBase,
        'defaultParams': defaultParams,
        'polishRules': polishRules,
        'examples': examples.map((e) => e.toJson()).toList(),
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        icon: json['icon'] ?? '📚',
        category: json['category'] ?? '',
        tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
        description: json['description'] ?? '',
        source: json['source'] ?? 'user',
        createdAt: json['createdAt'],
        learnedFrom: json['learnedFrom'] != null
            ? LearnedFrom.fromJson(json['learnedFrom'])
            : null,
        usageCount: json['usageCount'] ?? 0,
        rating: json['rating'] ?? 5,
        promptTemplates: json['promptTemplates'] != null
            ? (json['promptTemplates'] as List)
                .map((t) => PromptTemplate.fromJson(t))
                .toList()
            : [],
        knowledgeBase: json['knowledgeBase'] ?? '',
        defaultParams: json['defaultParams'] ?? {},
        polishRules: json['polishRules'] != null
            ? List<String>.from(json['polishRules'])
            : [],
        examples: json['examples'] != null
            ? (json['examples'] as List)
                .map((e) => SkillExample.fromJson(e))
                .toList()
            : [],
      );

  String toJsonString() => jsonEncode(toJson());

  static Skill fromJsonString(String str) =>
      Skill.fromJson(jsonDecode(str));

  static Future<Skill> fromFile(File file) async {
    final content = await file.readAsString();
    if (file.path.endsWith('.md')) {
      return Skill.fromMarkdown(content);
    }
    return Skill.fromJson(jsonDecode(content));
  }

  /// Convert to .md format with YAML frontmatter
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('id: $id');
    buf.writeln('name: $name');
    buf.writeln('icon: $icon');
    buf.writeln('category: $category');
    buf.writeln('tags: [${tags.join(', ')}]');
    buf.writeln('description: $description');
    buf.writeln('source: $source');
    if (createdAt != null) buf.writeln('createdAt: $createdAt');
    buf.writeln('usageCount: $usageCount');
    buf.writeln('rating: $rating');
    buf.writeln('defaultParams: ${jsonEncode(defaultParams)}');
    if (promptTemplates.isNotEmpty) {
      buf.writeln('promptTemplates:');
      for (final t in promptTemplates) {
        buf.writeln('  - name: ${t.name}');
        buf.writeln('    template: "${t.template.replaceAll('"', '\\"')}"');
        buf.writeln('    aspectRatio: ${t.aspectRatio}');
        buf.writeln('    imageSize: ${t.imageSize}');
      }
    }
    if (polishRules.isNotEmpty) {
      buf.writeln('polishRules:');
      for (final r in polishRules) {
        buf.writeln('  - "$r"');
      }
    }
    if (learnedFrom != null) {
      buf.writeln('learnedFrom: ${jsonEncode(learnedFrom!.toJson())}');
    }
    if (examples.isNotEmpty) {
      buf.writeln('examples:');
      for (final e in examples) {
        buf.writeln('  - input: "${e.input.replaceAll('"', '\\"')}"');
        buf.writeln('    output: "${e.output.replaceAll('"', '\\"')}"');
      }
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# $icon $name');
    buf.writeln();
    buf.writeln(knowledgeBase);
    return buf.toString();
  }

  /// Parse from .md format with YAML frontmatter
  static Skill fromMarkdown(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('---')) {
      // fallback: try JSON
      return Skill.fromJson(jsonDecode(trimmed));
    }

    final secondDash = trimmed.indexOf('---', 3);
    if (secondDash < 0) {
      return Skill.fromJson(jsonDecode(trimmed));
    }

    final frontmatter = trimmed.substring(3, secondDash).trim();
    final body = trimmed.substring(secondDash + 3).trim();

    final data = <String, dynamic>{};

    // simple YAML parser for flat key-value pairs
    final lines = frontmatter.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final colonPos = line.indexOf(':');
      if (colonPos < 0) {
        i++;
        continue;
      }
      final key = line.substring(0, colonPos).trim();
      var value = line.substring(colonPos + 1).trim();

      // parse array values: [tag1, tag2]
      if (value.startsWith('[') && value.endsWith(']')) {
        final inner = value.substring(1, value.length - 1);
        data[key] = inner
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        i++;
        continue;
      }

      // parse list values (indented with - )
      if (value.isEmpty && i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('- ')) {
        final list = <dynamic>[];
        final indent = lines[i + 1].length - lines[i + 1].trimLeft().length;
        i++;
        while (i < lines.length) {
          final l = lines[i];
          if (l.trimLeft().startsWith('- ') && (l.length - l.trimLeft().length) >= indent) {
            list.add(_parseYamlListItem(l.trimLeft().substring(2)));
            i++;
          } else if (l.trimLeft().startsWith('  ') && (l.length - l.trimLeft().length) > indent) {
            // continuation of list item (e.g. promptTemplates sub-fields)
            i++;
          } else {
            break;
          }
        }
        data[key] = list;
        continue;
      }

      // try JSON decode for complex values
      if (value.startsWith('{') || value.startsWith('[')) {
        try {
          data[key] = jsonDecode(value);
        } catch (_) {
          data[key] = value;
        }
      } else if (value.startsWith('"') && value.endsWith('"')) {
        data[key] = value.substring(1, value.length - 1);
      } else {
        data[key] = value;
      }
      i++;
    }

    // body is the knowledgeBase
    data['knowledgeBase'] = body;

    return Skill.fromJson(data);
  }

  static dynamic _parseYamlListItem(String item) {
    if (item.contains(': ')) {
      final parts = item.split(': ');
      return {parts[0].trim(): parts[1].trim()};
    }
    if (item.startsWith('"') && item.endsWith('"')) {
      return item.substring(1, item.length - 1);
    }
    return item;
  }

  Skill copyWith({
    String? id,
    String? name,
    String? icon,
    String? category,
    List<String>? tags,
    String? description,
    String? source,
    String? createdAt,
    LearnedFrom? learnedFrom,
    int? usageCount,
    int? rating,
    List<PromptTemplate>? promptTemplates,
    String? knowledgeBase,
    Map<String, dynamic>? defaultParams,
    List<String>? polishRules,
    List<SkillExample>? examples,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      learnedFrom: learnedFrom ?? this.learnedFrom,
      usageCount: usageCount ?? this.usageCount,
      rating: rating ?? this.rating,
      promptTemplates: promptTemplates ?? this.promptTemplates,
      knowledgeBase: knowledgeBase ?? this.knowledgeBase,
      defaultParams: defaultParams ?? this.defaultParams,
      polishRules: polishRules ?? this.polishRules,
      examples: examples ?? this.examples,
    );
  }
}

class SkillCategory {
  final String id;
  final String name;
  final String icon;
  final List<String> skillIds;

  SkillCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.skillIds,
  });

  factory SkillCategory.fromJson(Map<String, dynamic> json) => SkillCategory(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        icon: json['icon'] ?? '📚',
        skillIds: json['skillIds'] != null
            ? List<String>.from(json['skillIds'])
            : [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'skillIds': skillIds,
      };
}

class SkillIndex {
  final String version;
  final String lastUpdated;
  final List<SkillCategory> categories;
  final Map<String, List<String>> tags;

  SkillIndex({
    this.version = '1.0',
    required this.lastUpdated,
    required this.categories,
    this.tags = const {},
  });

  factory SkillIndex.fromJson(Map<String, dynamic> json) => SkillIndex(
        version: json['version'] ?? '1.0',
        lastUpdated: json['lastUpdated'] ?? '',
        categories: json['categories'] != null
            ? (json['categories'] as List)
                .map((c) => SkillCategory.fromJson(c))
                .toList()
            : [],
        tags: json['tags'] != null
            ? Map<String, List<String>>.from(
                (json['tags'] as Map).map(
                  (k, v) => MapEntry(k.toString(), List<String>.from(v)),
                ),
              )
            : {},
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastUpdated': lastUpdated,
        'categories': categories.map((c) => c.toJson()).toList(),
        'tags': tags,
      };
}

class SkillMatch {
  final Skill skill;
  final double relevanceScore;
  final String matchedReason;

  SkillMatch({
    required this.skill,
    required this.relevanceScore,
    required this.matchedReason,
  });
}
