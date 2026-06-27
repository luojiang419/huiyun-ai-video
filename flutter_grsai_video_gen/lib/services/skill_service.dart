import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/skill.dart';

final skillServiceProvider = Provider((ref) => SkillService());

class SkillService {
  static const String _skillsDir = 'data/Skills';
  static const String _builtinDir = '$_skillsDir/builtin';
  static const String _userDir = '$_skillsDir/user';
  static const String _indexFile = '$_skillsDir/index.json';

  String _appDir = '';

  String get _exeDir {
    if (_appDir.isEmpty) {
      _appDir = File(Platform.resolvedExecutable).parent.path;
    }
    return _appDir;
  }

  Future<void> initDirectories() async {
    await Directory('$_exeDir/$_skillsDir').create(recursive: true);
    await Directory('$_exeDir/$_builtinDir').create(recursive: true);
    await Directory('$_exeDir/$_userDir').create(recursive: true);
  }

  Future<SkillIndex?> loadIndex() async {
    final file = File('$_exeDir/$_indexFile');
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      return SkillIndex.fromJson(jsonDecode(content));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIndex(SkillIndex index) async {
    final file = File('$_exeDir/$_indexFile');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
    );
  }

  Future<List<Skill>> loadAllSkills() async {
    final skills = <Skill>[];
    skills.addAll(await _loadSkillsFromDir('$_exeDir/$_builtinDir'));
    skills.addAll(await _loadSkillsFromDir('$_exeDir/$_userDir'));
    return skills;
  }

  Future<List<Skill>> loadBuiltinSkills() async {
    return _loadSkillsFromDir('$_exeDir/$_builtinDir');
  }

  Future<List<Skill>> loadUserSkills() async {
    return _loadSkillsFromDir('$_exeDir/$_userDir');
  }

