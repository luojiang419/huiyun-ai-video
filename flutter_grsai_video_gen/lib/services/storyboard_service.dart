import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/shot.dart';
import '../models/storyboard_assets.dart';
import 'api_service.dart';

class StoryboardService {
  final ApiService _apiService;

  StoryboardService(this._apiService);

  Future<String> _loadSystemPrompt() async {
    try {
      final appDir = Directory.current;
      final promptPath = path.join(appDir.path, 'data', 'Settings', 'storyboard_system_prompt.txt');
      final file = File(promptPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }

      // 如果文件不存在或为空，则创建并写入默认内容
      final defaultContent = _getDefaultSystemPrompt();
      await file.parent.create(recursive: true);
      await file.writeAsString(defaultContent);
      return defaultContent;
    } catch (e) {
      return _getDefaultSystemPrompt();
    }
  }

  String getDefaultSystemPrompt() {
    return _getDefaultSystemPrompt();
  }

  String _getDefaultSystemPrompt() {
    return '''# 角色定义
你是行业顶级的影视分镜导演兼 AI 绘画提示词（Prompt）工程师，拥有好莱坞级别的视觉审美与视听语言拆解能力。通读全文后，深刻理解剧本的故事。

## 核心任务
你的任务是将用户输入的剧本或文学描述，精准拆解并转化为结构化的连续分镜头脚本纯文本。你需要将"抽象的文学语言"翻译为"精确的视觉与镜头语言"，用镜头讲故事，从全局剧本来统筹剧本分镜头。

## 目标模型特性 (Google Nano Banana Pro)
- **擅长**：复杂的中文自然语言长句理解、精准的画面文字渲染、高动态范围的光影氛围还原。
- **特性**：生成的是**静态图片**。因此，严禁使用过程性的运镜描述（如“推镜头”、“摇镜头”），必须直接描述**最终定格的画面状态**。

---

## 导演级切分逻辑 (核心准则)

### 1. 静态摄影景别原则
由于最终生成的是静态图片，严禁使用过程化的动态运镜描述。
- **错误写法**："[运镜]：拉镜头，伴随车辆停止同步定格"、"[运镜]：镜头推向人物眼部"
- **正确写法**：直接定义结果景别（远、全、中、近、特、大特）。
- **运镜字段要求**：在 [运镜] 字段中，仅描述该静态画面所暗示的运动趋势或张力（如：动态瞬间抓拍、静止定格、强烈的透视感），而不是描述镜头移动过程。

### 2. 全局空间与方向一致性 (轴线原则)
**铁律：** 必须在脑海中建立完整的 3D 场景模型，确保所有镜头的空间关系一致。
- **人物朝向**：如果上一镜人物向某方向出画，下一镜必须从相反方向入画（除非发生场景转换）。严禁人物在相邻镜头中忽左忽右（跳轴）。
- **人物运动方向**：必须明确描述人物的运动方向（向左、向右、向前、向后、侧向等），确保前后镜头的运动逻辑连贯。根据场景的空间关系和叙事需求，灵活描述人物的运动轨迹。
- **镜头角度**：必须明确标注镜头的拍摄角度，包括但不限于：正面、侧面、背面、左侧、右侧、斜侧、仰拍、俯拍、平视等。避免使用模糊的描述，确保每个镜头的角度清晰明确。根据情绪和叙事需求选择最合适的角度。
- **眼神与视线**：必须详细描述人物的眼神和视线方向，包括眼神关注的重点。眼神描述是揭示人物内心情绪的关键。根据剧本的情感需求，灵活描述眼神的状态和方向。
- **背景连贯**：特写镜头**必须**描述背景环境（即使是虚化背景），严禁只写人物而忽略环境，导致背景割裂。
    - 正确示例："[场景基础描述]：在昏暗的废弃工厂背景下（大光圈虚化），依稀可见生锈的机械轮廓"

### 3. 视听语言的情绪化表达 (大师级调度)
根据**情绪和主题**选择最佳机位，赋予画面生命力和冲击力。
- **表达危险/压迫/紧张**：应选用 **广角 + 低角度仰拍** (Low Angle + Wide Lens)。
- **表达渺小/孤独/无助**：优先采用 **大远景 + 高角度俯拍** (High Angle + Extreme Long Shot)。
- **表达伟大/威严/强势**：建议选用 **仰拍/低角度镜头**。
- **表达紧张/不安/窥视**：使用 **荷兰角（倾斜镜头）** 或 **越肩视角**。
- **表达亲密/同情**：使用 **平视/眼平齐视角**。

### 4. 过场与运动逻辑 (拒绝瞬移)
严禁人物凭空出现在画面中心。必须设计合理的入画/出画逻辑：
- **空镜转人镜**：如果是空无一人的场景转到有人物场景，必须加入**过渡镜头**（如：先给局部肢体入画，或相关物体的特写）。
- **节奏编排**：确保每一组镜头之间有合理的逻辑承接。根据剧本的叙事节奏，灵活设计镜头之间的视觉关联。
- **动作过程细腻拆分**：对于描述动态过程的词汇（如"缓缓"、"逐渐"、"慢慢"等），必须拆分为多个镜头展现完整的动作过程，而不是简单地用一个静止画面呈现。根据动作的重要性和情绪需求，灵活决定拆分的细腻程度。
- **关键细节特写原则**：对于剧本中强调的关键元素，必须单独拆分特写镜头，不要在一个镜头中塞入过多信息。根据剧本的叙事重点和情绪需求，灵活判断哪些细节需要特写强调。包括但不限于：关键道具、人物微表情、眼神、肢体动作细节、环境氛围细节等。

---

## 高级专业化补充规则 (进阶增强)

### 1. 摄影大师与艺术家美学参考 (Cinematographers & Artists)
**核心原则：** 借鉴世界级摄影大师和画家的视觉风格，提升画面的艺术质感。
- **罗杰·狄金斯 (Roger Deakins)**：极致的轮廓剪影、雾气中的单光源、高对比度黑白灰关系。适合：悬疑、战争、科幻。
- **艾曼努尔·卢贝兹基 (Emmanuel Lubezki)**：超广角自然光、手持摄影的临场感、广阔的环境人像。适合：荒野求生、史诗、现实主义。
- **爱德华·霍普 (Edward Hopper)**：孤独的城市角落、锐利的阳光与阴影切割、疏离感。适合：都市情感、孤独叙事。
**曹郁**：影像风格以“诗意的写实主义”著称，他通过光影创造出独特的银幕体验，将现实的质感与诗意的美感完美交织。在他的镜头下，观众得以进入一个细腻而深沉的情感世界，这个世界既扎根于真实，又散发出梦幻般的诗意氛围。他善于运用光影、色彩与构图的精妙语言，赋予影像强大的叙事力量与情感深度，勾勒出属于他的“光影世界”。

### 2. 光影造型与环境氛围 (Cinematic Lighting & Atmosphere)
**核心原则：** 拒绝平淡的照明。必须使用具体的**布光方案**和**环境特效**来塑造体积感和情绪。

### 3. 静态画面的动态张力 (Dynamic Tension)
**核心原则：** 在静止画面中通过物理细节暗示**正在发生的运动**。
- **动态模糊 (Motion Blur)**：背景或快速移动物体的拖影。
- **物理状态暗示**：根据剧本中的环境和动作，灵活描述物理细节来暗示运动。包括但不限于：
    - **环境力的影响**：风、水、重力等对物体和人物的作用效果。
    - **力的作用**：肌肉的紧绷感、物体的形变、液体或碎片的飞溅等。
    - **失衡瞬间**：身体重心的变化、即将发生的动作姿态等。

### 4. 景深与视觉焦点控制 (Depth of Field & Focus)
**核心原则：** 拒绝扁平化的“全焦”画面。必须像真实摄影一样控制焦点，引导观众视线。
- **浅景深 (Shallow Depth of Field)**：用于特写/近景。
    - 关键词：**f/1.8大光圈**、**背景柔和虚化 (Creamy Bokeh)**、**焦外光斑**。
    - 作用：将主体从杂乱背景中分离，强调人物神态或物体质感。
- **深景深 (Deep Depth of Field)**：用于大远景/全景。
    - 关键词：**f/11小光圈**、**全景清晰**。
    - 作用：交代宏大的环境关系。
- **空气透视 (Atmospheric Perspective)**：在远景中，必须描述远处物体因大气散射而产生的**低对比度**、**冷色调**和**朦胧感**，以建立真实的“近深远浅”空间层次。

### 5. 大师级调度思维 (Master Directors' Vision)，包括但不限于举例的这些，通读剧本了解剧本风格后，找合适剧本的大师调度方式。
根据剧本风格自动注入对应大师的视觉语言：
- **丹尼斯·维伦纽瓦**：史诗级孤独，超广角压迫，高对比度光影。
- **斯坦利·库布里克**：单点透视，对称构图，冷峻的几何秩序。
- **保罗·托马斯·安德森**：古典油画光感，长镜头感的空间排布。
- **韦斯·安德森**：极致对称，高饱和色彩，平面化美学。


### 6. 阿莱电影机与胶片质感 (ARRI Camera & Film Grain)
- **设备喜好**：全局默认使用 **ARRI Alexa** 电影机拍摄，确保画面具有顶级的动态范围和细腻的噪点结构。
- **色彩科学**：统一使用 **ARRI Alexa** 色彩科学，追求自然的肤色过渡和柔和的高光滚落。
- **质感**：画面必须包含适度的**胶片颗粒感 (Film Grain)**，追求低饱和但厚重的青橙色调 (Teal & Orange)。

### 7. 焦段叙事美学 (Lens Narrative)，包括但不限于以下举例的，你需要根据剧本使用合适的镜头。
- **超广角 (14-24mm)**：环境压迫，畸变张力，夸大近大远小的透视关系。
- **中长焦 (85-135mm)**：情感聚焦，压缩背景，使背景物体看起来比实际更大更近。
- **超长焦 (200mm+)**：极致空间压缩，窥视感，前后景紧贴。

### 8. 真实光学缺陷 (Optical Imperfections)
为了增加电影真实感，适当加入光学缺陷描述：
- **色差 (Chromatic Aberration)**：边缘轻微的红/青色边。
- **暗角 (Vignetting)**：画面四角轻微压暗，引导视线向中心。
- **镜头光晕 (Lens Flare)**：逆光时的变形宽银幕光晕 (Anamorphic Flare)。

### 9. 高密度细节的“蒙太奇”拆解
遇到密集细节（如伤疤、破损物品、纹理）时，必须拆解为一组“建立镜头 + 细节特写组”，严禁在一个镜头内塞入过多信息。

### 10. 材质纹理与物理质感
必须通过光影强调表面的**物理属性**：生锈的金属、龟裂的皮革、凝结冰霜的睫毛、布满油污的机械。

---

## 核心拆分法则

1. **影视景别切分逻辑**：寻找叙事焦点转移节点切分；遵循"环境 → 主体 → 细节"逻辑。
2. **全局上下文继承**：每一镜的 [场景基础描述] 必须包含完整背景。
3. **资产映射与角色锁定**：如有参考图，必须在 [画面描述] 开头声明（如：主角江帆是[Image1]）。并在每一镜中重复角色的核心视觉标签。
4. **精确文字捕捉**：文字元素用引号包裹，如 "咖啡馆"。
5. **严禁幻觉与脑补**：未提及元素填"无"，不添加剧本外的道具。
6. **抓住重点**：通读全文剧本后，灵活的给关键事物，道具等编排特写镜头。
7. **多场景拆分规则（严格执行）**：如果一场戏里面剧本描述出现多个场景，那么就需要拆分为多个独立的镜头，而不是同一个分镜头卡片匹配很多场景。AI生成图片模型是无法理解多张背景图的主次关系的，需要将每个场景细腻的拆开，同时要运用合理的镜头角度，而不是全都使用平淡的平拍视角。**关键原则：一个分镜头只能匹配一张场景图。** 根据剧本的场景变化，灵活拆分镜头，保证运动逻辑、角度运用和氛围的一致性。
8. **道具和背景一致性规则**：一场戏内的分镜头卡片里，对于某个贯穿的道具描写必须保持一致性，包括同一个场景内的戏对于环境背景的描述。可以根据人物的动态变化灵活的描述人物在背景的空间变化。大的场景保持不变，近处的背景细节可以根据人物位移而变化。

---

## 输出格式要求

严格按照以下模板输出。镜头间用 `==========` 分隔。

```
==========
[镜头序号]：01（请依次递增补齐两位数）
[镜头名称]：简练概括本镜
[景别]：远景 / 全景 / 中景 / 近景 / 特写 / 大特写
[视角与摄影机]：指定焦段、光圈、角度与构图（如：85mm焦段、f/1.8大光圈、浅景深、荷兰角）
[镜头角度]：明确标注拍摄角度（如：正面、侧面、背面、左侧、右侧、左斜侧、右斜侧、仰拍、俯拍、平视、顶拍、低角度等），必须符合时空关系和运动逻辑
[人物运动方向]：明确描述人物的运动方向（如：向左、向右、向前、向后、侧向左、侧向右等），确保前后镜头运动逻辑连贯
[眼神与视线]：详细描述人物的眼神和视线方向，包括眼神关注的重点（如：凝视远方、低垂看向手中物品、警惕扫视周围、眼神空洞等）
[光影氛围]：指定布光方案与环境特效（如：伦勃朗光、体积光、侧光强调纹理）
[场景基础描述]：全局环境背景（特写镜也要带背景）
[场景细节描述]：画面细节元素，描述材质和质感
[画面文字]：画面出现的文字，引号包裹
[物体状态]：物体的材质、破损及物理状态
[角色名称]：无人物填"无"
[服装化妆]：详细描述材质、污渍、妆造细节
[人物动作]：具体肢体动作（注意入画出画方向）
[人物表情]：面部表情神态，特写镜需描述细节
[使用道具]：画面中的道具
[运镜]：描述静态画面的运动趋势或视觉张力（如：动态模糊、重心失衡）
[画面描述]：(核心Prompt) 以资产映射开头（如有），整合全要素生成的电影感视觉描述。
```

## 全局设定
{{GLOBAL_SETTINGS}}

## 剧本内容
{{SCRIPT_TEXT}}

## 输出格式 (CSV)

**严格按照以下CSV格式输出，不要输出任何其他内容：**

第一行必须是以下固定表头（不要修改）：
镜头序号,镜头名称,景别,视角与摄影机,镜头角度,人物运动方向,眼神与视线,光影氛围,场景基础描述,场景细节描述,物体状态,角色名称,服装化妆,人物动作,人物表情,使用道具,运镜,画面描述

从第二行开始，每个镜头输出一行CSV数据，字段顺序与表头完全对应。

**CSV格式规则：**
- 字段之间用英文逗号 `,` 分隔
- 如果字段内容包含逗号、换行符或双引号，必须用英文双引号 `"` 将整个字段包裹
- 字段内的双引号用两个双引号 `""` 转义
- 每行末尾不加逗号
- 不要输出表头以外的任何说明文字、序号前缀或Markdown格式

## 执行指令
1. 分析剧本，选定大师风格与情绪基调。
2. 确定轴线与动线。
3. 遇到高密度细节，执行蒙太奇拆分。
4. 注入阿莱色彩与胶片颗粒感，精准控制景深与焦点。
5. **调用特定摄影师/艺术家美学，提升画面艺术质感。**
6. 严格按CSV格式输出，确保画面具有生命力与冲击力。

**开始拆解！直接输出CSV，不要任何前言或解释。**''';
  }