  Future<List<Skill>> _loadSkillsFromDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final skills = <Skill>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          (entity.path.endsWith('.md') || entity.path.endsWith('.json'))) {
        try {
          skills.add(await Skill.fromFile(entity));
        } catch (e) {
          // skip invalid files
        }
      }
    }
    return skills;
  }

  Future<Skill?> loadSkillById(String id) async {
    final allSkills = await loadAllSkills();
    try {
      return allSkills.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Skill>> getSkillsByCategory(String categoryId) async {
    final index = await loadIndex();
    if (index == null) return [];

    final category = index.categories
        .where((c) => c.id == categoryId)
        .toList();
    if (category.isEmpty) return [];

    final allSkills = await loadAllSkills();
    final skillIds = category.first.skillIds.toSet();
    return allSkills.where((s) => skillIds.contains(s.id)).toList();
  }

  Future<List<SkillMatch>> matchSkills(String userInput) async {
    final allSkills = await loadAllSkills();
    final matches = <SkillMatch>[];
    final inputLower = userInput.toLowerCase();

    for (final skill in allSkills) {
      double score = 0.0;

      // tag keyword matching (weight 40%)
      for (final tag in skill.tags) {
        if (inputLower.contains(tag.toLowerCase())) {
          score += 0.4 / skill.tags.length * 2;
        }
      }

      // category matching (weight 20%)
      if (inputLower.contains(skill.category.toLowerCase())) {
        score += 0.2;
      }

      // skill name matching (weight 15%)
      if (inputLower.contains(skill.name.toLowerCase()) ||
          skill.name.toLowerCase().contains(inputLower)) {
        score += 0.15;
      }

      // description matching (weight 10%)
      if (skill.description.toLowerCase().contains(inputLower)) {
        score += 0.1;
      }

      // usage frequency (weight 10%)
      if (skill.usageCount > 0) {
        score += 0.1 * (skill.usageCount / 10).clamp(0.0, 1.0);
      }

      // user skill bonus (weight 5%)
      if (skill.source == 'user') {
        score += 0.05;
      }

      if (score > 0.2) {
        matches.add(SkillMatch(
          skill: skill,
          relevanceScore: score.clamp(0.0, 1.0),
          matchedReason: _buildMatchReason(skill, inputLower),
        ));
      }
    }

    matches.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return matches.take(3).toList();
  }

  String _buildMatchReason(Skill skill, String input) {
    final matchedTags =
        skill.tags.where((t) => input.contains(t.toLowerCase())).toList();
    if (matchedTags.isNotEmpty) {
      return '匹配标签：${matchedTags.join('、')}';
    }
    if (input.contains(skill.category.toLowerCase())) {
      return '匹配分类：${skill.category}';
    }
    return '相关技能';
  }

  Future<Skill> saveUserSkill(Skill skill) async {
    final dir = Directory('$_exeDir/$_userDir');
    await dir.create(recursive: true);

    final filename = '${skill.id}.md';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(skill.toMarkdown());

    await _updateIndexWithSkill(skill);
    return skill;
  }

  Future<void> _updateIndexWithSkill(Skill skill) async {
    final index = await loadIndex();
    if (index == null) return;

    // add to tags index
    final newTags = Map<String, List<String>>.from(index.tags);
    for (final tag in skill.tags) {
      if (!newTags.containsKey(tag)) {
        newTags[tag] = [];
      }
      if (!newTags[tag]!.contains(skill.id)) {
        newTags[tag]!.add(skill.id);
      }
    }

    // check if category exists
    final existingCat = index.categories
        .where((c) => c.name == skill.category)
        .toList();

    if (existingCat.isEmpty && skill.category.isNotEmpty) {
      // auto-create category for user skills
    }

    await saveIndex(SkillIndex(
      version: index.version,
      lastUpdated: DateTime.now().toIso8601String().substring(0, 10),
      categories: index.categories,
      tags: newTags,
    ));
  }

  Future<void> incrementUsageCount(String skillId) async {
    final userDir = Directory('$_exeDir/$_userDir');
    final builtinDir = Directory('$_exeDir/$_builtinDir');

    for (final dir in [userDir, builtinDir]) {
      for (final ext in ['.md', '.json']) {
        final file = File('${dir.path}/$skillId$ext');
        if (await file.exists()) {
          try {
            final skill = await Skill.fromFile(file);
            final updated = skill.copyWith(usageCount: skill.usageCount + 1);
            final newFile = File('${dir.path}/${skill.id}.md');
            await newFile.writeAsString(updated.toMarkdown());
            // remove old .json if exists
            if (ext == '.json') await file.delete();
          } catch (_) {}
          return;
        }
      }
    }
  }

  Future<void> deleteUserSkill(String skillId) async {
    for (final ext in ['.md', '.json']) {
      final file = File('$_exeDir/$_userDir/$skillId$ext');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> ensureBuiltinSkillsExist() async {
    final builtinDir = Directory('$_exeDir/$_builtinDir');
    await builtinDir.create(recursive: true);

    final existing = await _loadSkillsFromDir(builtinDir.path);
    final existingIds = existing.map((s) => s.id).toSet();

    final builtins = _getAllBuiltinSkills();
    for (final skill in builtins) {
      if (!existingIds.contains(skill.id)) {
        final file = File('${builtinDir.path}/${skill.id}.md');
        await file.writeAsString(skill.toMarkdown());
      }
    }

    // ensure index exists
    final indexFile = File('$_exeDir/$_indexFile');
    if (!await indexFile.exists()) {
      await saveIndex(_buildDefaultIndex());
    }
  }

  List<Skill> _getAllBuiltinSkills() {
    return [
      _cinematicFrames(),
      _portraitLighting(),
      _landscapeAtmosphere(),
      _productCommercial(),
      _conceptArt(),
      _scifiScene(),
      _periodDrama(),
      _actionSequence(),
      _foodPhotography(),
      _architecture(),
      _fashionEditorial(),
      _horrorAtmosphere(),
      _warScene(),
      _fantasyWorld(),
      _animalNature(),
      _abstractArt(),
    ];
  }

  SkillIndex _buildDefaultIndex() {
    return SkillIndex(
      lastUpdated: DateTime.now().toIso8601String().substring(0, 10),
      categories: [
        SkillCategory(id: 'film_tv', name: '影视制作', icon: '🎬', skillIds: [
          'builtin_cinematic_frames',
          'builtin_action_sequence',
        ]),
        SkillCategory(id: 'portrait', name: '人物肖像', icon: '👤', skillIds: [
          'builtin_portrait_lighting',
        ]),
        SkillCategory(
            id: 'scene_concept', name: '场景概念', icon: '🏙️', skillIds: [
          'builtin_scifi_scene',
          'builtin_period_drama',
          'builtin_fantasy_world',
        ]),
        SkillCategory(
            id: 'commercial', name: '商业摄影', icon: '📷', skillIds: [
          'builtin_product_commercial',
          'builtin_food_photography',
          'builtin_fashion_editorial',
        ]),
        SkillCategory(id: 'nature', name: '自然风光', icon: '🏔️', skillIds: [
          'builtin_landscape_atmosphere',
          'builtin_animal_nature',
        ]),
        SkillCategory(id: 'artistic', name: '艺术风格', icon: '🎨', skillIds: [
          'builtin_concept_art',
          'builtin_abstract_art',
        ]),
        SkillCategory(id: 'special', name: '特殊场景', icon: '⚡', skillIds: [
          'builtin_horror_atmosphere',
          'builtin_war_scene',
          'builtin_architecture',
        ]),
      ],
      tags: {
        '电影': ['builtin_cinematic_frames', 'builtin_action_sequence'],
        '构图': ['builtin_cinematic_frames', 'builtin_architecture'],
        '人物': ['builtin_portrait_lighting', 'builtin_fashion_editorial'],
        '科幻': ['builtin_scifi_scene'],
        '商业': ['builtin_product_commercial', 'builtin_fashion_editorial'],
        '自然': ['builtin_landscape_atmosphere', 'builtin_animal_nature'],
        '美食': ['builtin_food_photography'],
        '建筑': ['builtin_architecture'],
        '恐怖': ['builtin_horror_atmosphere'],
        '战争': ['builtin_war_scene'],
        '奇幻': ['builtin_fantasy_world'],
        '概念': ['builtin_concept_art', 'builtin_abstract_art'],
        '古装': ['builtin_period_drama'],
        '动作': ['builtin_action_sequence'],
        '时尚': ['builtin_fashion_editorial'],
        '动物': ['builtin_animal_nature'],
      },
    );
  }

  // ─── Built-in skill factory methods ───

  Skill _cinematicFrames() => Skill(
        id: 'builtin_cinematic_frames',
        name: '影视画面构图',
        icon: '🎬',
        category: '影视制作',
        tags: ['电影', '构图', '景别', '镜头语言', '分镜', '影视', '画面'],
        description: '专业影视画面构图技能，涵盖经典构图法则、景别体系和镜头运动描述',
        source: 'builtin',
        createdAt: '2026-04-23',
        promptTemplates: [
          PromptTemplate(
            name: '电影感远景',
            template:
                '{主体描述}，宽银幕电影画面，远景景别，三分法构图，{环境氛围}，{光影描述}，电影级调色，浅景深，{风格描述}',
            aspectRatio: '21:9',
            imageSize: '2K',
          ),
          PromptTemplate(
            name: '对话场景',
            template:
                '{角色描述}，中景景别，过肩镜头构图，{环境描述}，自然光从侧面照射，{氛围描述}，电影感色彩分级，{风格描述}',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
          PromptTemplate(
            name: '情绪特写',
            template:
                '{角色描述}面部特写，浅景深虚化背景，{表情描述}，{光影描述}突出面部轮廓和眼神光，{色调描述}，电影级皮肤质感，{风格描述}',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
        ],
        knowledgeBase:
            '一、经典构图法则\n- 三分法构图：将画面用两条水平线和两条垂直线均分为九宫格，主体放置在交叉点上\n- 黄金螺旋构图：基于斐波那契数列的螺旋线构图，视觉焦点沿螺旋线分布\n- 对称构图：画面左右或上下严格对称，营造庄严仪式感\n- 对角线构图：主体沿对角线方向排列，制造动感和张力\n- 框架构图：利用前景元素（门窗、树枝）形成画框，增加层次和深度感\n\n'
            '二、景别体系\n- 大远景（Extreme Long Shot）：交代环境全貌\n- 远景（Long Shot）：展示人物全身和环境关系\n- 全景（Full Shot）：人物全身入画\n- 中景（Medium Shot）：腰部以上，对话场景常用\n- 近景（Medium Close-up）：胸部以上\n- 特写（Close-up）：面部或物体细节，强调情绪\n- 大特写（Extreme Close-up）：局部细节\n\n'
            '三、镜头运动描述词\n- 缓慢推进（Slow Push In）：逐渐靠近主体，制造紧张感\n- 拉远（Pull Back）：逐渐远离，展示环境全貌\n- 横摇（Pan）：镜头水平转动\n- 环绕（Orbit）：镜头围绕主体旋转\n- 跟随（Tracking）：镜头跟随移动的主体',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
          'batchCount': 1,
        },
        polishRules: [
          '始终使用专业影视术语描述画面',
          '景别优先考虑：远景→全景→中景→近景→特写',
          '光影描述必须包含光源方向和色温',
          '画面层次：前景-中景-背景必须有明确区分',
        ],
        examples: [
          SkillExample(
            input: '一个人站在海边',
            output:
                '一位身着白色长裙的女性背对镜头站立在日落时分的海岸线上，采用宽银幕全景构图，人物位于画面左侧三分之一处，金色夕阳从画面右侧低角度照射，在海面铺下一条闪烁的金色光路，前景的浪花轻柔地漫过脚踝，中景是波光粼粼的大海，远景天际线处云层被染成橙红与紫蓝的渐变色，整体画面呈现出宁静而壮阔的电影感氛围',
          ),
        ],
      );

  Skill _portraitLighting() => Skill(
        id: 'builtin_portrait_lighting',
        name: '人物肖像布光',
        icon: '👤',
        category: '人物肖像',
        tags: ['人物', '肖像', '布光', '人像', '肖像画', '头像'],
        description: '专业人像布光技能，涵盖经典布光模式、光源类型和肤色质感表现',
        source: 'builtin',
        createdAt: '2026-04-23',
        promptTemplates: [
          PromptTemplate(
            name: '经典肖像',
            template:
                '一位{人物描述}，{姿势描述}，{布光模式}，{光源描述}，背景{背景描述}，{色调描述}，专业人像摄影，{风格描述}',
            aspectRatio: '4:3',
            imageSize: '2K',
          ),
          PromptTemplate(
            name: '情绪人像',
            template:
                '一位{人物描述}，{表情描述}，{布光模式}，{光源描述}，浅景深虚化背景为{背景色调}色调，情绪化的{色调描述}调色，{风格描述}',
            aspectRatio: '3:4',
            imageSize: '2K',
          ),
        ],
        knowledgeBase:
            '一、经典布光模式\n- 蝴蝶光（Butterfly Lighting）：光源在人物正上方略前，鼻子下方形成蝴蝶形阴影\n- 伦勃朗光（Rembrandt Lighting）：光源45度侧上方照射，面部暗侧形成倒三角光斑\n- 环形光（Loop Lighting）：光源30度侧上方照射，最通用的人像布光\n- 分割光（Split Lighting）：光源从正侧面90度照射，面部一半亮一半暗\n- 边缘光（Rim Lighting）：光源在人物正后方，勾勒轮廓边缘\n\n'
            '二、光源类型描述词\n- 自然窗光（Window Light）：柔和的方向性光线\n- 黄金时刻（Golden Hour）：日出日落前后的暖色光，色温约3000-4000K\n- 蓝色时刻（Blue Hour）：日落后的冷色光线，色温约7000-10000K\n- 影棚闪光灯（Studio Strobe）：干净利落的光线\n- 霓虹灯光（Neon Light）：彩色霓虹灯照射\n\n'
            '三、肤色与质感描述词\n- 健康光泽的肤色，细腻自然\n- 精致的妆面质感，哑光底妆\n- 电影级皮肤处理，保留纹理细节\n- 高端时尚杂志质感，无暇肌肤',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '4:3',
          'imageSize': '2K',
          'batchCount': 1,
        },
        polishRules: [
          '人像必须明确布光模式',
          '肤色描述需与整体色调协调',
          '背景必须虚化或简化，突出人物',
          '眼神光是必需要素',
        ],
        examples: [
          SkillExample(
            input: '一个帅气的男人',
            output:
                '一位三十岁左右的亚洲男性，微微侧身面向镜头，伦勃朗布光从左上方45度照射，面部右侧形成经典的倒三角形光斑，深邃的眼神中带有柔和的眼神光，穿着深蓝色高领毛衣，浅景深虚化背景为深灰色调，皮肤质感细腻保留自然纹理，整体呈现高端时尚杂志人像风格',
          ),
        ],
      );

  Skill _landscapeAtmosphere() => Skill(
        id: 'builtin_landscape_atmosphere',
        name: '自然风光氛围',
        icon: '🏔️',
        category: '自然风光',
        tags: ['自然', '风景', '风光', '山水', '日出', '日落', '星空'],
        description: '自然风光氛围营造技能，涵盖时间氛围、天气效果和风光构图技法',
        source: 'builtin',
        createdAt: '2026-04-23',
        promptTemplates: [
          PromptTemplate(
            name: '黄金时刻风光',
            template:
                '{场景描述}，黄金时刻的光线，{主体描述}，前景{前景描述}，{天空描述}，暖金色色调覆盖整个画面，{风格描述}',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
          PromptTemplate(
            name: '星空夜景',
            template:
                '{场景描述}的夜晚，银河横贯天际，{前景描述}形成剪影，满天繁星闪烁，{光影描述}，长曝光效果，{风格描述}',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
        ],
        knowledgeBase:
            '一、时间氛围体系\n- 黎明：天际线泛起鱼肚白，薄雾笼罩山谷，色温暖金\n- 黄金时刻：太阳低悬，万物镀金，暖色调，长投影\n- 蓝色时刻：日落后天际深蓝，冷暖交织\n- 星空：银河横贯天际，前景剪影化，长曝光效果\n\n'
            '二、天气氛围描述词\n- 薄雾：朦胧柔美，景物若隐若现\n- 暴风雨：乌云密布，闪电划空，极具戏剧性\n- 雨后：清新通透，彩虹出现\n- 雪景：银装素裹，宁静纯净\n- 云海：站在高处俯瞰云层翻涌\n\n'
            '三、风光构图技法\n- 前景引导：利用前景元素引导视线\n- 层次递进：前景清晰→中景柔和→远景朦胧\n- 汇聚线：利用道路、河流引向远方焦点\n- 倒影构图：平静水面形成完美镜像',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
          'batchCount': 1,
        },
        polishRules: [
          '风光画面必须有前景、中景、背景三个层次',
          '光影描述必须指明时间时段和光线方向',
          '色彩描述需与天气和时间一致',
        ],
        examples: [
          SkillExample(
            input: '山顶的日出',
            output:
                '黎明时分站在高山之巅俯瞰连绵群山，金色朝阳从东方地平线升起，第一缕阳光穿透薄雾照亮远处的山峰，前景是布满露珠的野花和岩石，中景是层层叠叠的山峦在晨雾中若隐若现，远景是最高的雪峰被朝霞染成玫瑰金色，天空呈现从深蓝到橙红的渐变色，云海在山谷间翻涌流动，整个画面气势磅礴而宁静悠远',
          ),
        ],
      );

  Skill _productCommercial() => Skill(
        id: 'builtin_product_commercial',
        name: '产品商业摄影',
        icon: '📷',
        category: '商业摄影',
        tags: ['产品', '商业', '广告', '商品', '电商', '摄影'],
        description: '产品商业摄影技能，涵盖布光技巧、场景搭建和质感表现',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、产品摄影布光\n- 主光+辅光+轮廓光三灯法\n- 柔光箱+反光板，消除硬阴影\n- 硫酸纸柔化高光，避免表面反射\n\n'
            '二、背景与场景\n- 纯色背景：白底/黑底/灰底\n- 渐变背景：柔和颜色渐变\n- 场景化拍摄：产品融入使用场景\n- 悬浮效果：产品悬浮于空中\n\n'
            '三、质感表现\n- 金属：冷调光线+高对比\n- 玻璃：侧逆光+暗背景\n- 皮革：暖调侧光+近距离\n- 织物：柔和光线+微距\n- 食品：暖色侧光+蒸汽效果',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '1:1',
          'imageSize': '2K',
        },
        promptTemplates: [
          PromptTemplate(
            name: '产品展示',
            template:
                '{产品描述}，{布光描述}，{背景描述}，产品位于画面中心，{材质质感描述}，专业商业摄影，{风格描述}',
            aspectRatio: '1:1',
            imageSize: '2K',
          ),
        ],
        polishRules: [
          '产品必须位于画面视觉中心',
          '背景不能喧宾夺主',
          '必须突出材质质感',
        ],
        examples: [],
      );

  Skill _conceptArt() => Skill(
        id: 'builtin_concept_art',
        name: '概念艺术设计',
        icon: '🎭',
        category: '艺术风格',
        tags: ['概念', '设计', '概念艺术', '游戏', '原画', '设定'],
        description: '概念艺术设计技能，涵盖世界观构建、视觉叙事和多种概念风格',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、概念艺术核心要素\n- 世界观一致性：所有元素统一在同一世界观下\n- 视觉叙事：每一帧画面都应讲述一个故事\n- 氛围优先：先确定情绪基调，再填充细节\n\n'
            '二、概念艺术风格\n- 写实概念：照片级真实感\n- 半写实概念：保留绘画笔触感\n- 手绘概念：明显绘画风格\n- 极简概念：大面积留白\n\n'
            '三、概念设计常用构图\n- 环境全景：展示完整场景全貌\n- 角色展示：展示服装和装备\n- 氛围图：以色块和光影为主的情绪参考',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '必须保持世界观一致性',
          '氛围和色调必须统一',
          '每个元素都必须有叙事功能',
        ],
        examples: [],
      );

  Skill _scifiScene() => Skill(
        id: 'builtin_scifi_scene',
        name: '科幻场景',
        icon: '🌃',
        category: '场景概念',
        tags: ['科幻', '赛博朋克', '未来', '科技', '太空', '机甲'],
        description: '科幻场景创作技能，涵盖科幻建筑、交通、科技元素和色调体系',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、科幻场景核心元素\n- 建筑语言：高耸摩天楼、悬浮建筑、弧形穹顶\n- 交通工具：光轨列车、飞行器、悬浮汽车\n- 科技元素：全息投影、数据流瀑布、能量护盾\n- 材质感：金属拉丝、透明屏幕、发光面板\n- 光效：霓虹灯带、粒子光效、能量脉冲\n\n'
            '二、科幻色调体系\n- 赛博朋克：品红+青蓝+暗紫，高对比霓虹\n- 太空歌剧：深蓝+金色+白色，宏大壮阔\n- 废土末日：土黄+铁锈红+灰色，荒凉破败\n- 科技洁净：纯白+银色+淡蓝，极简未来\n\n'
            '三、科幻氛围描述词\n- 空中穿梭的光轨列车在摩天大楼间划出流光溢彩的弧线\n- 全息广告牌在雨幕中闪烁，倒映在湿漉漉的路面上\n- 巨型能量塔顶端的蓝色脉冲照亮了整个城市的夜空',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [
          PromptTemplate(
            name: '赛博朋克城市',
            template:
                '{城市描述}的赛博朋克城市夜景，{建筑描述}，{光源描述}，雨后湿漉漉的路面倒映着霓虹灯光，{氛围描述}，{风格描述}',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
        ],
        polishRules: [
          '科幻场景必须有明确的光源设定',
          '建筑和科技元素需保持风格统一',
          '霓虹和光效是赛博朋克核心元素',
        ],
        examples: [
          SkillExample(
            input: '赛博朋克街道',
            output:
                '一条狭窄的赛博朋克街道夜景，两侧高耸的摩天大楼表面布满了闪烁的全息广告和霓虹灯牌，品红色和青蓝色的霓虹灯光交织照射在雨后湿漉漉的路面上形成五彩斑斓的倒影，空中穿梭着光轨列车划出流光溢彩的弧线，街道上行人打着发光的透明雨伞匆匆走过，蒸汽从地下通风口升起，整体氛围充满未来科技感与都市孤独感',
          ),
        ],
      );

  Skill _periodDrama() => Skill(
        id: 'builtin_period_drama',
        name: '古装历史场景',
        icon: '🏯',
        category: '场景概念',
        tags: ['古装', '历史', '古风', '宫廷', '武侠', '朝代', '中国风'],
        description: '古装历史场景创作技能，涵盖古建筑、服饰特征和传统色彩',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、朝代建筑特征\n- 唐代：宏大壮丽，飞檐翘角，朱红柱梁\n- 宋代：精巧雅致，白墙灰瓦，园林意境\n- 明清：金碧辉煌，雕梁画栋，宫廷规制\n\n'
            '二、传统色彩体系\n- 宫廷色：朱红、明黄、翠绿、靛蓝\n- 文人色：水墨灰、淡青、米白、赭石\n- 民间色：大红、翠绿、金黄、靛蓝\n\n'
            '三、古风氛围描述词\n- 晨雾中若隐若现的亭台楼阁\n- 月光下的竹林小径，斑驳的光影\n- 烟雨江南的水乡古镇',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '建筑风格必须符合对应朝代特征',
          '色彩使用传统中国色系',
          '氛围需有诗画意境',
        ],
        examples: [],
      );

  Skill _actionSequence() => Skill(
        id: 'builtin_action_sequence',
        name: '动作场面',
        icon: '⚔️',
        category: '影视制作',
        tags: ['动作', '战斗', '追逐', '格斗', '运动', '武打'],
        description: '动作场面创作技能，涵盖动态模糊、冲击感构图和高速运动表现',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、动感表现技法\n- 动态模糊：背景运动模糊，主体相对清晰\n- 速度线：沿运动方向的线条暗示速度\n- 冻结瞬间：高速快门冻结动作高潮\n- 残影效果：多重曝光暗示快速移动\n\n'
            '二、冲击感构图\n- 对角线构图：制造不稳定感和冲击力\n- 低角度仰拍：增强力量感和压迫感\n- 广角畸变：夸张的透视增强冲击\n- 碎片飞溅：环境中碎片飞散增强冲击感',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '必须描述动态而非静态',
          '运动方向必须明确',
          '环境反应需与动作力度匹配',
        ],
        examples: [],
      );

  Skill _foodPhotography() => Skill(
        id: 'builtin_food_photography',
        name: '美食摄影',
        icon: '🍜',
        category: '商业摄影',
        tags: ['美食', '食物', '餐饮', '料理', '甜品', '饮品'],
        description: '美食摄影技能，涵盖食品布光、摆盘构图和食欲色彩',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、美食布光\n- 侧逆光为主，突出食物纹理和光泽\n- 暖色光线增加食欲感\n- 蒸汽效果增加热食的新鲜感\n\n'
            '二、摆盘构图\n- 俯拍（Flat Lay）：展示完整摆盘\n- 45度角：最接近人眼视角，亲切自然\n- 特写：突出食材细节和质感\n\n'
            '三、食欲色彩\n- 暖色调为主，红、橙、黄色激发食欲\n- 新鲜食材的饱和色彩\n- 酱汁的光泽和流动感',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '4:3',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '食物必须看起来新鲜诱人',
          '必须有热气或光泽感',
          '餐具和背景需搭配协调',
        ],
        examples: [],
      );

  Skill _architecture() => Skill(
        id: 'builtin_architecture',
        name: '建筑空间',
        icon: '🏛️',
        category: '特殊场景',
        tags: ['建筑', '空间', '室内', '城市', '天际线', '楼房'],
        description: '建筑空间摄影技能，涵盖建筑透视、对称构图和空间表现',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、建筑摄影技法\n- 透视校正：垂直线条保持平行\n- 对称构图：展示建筑的秩序美\n- 引导线：利用建筑线条引导视线\n- 框架构图：利用门窗形成画中画\n\n'
            '二、最佳拍摄时段\n- 蓝调时刻：天空深蓝与建筑暖灯对比\n- 黄金时刻：建筑镀上温暖的金色\n- 夜景：灯光勾勒建筑轮廓',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '建筑线条必须横平竖直',
          '空间感需通过透视表现',
          '光影需突出建筑结构美',
        ],
        examples: [],
      );

  Skill _fashionEditorial() => Skill(
        id: 'builtin_fashion_editorial',
        name: '时尚杂志',
        icon: '💃',
        category: '商业摄影',
        tags: ['时尚', '杂志', '服装', '时装', '造型', ' runway'],
        description: '时尚杂志摄影技能，涵盖高端布光、杂志排版构图和前卫造型',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、时尚摄影布光\n- 高对比硬光：突出服装剪裁和质感\n- 美人光：柔和均匀的蝴蝶光\n- 彩色凝胶光：创造前卫色彩效果\n\n'
            '二、杂志构图\n- 留白构图：大面积留白突出模特\n- 对角线姿态：增加画面动感\n- 裁切构图：大胆裁切增加时尚感',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '3:4',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '服装是画面的核心',
          '姿态需优雅自信',
          '整体色调需时尚前卫',
        ],
        examples: [],
      );

  Skill _horrorAtmosphere() => Skill(
        id: 'builtin_horror_atmosphere',
        name: '恐怖氛围',
        icon: '🌑',
        category: '特殊场景',
        tags: ['恐怖', '惊悚', '暗黑', '诡异', '鬼怪', '悬疑'],
        description: '恐怖氛围创作技能，涵盖低调布光、阴影构图和心理暗示',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、恐怖氛围布光\n- 低调照明：大量暗部，只有关键区域被照亮\n- 底光：从下方照射，制造不自然的阴影\n- 单点光源：孤立的光源制造孤独感\n\n'
            '二、恐怖构图\n- 大量负空间：空旷的黑暗增加不安感\n- 不完整构图：只展示部分暗示整体\n- 诡异对称：过于完美的对称制造不安',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '暗部面积需占画面60%以上',
          '关键元素需用光线引导',
          '不安感来源于暗示而非直接展示',
        ],
        examples: [],
      );

  Skill _warScene() => Skill(
        id: 'builtin_war_scene',
        name: '战争场面',
        icon: '💥',
        category: '特殊场景',
        tags: ['战争', '军事', '战场', '爆炸', '军队', '坦克'],
        description: '战争场面创作技能，涵盖战场氛围、烟雾爆炸和史诗感构图',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、战争氛围元素\n- 烟雾和灰尘：弥漫在战场上的硝烟\n- 爆炸和火焰：橘红色的爆炸火球\n- 弹痕和碎片：环境破坏的细节\n- 军事装备：坦克、战机、武器\n\n'
            '二、史诗感构图\n- 宽银幕全景：展示战场全貌\n- 低角度仰拍：增强英雄主义感\n- 剪影效果：逆光下的士兵剪影',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '21:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '必须有烟雾或硝烟元素',
          '色调偏向暖色（火焰）或冷色（钢铁）',
          '画面需传达紧张和压迫感',
        ],
        examples: [],
      );

  Skill _fantasyWorld() => Skill(
        id: 'builtin_fantasy_world',
        name: '奇幻世界',
        icon: '🐉',
        category: '场景概念',
        tags: ['奇幻', '魔法', '精灵', '龙', '魔法师', '异世界'],
        description: '奇幻世界创作技能，涵盖奇幻生物、魔法效果和史诗级氛围',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、奇幻核心元素\n- 奇幻生物：龙、精灵、独角兽、凤凰\n- 魔法效果：光芒、粒子、能量波纹、符文\n- 奇幻建筑：悬浮城堡、魔法塔、精灵树屋\n- 奇幻植物：发光的花朵、巨型蘑菇、水晶树\n\n'
            '二、魔法氛围描述词\n- 金色的魔法粒子在空气中飘散\n- 蓝色的能量弧光在指尖跳跃\n- 古老的符文在空中缓缓旋转发光',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '魔法效果必须有光效描述',
          '奇幻元素需与自然环境协调',
          '氛围偏向神秘和壮阔',
        ],
        examples: [],
      );

  Skill _animalNature() => Skill(
        id: 'builtin_animal_nature',
        name: '动物自然',
        icon: '🦁',
        category: '自然风光',
        tags: ['动物', '野生动物', '宠物', '鸟类', '海洋', '生态'],
        description: '动物自然摄影技能，涵盖野生动物拍摄、微距生态和运动抓拍',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、动物摄影技法\n- 眼睛对焦：动物眼睛必须清晰锐利\n- 环境融合：动物与自然环境的和谐关系\n- 行为抓拍：捕捉动物最生动的瞬间\n\n'
            '二、微距生态\n- 极浅景深：背景完全虚化\n- 自然光线：避免使用闪光灯惊扰\n- 细节展现：绒毛、鳞片、翅膀纹理',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '16:9',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '动物眼睛必须有眼神光',
          '需描述动物的动作和姿态',
          '环境需与动物栖息地一致',
        ],
        examples: [],
      );

  Skill _abstractArt() => Skill(
        id: 'builtin_abstract_art',
        name: '抽象艺术',
        icon: '🎨',
        category: '艺术风格',
        tags: ['抽象', '艺术', '流体', '几何', '色彩', '现代艺术'],
        description: '抽象艺术创作技能，涵盖抽象构图、色彩理论和几何构成',
        source: 'builtin',
        createdAt: '2026-04-23',
        knowledgeBase:
            '一、抽象艺术技法\n- 流体艺术：色彩的自由流动和融合\n- 几何构成：规则几何形状的组合\n- 泼洒技法：颜料的随机泼洒\n- 渐变色彩：色彩的平滑过渡\n\n'
            '二、色彩理论\n- 互补色对比：增强视觉冲击\n- 类似色和谐：柔和统一的色调\n- 三色组合：丰富而平衡',
        defaultParams: {
          'model': 'gemini-3-pro-image-preview',
          'aspectRatio': '1:1',
          'imageSize': '2K',
        },
        promptTemplates: [],
        polishRules: [
          '色彩关系必须有理论依据',
          '构图需有视觉重心',
          '避免出现具象物体',
        ],
        examples: [],
      );
}