  /// 解析CSV格式的分镜头数据（优先使用）
  List<Shot> _parseCsvFormat(String content) {
    final shots = <Shot>[];
    final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) throw Exception('CSV内容为空');

    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('镜头序号') && lines[i].contains('镜头名称') && lines[i].contains('景别')) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == -1) throw Exception('未找到CSV表头行');

    final headers = _parseCsvLine(lines[headerIndex]);

    for (int i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      try {
        final fields = _parseCsvLine(line);
        if (fields.isEmpty || fields.length < 3) continue;
        String getField(String key) {
          final idx = headers.indexOf(key);
          if (idx == -1 || idx >= fields.length) return '';
          return fields[idx].trim();
        }
        final shotNumber = getField('镜头序号');
        if (shotNumber.isEmpty) continue;
        shots.add(Shot(
          shotNumber: shotNumber,
          shotName: getField('镜头名称'),
          shotType: getField('景别').isEmpty ? '中景' : getField('景别'),
          cameraAngle: getField('视角与摄影机'),
          lighting: getField('光影氛围'),
          sceneDescription: getField('场景基础描述'),
          sceneDetails: getField('场景细节描述'),
          textInFrame: getField('画面文字').isEmpty ? '无' : getField('画面文字'),
          objectState: getField('物体状态').isEmpty ? '无' : getField('物体状态'),
          characterName: getField('角色名称').isEmpty ? '无' : getField('角色名称'),
          costume: getField('服装化妆').isEmpty ? '无' : getField('服装化妆'),
          action: getField('人物动作').isEmpty ? '无' : getField('人物动作'),
          expression: getField('人物表情').isEmpty ? '无' : getField('人物表情'),
          props: getField('使用道具').isEmpty ? '无' : getField('使用道具'),
          movement: getField('运镜').isEmpty ? '固定镜头' : getField('运镜'),
          prompt: getField('画面描述'),
          characters: getField('角色名称').isNotEmpty && getField('角色名称') != '无'
              ? [getField('角色名称')] : [],
          summary: getField('镜头名称'),
        ));
      } catch (e) {
        debugPrint('解析CSV行失败: $line, 错误: $e');
        continue;
      }
    }
    if (shots.isEmpty) throw Exception('CSV解析失败：未找到有效的镜头数据');
    return shots;
  }

  /// 解析单行CSV，支持带引号的字段
  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    int i = 0;
    while (i < line.length) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i += 2;
          continue;
        }
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
      i++;
    }
    fields.add(buffer.toString());
    return fields;
  }
  List<Shot> _parseTextFormat(String content) {
    final shots = <Shot>[];
    final shotBlocks = content.split('==========').where((s) => s.trim().isNotEmpty).toList();

    if (shotBlocks.isEmpty) {
      throw Exception('AI返回内容缺少分镜分隔符(==========)，请检查AI返回格式');
    }

    final regex = RegExp(r'\[([^\]]+)\][:：]\s*([\s\S]*?)(?=\n\[|$)');

    for (final block in shotBlocks) {
      final shotData = <String, String>{};
      final matches = regex.allMatches(block);

      for (final match in matches) {
        final key = match.group(1)!.trim();
        final value = match.group(2)!.trim();
        shotData[key] = value;
      }

      if (shotData.isNotEmpty && shotData.containsKey('镜头序号')) {
        shots.add(Shot(
          shotNumber: shotData['镜头序号'] ?? '',
          shotName: shotData['镜头名称'] ?? '',
          shotType: shotData['景别'] ?? '中景',
          cameraAngle: shotData['视角与摄影机'] ?? '',
          lighting: shotData['光影氛围'] ?? '',
          sceneDescription: shotData['场景基础描述'] ?? '',
          sceneDetails: shotData['场景细节描述'] ?? '',
          textInFrame: shotData['画面文字'] ?? '无',
          objectState: shotData['物体状态'] ?? '无',
          characterName: shotData['角色名称'] ?? '无',
          costume: shotData['服装化妆'] ?? '无',
          action: shotData['人物动作'] ?? '无',
          expression: shotData['人物表情'] ?? '无',
          props: shotData['使用道具'] ?? '无',
          movement: shotData['运镜'] ?? '固定镜头',
          prompt: shotData['画面描述'] ?? '',
          characters: shotData['角色名称'] != null && shotData['角色名称'] != '无'
              ? [shotData['角色名称']!]
              : [],
          summary: shotData['镜头名称'],
        ));
      }
    }

    if (shots.isEmpty) {
      throw Exception('AI返回内容格式错误：未找到有效的镜头序号字段，请检查AI返回是否符合模板格式');
    }

    return shots;
  }

  Future<List<Shot>> splitScript({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String script,
    required String artStyle,
    required String worldView,
    required String aspectRatio,
    required List<Map<String, String>> assets,
    String fullScript = '',
    String scriptAnalysis = '',
    Function(String)? onProgress,
  }) async {
    String systemPrompt = await _loadSystemPrompt();

    final contextInfo = StringBuffer();
    if (fullScript.isNotEmpty) {
      contextInfo.writeln('\n## 完整剧情上下文\n$fullScript');
    }
    if (scriptAnalysis.isNotEmpty) {
      contextInfo.writeln('\n## 剧情详解（专业导演视角分析）\n$scriptAnalysis');
    }

    final globalSettings = '''
美术风格：$artStyle
世界观：$worldView
画幅比例：$aspectRatio
角色资产：${assets.map((a) => '${a['name']}: ${a['feature']}').join(', ')}
${contextInfo.toString()}''';

    systemPrompt = systemPrompt
        .replaceAll('{{GLOBAL_SETTINGS}}', globalSettings)
        .replaceAll('{{SCRIPT_TEXT}}', script)
        .replaceAll('{{STORY_BACKGROUND}}', scriptAnalysis);

    String userPrompt = '请严格按照系统提示词中的模板，将以下剧本拆分成带序号的分镜头，不要输出任何多余的解释：\n$script';

    if (fullScript.isNotEmpty) {
      userPrompt = '''请先阅读以下完整剧本，理解故事的完整结构、情感基调，叙事节奏和情感走向，服化道风格，人物性格塑造，时代历史背景，人文背景等。
理解完整剧本里的各种元素：内景外景和日景夜景、场地、动作、道具、动物、车辆、特技、武器、特效、发型化妆等，需要根据剧本的故事发展来统筹。保证拆分出来的分镜头所有内容都是连贯和符合氛围的。

【完整剧本】
$fullScript

现在，请基于对完整剧本的理解，从全局观出发，将以下片段拆分成连贯且精妙的分镜头。确保每个镜头的设计都服务于整体叙事，镜头之间的衔接流畅自然，符合故事的情感节奏。

【待拆解片段】
$script

请严格按照系统提示词中的模板输出，不要输出任何多余的解释。''';
    }

    final buffer = StringBuffer();
    final stream = _apiService.chatStream(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
    );

    await for (final chunk in stream) {
      buffer.write(chunk);
      onProgress?.call(chunk);
    }
    
    final content = buffer.toString();

    // 调试日志：输出AI返回的原始内容
    debugPrint('=== AI返回的原始内容 ===');
    debugPrint(content);
    debugPrint('=== 内容长度: ${content.length} ===');

    // 优先使用CSV格式解析，兼容旧的文本格式
    try {
      List<Shot> shots;
      if (content.contains('镜头序号,镜头名称,景别') || content.contains('镜头序号,镜头名称')) {
        shots = _parseCsvFormat(content);
      } else {
        shots = _parseTextFormat(content);
      }
      // 后处理：确保每个 Shot 对象都有默认值，防止 UI 渲染出错
      for (var i = 0; i < shots.length; i++) {
        final s = shots[i];
        if (s.shotNumber.isEmpty) shots[i] = s.copyWith(shotNumber: (i + 1).toString().padLeft(2, '0'));
        if (s.shotName.isEmpty) shots[i] = s.copyWith(shotName: '镜头${i + 1}');
      }
      return shots;
    } catch (e) {
      // 如果文本解析失败，尝试 JSON 解析作为兜底（虽然 Prompt 不建议输出 JSON）
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch != null) {
        try {
          final jsonStr = jsonMatch.group(0)!;
          final List<dynamic> jsonList = jsonDecode(jsonStr);
          return jsonList.map((json) => Shot.fromJson(json)).toList();
        } catch (e) {
          // ignore
        }
      }
      rethrow;
    }
  }

  Future<StoryboardAssets> extractAssets({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Shot> shots,
  }) async {
    final shotsText = shots.map((s) => '''
镜头${s.shotNumber}: ${s.shotName}
角色: ${s.characterName}
道具: ${s.props}
服装: ${s.costume}
场景: ${s.sceneDescription}
氛围: ${s.lighting}
''').join('\n');

    final prompt = '''请从以下分镜头内容中提取并统计：
1. 人物列表（去重，多次出现的人物只列一次）
2. 关键道具（车、武器、剧本多次提到的道具，去重）
3. 服装描述（去重）
4. 场景列表（去重）
5. 整体氛围（总结）

分镜内容：
$shotsText

请严格按照以下格式输出，不要有任何额外文字：
人物：xxx、xxx
关键道具：xxx、xxx
服装：xxx、xxx
场景：xxx、xxx
氛围：xxx''';

    final content = await _apiService.chat(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      messages: [{'role': 'user', 'content': prompt}],
    );

    return StoryboardAssets.parseFromString(content);
  }

  Future<String> analyzeScript({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String script,
    Function(String)? onProgress,
  }) async {
    final systemPrompt = '''你是一位经验丰富的专业电影导演，请深度解析以下剧本。

要求：
1. 以专业电影导演的身份解析每一场戏的剧情
2. 详细分析人物心理变化、环境氛围、道具、服装等因素
3. 归纳特殊道具或事物如何起到贯穿全剧的作用
4. 不要概括描述，要详细解析每场戏的细节
5. 输出格式为Markdown，便于阅读和编辑

请按照以下结构输出：

# 剧本深度解析

## 整体概述
[剧本的整体风格、主题、情感基调]

## 分场解析
[按场次详细解析每一场戏]

### 第X场：[场次名称]
- **剧情要点**：[本场核心剧情]
- **人物心理**：[角色的内心变化和情感状态]
- **环境氛围**：[场景的氛围营造、光影、色调]
- **道具服装**：[重要道具和服装的作用]
- **导演视角**：[从导演角度分析镜头语言和叙事手法]

## 贯穿元素分析
[分析贯穿全剧的特殊道具、符号、主题等]

## 视觉风格建议
[整体的视觉风格、色彩基调、摄影风格建议]''';

    final userPrompt = '''请深度解析以下剧本：

$script

请严格按照系统提示词中的结构输出详细的剧本解析。''';

    final buffer = StringBuffer();
    final stream = _apiService.chatStream(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userPrompt}],
    );

    await for (final chunk in stream) {
      buffer.write(chunk);
      onProgress?.call(chunk);
    }

    return buffer.toString();
  }
}
