import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// 统一重绘编辑器 — 标签页合并「多角度」「灯光」「裁切」
/// 两个标签页的参数可以组合使用也可以单独使用
class RepaintEditor extends StatefulWidget {
  final String imagePath;
  final void Function(String prompt, String imagePath, {Uint8List? croppedBytes}) onGenerate;
  final void Function(String prompt, String imagePath)? onReturnToInput;

  const RepaintEditor({
    super.key,
    required this.imagePath,
    required this.onGenerate,
    this.onReturnToInput,
  });

  @override
  State<RepaintEditor> createState() => _RepaintEditorState();
}

class _RepaintEditorState extends State<RepaintEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ui.Image? _refImage;

  // ── 多角度参数 ──
  double _camAzimuth = 0;
  double _camElevation = 0;
  double _camDistance = 5;
  bool _angleEnabled = false;
  String _anglePreset = '自定义';

  // ── 灯光参数 ──
  double _lightAzimuth = 225;
  double _lightElevation = 45;
  double _lightIntensity = 5;
  double _lightColorTemp = 6;
  String _lightType = '柔光';
  bool _lightEnabled = false;
  String _lightPreset = '自定义';

  // ── 角度/原点模式 ──
  bool _originMode = false;

  // ── 中英文切换 ──
  bool _useChinese = false;

  // ── 提示词编辑框 ──
  final TextEditingController _promptEditController = TextEditingController();
  bool _isUserEditing = false;

  // ── 裁切参数 ──
  Rect _cropRect = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  String _cropAspectRatio = '自由';
  bool _hasCrop = false;
  ui.Image? _fullImage;
  Size? _fullImageSize;

  // ── 用户自定义预设 ──
  final List<Map<String, dynamic>> _savedAnglePresets = [];
  final List<Map<String, dynamic>> _savedLightPresets = [];

  static const _anglePresets = {
    '自定义': null,
    '鱼眼视角': [0.0, 60.0, 2.0],
    '倾斜视角': [45.0, 30.0, 5.0],
    '正面俯拍': [0.0, 60.0, 5.0],
    '正面仰拍': [0.0, -30.0, 5.0],
    '全景俯拍': [0.0, 60.0, 10.0],
    '背面视角': [180.0, 0.0, 5.0],
    '左侧视角': [270.0, 0.0, 5.0],
    '右侧视角': [90.0, 0.0, 5.0],
  };

  static const _lightPresets = <String, dynamic>{
    '自定义': null,
    '主光源': [225.0, 45.0, 6.0, 6.0, '柔光'],
    '补光': [135.0, 30.0, 3.0, 5.0, '柔光'],
    '轮廓光': [0.0, 20.0, 7.0, 4.0, '硬光'],
    '顶光': [0.0, 85.0, 7.0, 5.0, '硬光'],
    '底光': [0.0, -25.0, 5.0, 4.0, '柔光'],
    '背光': [180.0, 30.0, 6.0, 6.0, '硬光'],
    '侧光': [270.0, 10.0, 7.0, 5.0, '硬光'],
    '黄金时刻': [250.0, 15.0, 5.0, 9.0, '柔光'],
    '蓝调时刻': [200.0, 10.0, 4.0, 1.0, '漫射光'],
    '伦勃朗光': [240.0, 40.0, 8.0, 6.0, '硬光'],
  };

  static const _lightTypes = ['柔光', '硬光', '漫射光', '聚光'];

  static const _cropRatios = <String, double?>{
    '自由': null,
    '1:1': 1.0,
    '3:4': 3.0 / 4.0,
    '4:3': 4.0 / 3.0,
    '16:9': 16.0 / 9.0,
    '9:16': 9.0 / 16.0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRefImage();
    _loadFullImage();
    // 初始填充提示词
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPromptToEditor());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptEditController.dispose();
    super.dispose();
  }

  Future<void> _loadRefImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120, targetHeight: 120);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _refImage = frame.image);
    } catch (_) {}
  }

  Future<void> _loadFullImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _fullImage = frame.image;
          _fullImageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        });
      }
    } catch (_) {}
  }

  /// 将自动生成的提示词同步到编辑框（仅在非用户编辑状态下）
  void _syncPromptToEditor() {
    if (!_isUserEditing) {
      _promptEditController.text = _submitPrompt;
    }
  }

  // ── 合并提示词 ──

  String get _submitPrompt => _useChinese ? _combinedPromptCN : _combinedPrompt;

  String get _combinedPrompt {
    final parts = <String>[];
    if (_angleEnabled) parts.add(_anglePrompt);
    if (_lightEnabled) parts.add(_lightPrompt);
    if (parts.isEmpty) {
      return _tabController.index == 0 ? _anglePrompt : (_tabController.index == 1 ? _lightPrompt : _anglePrompt);
    }
    return parts.join(', ');
  }

  String get _combinedPromptCN {
    final parts = <String>[];
    if (_angleEnabled) parts.add(_anglePromptCN);
    if (_lightEnabled) parts.add(_lightPromptCN);
    if (parts.isEmpty) {
      return _tabController.index == 0 ? _anglePromptCN : (_tabController.index == 1 ? _lightPromptCN : _anglePromptCN);
    }
    return parts.join('，');
  }


  // ══════════════════════════════════════════════════════════
  // 优化后的多角度提示词 — 用视觉描述替代摄影术语
  // ══════════════════════════════════════════════════════════

  String get _anglePrompt {
    if (_originMode) return _originAnglePrompt;
    final az = _azToText(_camAzimuth);
    final el = _elToText(_camElevation);
    final dist = _distToText(_camDistance);
    return '$az, $el, $dist';
  }

  String get _anglePromptCN {
    if (_originMode) return _originAnglePromptCN;
    final az = _azToTextCN(_camAzimuth);
    final el = _elToTextCN(_camElevation);
    final dist = _distToTextCN(_camDistance);
    return '$az，$el，$dist';
  }

  // 原点模式提示词
  String get _originAnglePrompt {
    final h = _camAzimuth;
    final v = _camElevation;
    String hDir;
    if (h.abs() < 5) { hDir = 'keep the same horizontal angle'; }
    else if (h > 0) { hDir = 'rotate the view ${h.round()} degrees to the right'; }
    else { hDir = 'rotate the view ${h.abs().round()} degrees to the left'; }
    String vDir;
    if (v.abs() < 5) { vDir = 'keep the same vertical angle'; }
    else if (v > 0) { vDir = 'tilt ${v.round()} degrees upward'; }
    else { vDir = 'tilt ${v.abs().round()} degrees downward'; }
    final dist = _distToText(_camDistance);
    return '$hDir, $vDir, $dist';
  }

  String get _originAnglePromptCN {
    final h = _camAzimuth;
    final v = _camElevation;
    String hDir;
    if (h.abs() < 5) { hDir = '水平角度不变'; }
    else if (h > 0) { hDir = '视角向右旋转${h.round()}度'; }
    else { hDir = '视角向左旋转${h.abs().round()}度'; }
    String vDir;
    if (v.abs() < 5) { vDir = '垂直角度不变'; }
    else if (v > 0) { vDir = '向上倾斜${v.round()}度'; }
    else { vDir = '向下倾斜${v.abs().round()}度'; }
    final dist = _distToTextCN(_camDistance);
    return '$hDir，$vDir，$dist';
  }

  // 优化后的方位描述 — 视觉场景描述
  String _azToText(double deg) {
    deg = deg % 360;
    if (deg < 22.5 || deg >= 337.5) return 'viewed from the front';
    if (deg < 67.5) return 'viewed from the front-right at ${deg.round()} degrees';
    if (deg < 112.5) return 'side view from the right';
    if (deg < 157.5) return 'viewed from the back-right at ${deg.round()} degrees';
    if (deg < 202.5) return 'viewed from behind, back view';
    if (deg < 247.5) return 'viewed from the back-left at ${deg.round()} degrees';
    if (deg < 292.5) return 'side view from the left';
    return 'viewed from the front-left at ${deg.round()} degrees';
  }

  String _elToText(double deg) {
    if (deg <= -20) return 'seen from below, looking up at ${deg.abs().round()} degrees';
    if (deg <= -5) return 'slight low angle, looking up';
    if (deg <= 10) return 'at eye level';
    if (deg <= 30) return 'seen from slightly above at ${deg.round()} degrees';
    if (deg <= 60) return 'seen from above, looking down at ${deg.round()} degrees';
    return 'bird\'s eye view, looking straight down';
  }

  String _distToText(double d) {
    if (d <= 2) return 'extreme close-up, detailed view';
    if (d <= 4) return 'close-up shot';
    if (d <= 7) return 'medium shot, waist-up framing';
    return 'wide shot, full scene visible';
  }

  String _azToTextCN(double deg) {
    deg = deg % 360;
    if (deg < 22.5 || deg >= 337.5) return '从正面观看';
    if (deg < 67.5) return '从右前方${deg.round()}度角观看';
    if (deg < 112.5) return '从右侧观看';
    if (deg < 157.5) return '从右后方${deg.round()}度角观看';
    if (deg < 202.5) return '从背面观看';
    if (deg < 247.5) return '从左后方${deg.round()}度角观看';
    if (deg < 292.5) return '从左侧观看';
    return '从左前方${deg.round()}度角观看';
  }

  String _elToTextCN(double deg) {
    if (deg <= -20) return '从下方${deg.abs().round()}度仰视';
    if (deg <= -5) return '略微仰视';
    if (deg <= 10) return '平视角度';
    if (deg <= 30) return '从上方${deg.round()}度俯视';
    if (deg <= 60) return '高角度俯视${deg.round()}度';
    return '鸟瞰视角，垂直向下';
  }

  String _distToTextCN(double d) {
    if (d <= 2) return '极近特写';
    if (d <= 4) return '近景特写';
    if (d <= 7) return '中景构图';
    return '远景全景';
  }

  // ══════════════════════════════════════════════════════════
  // 灯光提示词
  // ══════════════════════════════════════════════════════════

  String get _lightPrompt {
    if (_originMode) return _originLightPrompt;
    final dir = _lightDirToText(_lightAzimuth, _lightElevation);
    final intens = _lightIntensToText(_lightIntensity);
    final temp = _lightTempToText(_lightColorTemp);
    final type = _lightTypeToText(_lightType);
    return 'Relight with: $type $temp light $dir, $intens';
  }

  String get _lightPromptCN {
    if (_originMode) return _originLightPromptCN;
    final dir = _lightDirToTextCN(_lightAzimuth, _lightElevation);
    final intens = _lightIntensCN(_lightIntensity);
    final temp = _lightTempCN(_lightColorTemp);
    return '打光：$dir，$_lightType，$temp，$intens';
  }

  String get _originLightPrompt {
    final h = _lightAzimuth;
    final v = _lightElevation;
    String hDir;
    if (h.abs() < 5) { hDir = 'keep current light direction'; }
    else if (h > 0) { hDir = 'shift light ${h.round()} degrees to the right'; }
    else { hDir = 'shift light ${h.abs().round()} degrees to the left'; }
    String vDir;
    if (v.abs() < 5) { vDir = 'keep current light height'; }
    else if (v > 0) { vDir = 'raise light ${v.round()} degrees'; }
    else { vDir = 'lower light ${v.abs().round()} degrees'; }
    final intens = _lightIntensToText(_lightIntensity);
    final temp = _lightTempToText(_lightColorTemp);
    final type = _lightTypeToText(_lightType);
    return '$hDir, $vDir, $type $temp, $intens';
  }

  String get _originLightPromptCN {
    final h = _lightAzimuth;
    final v = _lightElevation;
    String hDir;
    if (h.abs() < 5) { hDir = '方位不变'; }
    else if (h > 0) { hDir = '灯光右移${h.round()}度'; }
    else { hDir = '灯光左移${h.abs().round()}度'; }
    String vDir;
    if (v.abs() < 5) { vDir = '高度不变'; }
    else if (v > 0) { vDir = '灯光上移${v.round()}度'; }
    else { vDir = '灯光下移${v.abs().round()}度'; }
    final intens = _lightIntensCN(_lightIntensity);
    final temp = _lightTempCN(_lightColorTemp);
    return '$hDir，$vDir，$_lightType，$temp，$intens';
  }

  String _lightDirToText(double az, double el) {
    az = az % 360;
    String h;
    if (az < 22.5 || az >= 337.5) { h = 'from front'; }
    else if (az < 67.5) { h = 'from front-left ${az.round()}°'; }
    else if (az < 112.5) { h = 'from left ${az.round()}°'; }
    else if (az < 157.5) { h = 'from back-left ${az.round()}°'; }
    else if (az < 202.5) { h = 'from behind'; }
    else if (az < 247.5) { h = 'from back-right ${az.round()}°'; }
    else if (az < 292.5) { h = 'from right ${az.round()}°'; }
    else { h = 'from front-right ${az.round()}°'; }
    String v;
    if (el > 75) { v = 'directly above'; }
    else if (el > 45) { v = 'high ${el.round()}°'; }
    else if (el > 15) { v = 'upper ${el.round()}°'; }
    else if (el > -10) { v = 'eye level'; }
    else { v = 'below ${el.round()}°'; }
    return '$h, $v';
  }

  String _lightDirToTextCN(double az, double el) {
    az = az % 360;
    String h;
    if (az < 22.5 || az >= 337.5) { h = '正前方'; }
    else if (az < 112.5) { h = '左侧${az.round()}°'; }
    else if (az < 202.5) { h = '后方'; }
    else if (az < 292.5) { h = '右侧${az.round()}°'; }
    else { h = '右前方${az.round()}°'; }
    String v = el > 45 ? '上方${el.round()}°' : el > -10 ? '平射' : '下方${el.round()}°';
    return '$h $v';
  }

  String _lightIntensToText(double v) {
    if (v <= 3) return 'gentle';
    if (v <= 6) return 'medium';
    return 'dramatic';
  }

  String _lightIntensCN(double v) {
    if (v <= 3) return '柔和';
    if (v <= 6) return '中等';
    return '强烈';
  }

  String _lightTempToText(double v) {
    if (v <= 3) return 'cool blue';
    if (v <= 6) return 'neutral';
    return 'warm golden';
  }

  String _lightTempCN(double v) {
    if (v <= 3) return '冷光';
    if (v <= 6) return '自然光';
    return '暖光';
  }

  String _lightTypeToText(String t) {
    switch (t) {
      case '硬光': return 'hard';
      case '漫射光': return 'diffused';
      case '聚光': return 'spotlight';
      default: return 'soft';
    }
  }


  // ══════════════════════════════════════════════════════════
  // 主 UI
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a1a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 920,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('重绘编辑器',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // 标签页（3个：多角度、灯光、裁切）
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerHeight: 0,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.threed_rotation, size: 16),
                        const SizedBox(width: 6),
                        const Text('多角度'),
                        const SizedBox(width: 6),
                        _buildEnableChip(_angleEnabled, (v) => setState(() { _angleEnabled = v; _syncPromptToEditor(); })),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.light_mode, size: 16),
                        const SizedBox(width: 6),
                        const Text('灯光'),
                        const SizedBox(width: 6),
                        _buildEnableChip(_lightEnabled, (v) => setState(() { _lightEnabled = v; _syncPromptToEditor(); })),
                      ],
                    ),
                  ),
                  const Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.crop, size: 16),
                        SizedBox(width: 6),
                        Text('裁切'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 标签页内容 + 右侧预设栏
            SizedBox(
              height: 340,
              child: Row(
                children: [
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAngleTab(),
                        _buildLightingTab(),
                        _buildCropTab(),
                      ],
                    ),
                  ),
                  // 右侧预设栏（裁切页不显示）
                  if (_tabController.index != 2)
                    Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3a3a3a)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFF3a3a3a))),
                            ),
                            child: Center(
                              child: Text(
                                _tabController.index == 0 ? '角度预设' : '灯光预设',
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Expanded(child: _buildSavedPresetsList()),
                          InkWell(
                            onTap: _addCustomPreset,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: Color(0xFF3a3a3a))),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, size: 14, color: Colors.white54),
                                  SizedBox(width: 4),
                                  Text('添加预设', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // 提示词编辑框（始终展开）
            Container(
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _isUserEditing ? AppColors.primary.withOpacity(0.5) : const Color(0xFF3a3a3a)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _isUserEditing ? '✏️ 手动编辑中（重置后恢复自动）' : '📝 提示词（自动同步参数）',
                        style: TextStyle(color: _isUserEditing ? AppColors.primary : Colors.white38, fontSize: 10),
                      ),
                      const Spacer(),
                      if (_isUserEditing)
                        InkWell(
                          onTap: () => setState(() {
                            _isUserEditing = false;
                            _syncPromptToEditor();
                          }),
                          child: const Text('恢复自动', style: TextStyle(color: AppColors.primary, fontSize: 10)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _promptEditController,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      filled: true,
                      fillColor: Color(0xFF222222),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        borderSide: BorderSide.none,
                      ),
                      hintText: '提示词将随参数变化自动填充，也可手动编辑...',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                    onChanged: (text) {
                      // 用户手动编辑时标记
                      if (!_isUserEditing) {
                        setState(() => _isUserEditing = true);
                      }
                    },
                  ),
                ],
              ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  // 保存为预设
                  InkWell(
                    onTap: _saveCurrentAsPreset,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_add_outlined, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('保存预设', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 角度/原点模式切换
                  InkWell(
                    onTap: () => setState(() {
                      _originMode = !_originMode;
                      if (_originMode) {
                        _camAzimuth = 0; _camElevation = 0;
                        _lightAzimuth = 0; _lightElevation = 0;
                      }
                      _anglePreset = '自定义'; _angleEnabled = true;
                      _lightPreset = '自定义'; _lightEnabled = true;
                      _syncPromptToEditor();
                    }),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _originMode ? AppColors.primary : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _originMode ? '原点模式' : '角度模式',
                        style: TextStyle(color: _originMode ? Colors.white : Colors.white70, fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 中文/英文切换
                  InkWell(
                    onTap: () => setState(() { _useChinese = !_useChinese; _syncPromptToEditor(); }),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _useChinese ? const Color(0xFF4CAF50) : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _useChinese ? '中文' : '英文',
                        style: TextStyle(color: _useChinese ? Colors.white : Colors.white70, fontSize: 11),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onReturnToInput != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        final prompt = _promptEditController.text.trim().isNotEmpty
                            ? _promptEditController.text.trim()
                            : _submitPrompt;
                        widget.onReturnToInput!(prompt, widget.imagePath);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
                      label: const Text('返回输入', style: TextStyle(color: Colors.white70)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prompt = _promptEditController.text.trim().isNotEmpty
                          ? _promptEditController.text.trim()
                          : _submitPrompt;
                      Uint8List? croppedBytes;
                      if (_hasCrop) {
                        croppedBytes = await _getCroppedImageBytes();
                        debugPrint('[重绘编辑器] _hasCrop=$_hasCrop, croppedBytes=${croppedBytes != null ? "${croppedBytes.length} bytes" : "null"}');
                      } else {
                        debugPrint('[重绘编辑器] 未裁切, _hasCrop=false');
                      }
                      widget.onGenerate(prompt, widget.imagePath, croppedBytes: croppedBytes);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                    label: const Text('提交生成', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildEnableChip(bool enabled, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : Colors.transparent,
          border: Border.all(color: enabled ? AppColors.primary : Colors.white38, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: enabled ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 裁切图片获取
  // ══════════════════════════════════════════════════════════

  Future<Uint8List?> _getCroppedImageBytes() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) {
        debugPrint('[裁切] 文件不存在: ${widget.imagePath}');
        return null;
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final srcRect = Rect.fromLTRB(
        (_cropRect.left * img.width).roundToDouble(),
        (_cropRect.top * img.height).roundToDouble(),
        (_cropRect.right * img.width).roundToDouble(),
        (_cropRect.bottom * img.height).roundToDouble(),
      );

      final w = srcRect.width.round();
      final h = srcRect.height.round();
      if (w <= 0 || h <= 0) {
        debugPrint('[裁切] 裁切尺寸无效: ${w}x$h, cropRect=$_cropRect, imgSize=${img.width}x${img.height}');
        return null;
      }

      debugPrint('[裁切] 执行裁切: 原图${img.width}x${img.height} -> 裁切${w}x$h, rect=$srcRect');

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        srcRect,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final croppedImg = await picture.toImage(w, h);
      final byteData = await croppedImg.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('[裁切] toByteData返回null');
        return null;
      }
      final result = byteData.buffer.asUint8List();
      debugPrint('[裁切] 裁切成功: ${result.length} bytes');
      return result;
    } catch (e, stack) {
      debugPrint('[裁切] 裁切异常: $e\n$stack');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════
  // 保存预设
  // ══════════════════════════════════════════════════════════

  void _saveCurrentAsPreset() {
    final isAngle = _tabController.index == 0;
    final defaultName = '预设${(isAngle ? _savedAnglePresets : _savedLightPresets).length + 1}';
    final controller = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text('保存预设', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: '输入预设名称',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
          onSubmitted: (_) {
            _doSavePreset(controller.text.trim(), isAngle);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () { _doSavePreset(controller.text.trim(), isAngle); Navigator.pop(ctx); },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _doSavePreset(String name, bool isAngle) {
    if (name.isEmpty) name = '预设${(isAngle ? _savedAnglePresets : _savedLightPresets).length + 1}';
    setState(() {
      if (isAngle) {
        _savedAnglePresets.add({
          'name': name, 'azimuth': _camAzimuth, 'elevation': _camElevation,
          'distance': _camDistance, 'originMode': _originMode,
        });
      } else {
        _savedLightPresets.add({
          'name': name, 'azimuth': _lightAzimuth, 'elevation': _lightElevation,
          'intensity': _lightIntensity, 'colorTemp': _lightColorTemp, 'lightType': _lightType,
        });
      }
    });
  }

  Widget _buildSavedPresetsList() {
    final isAngle = _tabController.index == 0;
    final presets = isAngle ? _savedAnglePresets : _savedLightPresets;

    if (presets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无预设\n点击下方"保存预设"添加',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white30, fontSize: 11)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final p = presets[index];
        return GestureDetector(
          onTap: () => _loadSavedPreset(p, isAngle),
          onDoubleTap: () => p.containsKey('customPrompt')
              ? _editCustomPreset(presets, index)
              : _editPresetName(presets, index),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                Icon(
                  p.containsKey('customPrompt') ? Icons.text_fields : (isAngle ? Icons.videocam : Icons.light_mode),
                  size: 12,
                  color: p.containsKey('customPrompt') ? const Color(0xFF81C784) : (isAngle ? const Color(0xFFFF6B6B) : const Color(0xFFFFD54F)),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(p['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis)),
                InkWell(
                  onTap: () => setState(() => presets.removeAt(index)),
                  child: const Icon(Icons.close, size: 12, color: Colors.white30),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editPresetName(List<Map<String, dynamic>> presets, int index) {
    final controller = TextEditingController(text: presets[index]['name'] as String);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text('编辑预设名称', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller, autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
          onSubmitted: (_) {
            if (controller.text.trim().isNotEmpty) setState(() => presets[index]['name'] = controller.text.trim());
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) setState(() => presets[index]['name'] = controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _editCustomPreset(List<Map<String, dynamic>> presets, int index) {
    final p = presets[index];
    final nameCtrl = TextEditingController(text: p['name'] as String);
    final promptCtrl = TextEditingController(text: p['customPrompt'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text('编辑自定义预设', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('预设名称', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
            const SizedBox(height: 12),
            const Text('提示词', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(controller: promptCtrl, maxLines: 4, style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              setState(() {
                if (nameCtrl.text.trim().isNotEmpty) presets[index]['name'] = nameCtrl.text.trim();
                if (promptCtrl.text.trim().isNotEmpty) presets[index]['customPrompt'] = promptCtrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _addCustomPreset() {
    final isAngle = _tabController.index == 0;
    final nameCtrl = TextEditingController(text: '自定义预设${(isAngle ? _savedAnglePresets : _savedLightPresets).length + 1}');
    final promptCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: Text('添加${isAngle ? "角度" : "灯光"}预设', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('预设名称', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(controller: nameCtrl, autofocus: true, style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(hintText: '输入名称', hintStyle: const TextStyle(color: Colors.white30),
                filled: true, fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
            const SizedBox(height: 12),
            Text('${isAngle ? "角度" : "灯光"}提示词', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(controller: promptCtrl, maxLines: 4, style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: isAngle ? '例如: viewed from behind, seen from above, close-up shot' : '例如: soft warm golden light from upper-left, dramatic intensity',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11),
                filled: true, fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (name.isNotEmpty && prompt.isNotEmpty) {
                setState(() { (isAngle ? _savedAnglePresets : _savedLightPresets).add({'name': name, 'customPrompt': prompt}); });
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _loadSavedPreset(Map<String, dynamic> p, bool isAngle) {
    // 自定义文本预设：填充到编辑框（不再直接提交）
    if (p.containsKey('customPrompt')) {
      setState(() {
        _isUserEditing = true;
        _promptEditController.text = p['customPrompt'] as String;
      });
      return;
    }

    setState(() {
      if (isAngle) {
        _camAzimuth = (p['azimuth'] as num).toDouble();
        _camElevation = (p['elevation'] as num).toDouble();
        _camDistance = (p['distance'] as num).toDouble();
        _originMode = p['originMode'] as bool? ?? false;
        _anglePreset = '自定义'; _angleEnabled = true;
      } else {
        _lightAzimuth = (p['azimuth'] as num).toDouble();
        _lightElevation = (p['elevation'] as num).toDouble();
        _lightIntensity = (p['intensity'] as num).toDouble();
        _lightColorTemp = (p['colorTemp'] as num).toDouble();
        _lightType = p['lightType'] as String? ?? '柔光';
        _lightPreset = '自定义'; _lightEnabled = true;
      }
      _syncPromptToEditor();
    });
  }


  // ══════════════════════════════════════════════════════════
  // 多角度标签页（修复原点模式180度限位）
  // ══════════════════════════════════════════════════════════

  Widget _buildAngleTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Wrap(
              spacing: 8, runSpacing: 6,
              children: [
                ..._anglePresets.keys.map((name) {
                  final isActive = _anglePreset == name;
                  return InkWell(
                    onTap: () {
                      final v = _anglePresets[name];
                      setState(() {
                        _anglePreset = name; _angleEnabled = true;
                        if (v != null) { _camAzimuth = v[0]; _camElevation = v[1]; _camDistance = v[2]; }
                        _syncPromptToEditor();
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: isActive ? Colors.white : const Color(0xFF333333), borderRadius: BorderRadius.circular(6)),
                      child: Text(name, style: TextStyle(color: isActive ? Colors.black : Colors.white, fontSize: 11)),
                    ),
                  );
                }),
                // 重置按钮 — 同时恢复自动填充
                InkWell(
                  onTap: () => setState(() {
                    _camAzimuth = 0; _camElevation = 0; _camDistance = 5;
                    _anglePreset = '自定义'; _angleEnabled = false;
                    _isUserEditing = false; // 恢复自动填充
                    _syncPromptToEditor();
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 12, color: Colors.white54),
                        SizedBox(width: 3),
                        Text('重置', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAngleSphere(),
                const SizedBox(width: 20),
                Expanded(child: _buildAngleSliders()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleSphere() {
    return SizedBox(
      width: 240, height: 240,
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (d) => setState(() {
              if (_originMode) {
                _camAzimuth = (_camAzimuth + d.delta.dx * 0.8).clamp(-180.0, 180.0);
                _camElevation = (_camElevation - d.delta.dy * 0.4).clamp(-90.0, 90.0);
              } else {
                _camAzimuth = (_camAzimuth + d.delta.dx * 0.8) % 360;
                _camElevation = (_camElevation - d.delta.dy * 0.4).clamp(-30.0, 90.0);
              }
              _anglePreset = '自定义'; _angleEnabled = true;
              _syncPromptToEditor();
            }),
            child: CustomPaint(
              size: const Size(240, 240),
              painter: _CameraSpherePainter(azimuth: _camAzimuth, elevation: _camElevation, distance: _camDistance, refImage: _refImage),
            ),
          ),
          _arrowBtn(Alignment.topCenter, Icons.keyboard_arrow_up, () => setState(() {
            _camElevation = _originMode ? (_camElevation + 5).clamp(-90.0, 90.0) : (_camElevation + 5).clamp(-30.0, 90.0);
            _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.bottomCenter, Icons.keyboard_arrow_down, () => setState(() {
            _camElevation = _originMode ? (_camElevation - 5).clamp(-90.0, 90.0) : (_camElevation - 5).clamp(-30.0, 90.0);
            _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.centerLeft, Icons.keyboard_arrow_left, () => setState(() {
            _camAzimuth = _originMode ? (_camAzimuth - 15).clamp(-180.0, 180.0) : (_camAzimuth - 15) % 360;
            _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.centerRight, Icons.keyboard_arrow_right, () => setState(() {
            _camAzimuth = _originMode ? (_camAzimuth + 15).clamp(-180.0, 180.0) : (_camAzimuth + 15) % 360;
            _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor();
          })),
        ],
      ),
    );
  }

  Widget _buildAngleSliders() {
    final azMin = _originMode ? -180.0 : 0.0;
    final azMax = _originMode ? 180.0 : 360.0;
    final elMin = _originMode ? -90.0 : -30.0;
    final elMax = _originMode ? 90.0 : 90.0;
    final azLabel = _originMode ? '左右旋转' : '水平环绕';
    final elLabel = _originMode ? '上下倾斜' : '垂直俯仰';
    final azDisplay = _originMode
        ? '${_camAzimuth > 0 ? "右" : _camAzimuth < 0 ? "左" : ""}${_camAzimuth.abs().round()}°'
        : '${_camAzimuth.round()}°';
    final elDisplay = _originMode
        ? '${_camElevation > 0 ? "上" : _camElevation < 0 ? "下" : ""}${_camElevation.abs().round()}°'
        : '${_camElevation.round()}°';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _slider(azLabel, _camAzimuth, azMin, azMax, azDisplay, (v) =>
            setState(() { _camAzimuth = v; _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 16),
        _slider(elLabel, _camElevation, elMin, elMax, elDisplay, (v) =>
            setState(() { _camElevation = v; _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 16),
        _slider('景别缩放', _camDistance, 0, 10, _distToTextCN(_camDistance), (v) =>
            setState(() { _camDistance = v; _anglePreset = '自定义'; _angleEnabled = true; _syncPromptToEditor(); })),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // 灯光标签页（修复原点模式180度限位）
  // ══════════════════════════════════════════════════════════

  Widget _buildLightingTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Wrap(
              spacing: 8, runSpacing: 6,
              children: [
                ..._lightPresets.keys.map((name) {
                  final isActive = _lightPreset == name;
                  return InkWell(
                    onTap: () {
                      final v = _lightPresets[name];
                      setState(() {
                        _lightPreset = name; _lightEnabled = true;
                        if (v != null) {
                          _lightAzimuth = (v[0] as num).toDouble();
                          _lightElevation = (v[1] as num).toDouble();
                          _lightIntensity = (v[2] as num).toDouble();
                          _lightColorTemp = (v[3] as num).toDouble();
                          _lightType = v[4] as String;
                        }
                        _syncPromptToEditor();
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFFFD54F) : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(name, style: TextStyle(color: isActive ? Colors.black : Colors.white, fontSize: 11)),
                    ),
                  );
                }),
                // 重置按钮 — 同时恢复自动填充
                InkWell(
                  onTap: () => setState(() {
                    _lightAzimuth = 225; _lightElevation = 45; _lightIntensity = 5;
                    _lightColorTemp = 6; _lightType = '柔光';
                    _lightPreset = '自定义'; _lightEnabled = false;
                    _isUserEditing = false; // 恢复自动填充
                    _syncPromptToEditor();
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 12, color: Colors.white54),
                        SizedBox(width: 3),
                        Text('重置', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLightSphere(),
                const SizedBox(width: 20),
                Expanded(child: _buildLightSliders()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLightSphere() {
    return SizedBox(
      width: 240, height: 240,
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (d) => setState(() {
              if (_originMode) {
                _lightAzimuth = (_lightAzimuth + d.delta.dx * 0.8).clamp(-180.0, 180.0);
                _lightElevation = (_lightElevation - d.delta.dy * 0.5).clamp(-90.0, 90.0);
              } else {
                _lightAzimuth = (_lightAzimuth + d.delta.dx * 0.8) % 360;
                _lightElevation = (_lightElevation - d.delta.dy * 0.5).clamp(-30.0, 90.0);
              }
              _lightPreset = '自定义'; _lightEnabled = true;
              _syncPromptToEditor();
            }),
            child: CustomPaint(
              size: const Size(240, 240),
              painter: _LightCubeSpherePainter(
                azimuth: _lightAzimuth, elevation: _lightElevation,
                intensity: _lightIntensity, colorTemp: _lightColorTemp, refImage: _refImage,
              ),
            ),
          ),
          _arrowBtn(Alignment.topCenter, Icons.keyboard_arrow_up, () => setState(() {
            _lightElevation = _originMode ? (_lightElevation + 5).clamp(-90.0, 90.0) : (_lightElevation + 5).clamp(-30.0, 90.0);
            _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.bottomCenter, Icons.keyboard_arrow_down, () => setState(() {
            _lightElevation = _originMode ? (_lightElevation - 5).clamp(-90.0, 90.0) : (_lightElevation - 5).clamp(-30.0, 90.0);
            _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.centerLeft, Icons.keyboard_arrow_left, () => setState(() {
            _lightAzimuth = _originMode ? (_lightAzimuth - 15).clamp(-180.0, 180.0) : (_lightAzimuth - 15) % 360;
            _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor();
          })),
          _arrowBtn(Alignment.centerRight, Icons.keyboard_arrow_right, () => setState(() {
            _lightAzimuth = _originMode ? (_lightAzimuth + 15).clamp(-180.0, 180.0) : (_lightAzimuth + 15) % 360;
            _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor();
          })),
        ],
      ),
    );
  }

  Widget _buildLightSliders() {
    final azMin = _originMode ? -180.0 : 0.0;
    final azMax = _originMode ? 180.0 : 360.0;
    final elMin = _originMode ? -90.0 : -30.0;
    final elMax = _originMode ? 90.0 : 90.0;
    final azLabel = _originMode ? '左右偏移' : '灯光方位';
    final elLabel = _originMode ? '上下偏移' : '灯光高度';
    final azDisplay = _originMode
        ? '${_lightAzimuth > 0 ? "右" : _lightAzimuth < 0 ? "左" : ""}${_lightAzimuth.abs().round()}°'
        : '${_lightAzimuth.round()}°';
    final elDisplay = _originMode
        ? '${_lightElevation > 0 ? "上" : _lightElevation < 0 ? "下" : ""}${_lightElevation.abs().round()}°'
        : '${_lightElevation.round()}°';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _slider(azLabel, _lightAzimuth, azMin, azMax, azDisplay, (v) =>
            setState(() { _lightAzimuth = v; _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 10),
        _slider(elLabel, _lightElevation, elMin, elMax, elDisplay, (v) =>
            setState(() { _lightElevation = v; _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 10),
        _slider('灯光强度', _lightIntensity, 0, 10, _lightIntensCN(_lightIntensity), (v) =>
            setState(() { _lightIntensity = v; _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 10),
        _slider('灯光色温', _lightColorTemp, 0, 10, _lightTempCN(_lightColorTemp), (v) =>
            setState(() { _lightColorTemp = v; _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor(); })),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: 56, child: Text('类型', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
            ..._lightTypes.map((t) {
              final active = _lightType == t;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() { _lightType = t; _lightPreset = '自定义'; _lightEnabled = true; _syncPromptToEditor(); }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: active ? const Color(0xFFFFD54F) : const Color(0xFF333333), borderRadius: BorderRadius.circular(4)),
                    child: Text(t, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 11)),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }


  // ══════════════════════════════════════════════════════════
  // 裁切标签页
  // ══════════════════════════════════════════════════════════

  Widget _buildCropTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 比例选择栏
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                ..._cropRatios.keys.map((name) {
                  final isActive = _cropAspectRatio == name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() {
                        _cropAspectRatio = name;
                        _applyCropRatio();
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : const Color(0xFF333333),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(name, style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 11)),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() {
                    _cropRect = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
                    _cropAspectRatio = '自由';
                    _hasCrop = false;
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333), borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 12, color: Colors.white54),
                        SizedBox(width: 3),
                        Text('重置裁切', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 图片裁切区域
          Expanded(
            child: Center(
              child: _fullImage != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final imgW = _fullImageSize!.width;
                        final imgH = _fullImageSize!.height;
                        final scale = min(constraints.maxWidth / imgW, constraints.maxHeight / imgH);
                        final displayW = imgW * scale;
                        final displayH = imgH * scale;

                        return GestureDetector(
                          onTap: () => _showFullScreenCrop(context),
                          child: SizedBox(
                            width: displayW,
                            height: displayH,
                            child: Stack(
                              children: [
                                // 原图
                                Positioned.fill(
                                  child: RawImage(image: _fullImage, fit: BoxFit.contain),
                                ),
                                // 裁切遮罩
                                if (_hasCrop)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _CropOverlayPainter(cropRect: _cropRect),
                                    ),
                                  ),
                                // 提示文字
                                Positioned(
                                  bottom: 8, left: 0, right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _hasCrop ? '点击图片进入全屏裁切编辑' : '点击图片开始裁切',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : const Text('加载图片中...', style: TextStyle(color: Colors.white30, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  void _applyCropRatio() {
    final ratio = _cropRatios[_cropAspectRatio];
    if (ratio == null) {
      // 自由模式，不锁定
      _hasCrop = true;
      return;
    }
    _hasCrop = true;
    // 根据比例计算裁切框
    final imgRatio = (_fullImageSize?.width ?? 1) / (_fullImageSize?.height ?? 1);
    double cropW, cropH;
    if (ratio > imgRatio) {
      cropW = 0.8;
      cropH = cropW * imgRatio / ratio;
    } else {
      cropH = 0.8;
      cropW = cropH * ratio / imgRatio;
    }
    cropW = cropW.clamp(0.1, 0.95);
    cropH = cropH.clamp(0.1, 0.95);
    final cx = 0.5, cy = 0.5;
    _cropRect = Rect.fromCenter(center: Offset(cx, cy), width: cropW, height: cropH);
  }

  void _showFullScreenCrop(BuildContext context) {
    if (_fullImage == null) return;
    _hasCrop = true;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _FullScreenCropDialog(
        image: _fullImage!,
        imageSize: _fullImageSize!,
        initialCropRect: _cropRect,
        aspectRatio: _cropRatios[_cropAspectRatio],
        onCropChanged: (rect) {
          setState(() {
            _cropRect = rect;
            _hasCrop = true;
          });
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 通用组件
  // ══════════════════════════════════════════════════════════

  Widget _arrowBtn(Alignment align, IconData icon, VoidCallback onTap) {
    return Align(
      alignment: align,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white54, size: 24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      String display, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.2),
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 50, child: Text(display,
            style: const TextStyle(color: Colors.white, fontSize: 11), textAlign: TextAlign.right)),
      ],
    );
  }
}



// ══════════════════════════════════════════════════════════
// 全屏裁切对话框
// ══════════════════════════════════════════════════════════

class _FullScreenCropDialog extends StatefulWidget {
  final ui.Image image;
  final Size imageSize;
  final Rect initialCropRect;
  final double? aspectRatio;
  final ValueChanged<Rect> onCropChanged;

  const _FullScreenCropDialog({
    required this.image,
    required this.imageSize,
    required this.initialCropRect,
    this.aspectRatio,
    required this.onCropChanged,
  });

  @override
  State<_FullScreenCropDialog> createState() => _FullScreenCropDialogState();
}

class _FullScreenCropDialogState extends State<_FullScreenCropDialog> {
  late Rect _cropRect;
  String? _activeHandle; // tl, tr, bl, br, move

  @override
  void initState() {
    super.initState();
    _cropRect = widget.initialCropRect;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 顶部操作栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('裁切编辑', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onCropChanged(_cropRect);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('确认裁切', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          // 图片裁切区域
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imgW = widget.imageSize.width;
                final imgH = widget.imageSize.height;
                final scale = min(constraints.maxWidth / imgW, constraints.maxHeight / imgH);
                final displayW = imgW * scale;
                final displayH = imgH * scale;
                final offsetX = (constraints.maxWidth - displayW) / 2;
                final offsetY = (constraints.maxHeight - displayH) / 2;

                return GestureDetector(
                  onPanStart: (d) {
                    final local = d.localPosition;
                    final nx = (local.dx - offsetX) / displayW;
                    final ny = (local.dy - offsetY) / displayH;
                    _activeHandle = _hitTest(nx, ny);
                  },
                  onPanUpdate: (d) {
                    if (_activeHandle == null) return;
                    final dx = d.delta.dx / displayW;
                    final dy = d.delta.dy / displayH;
                    setState(() => _updateCrop(dx, dy));
                  },
                  onPanEnd: (_) => _activeHandle = null,
                  child: Stack(
                    children: [
                      // 原图
                      Positioned(
                        left: offsetX, top: offsetY,
                        width: displayW, height: displayH,
                        child: RawImage(image: widget.image, fit: BoxFit.contain),
                      ),
                      // 裁切遮罩 + 手柄
                      Positioned(
                        left: offsetX, top: offsetY,
                        width: displayW, height: displayH,
                        child: CustomPaint(
                          painter: _CropHandlePainter(cropRect: _cropRect),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _hitTest(double nx, double ny) {
    const hs = 0.04; // 手柄命中区域
    final r = _cropRect;
    if ((nx - r.left).abs() < hs && (ny - r.top).abs() < hs) return 'tl';
    if ((nx - r.right).abs() < hs && (ny - r.top).abs() < hs) return 'tr';
    if ((nx - r.left).abs() < hs && (ny - r.bottom).abs() < hs) return 'bl';
    if ((nx - r.right).abs() < hs && (ny - r.bottom).abs() < hs) return 'br';
    if (nx > r.left && nx < r.right && ny > r.top && ny < r.bottom) return 'move';
    return null;
  }

  void _updateCrop(double dx, double dy) {
    var r = _cropRect;
    switch (_activeHandle) {
      case 'tl':
        r = Rect.fromLTRB((r.left + dx).clamp(0.0, r.right - 0.05), (r.top + dy).clamp(0.0, r.bottom - 0.05), r.right, r.bottom);
        break;
      case 'tr':
        r = Rect.fromLTRB(r.left, (r.top + dy).clamp(0.0, r.bottom - 0.05), (r.right + dx).clamp(r.left + 0.05, 1.0), r.bottom);
        break;
      case 'bl':
        r = Rect.fromLTRB((r.left + dx).clamp(0.0, r.right - 0.05), r.top, r.right, (r.bottom + dy).clamp(r.top + 0.05, 1.0));
        break;
      case 'br':
        r = Rect.fromLTRB(r.left, r.top, (r.right + dx).clamp(r.left + 0.05, 1.0), (r.bottom + dy).clamp(r.top + 0.05, 1.0));
        break;
      case 'move':
        final w = r.width, h = r.height;
        var nl = (r.left + dx).clamp(0.0, 1.0 - w);
        var nt = (r.top + dy).clamp(0.0, 1.0 - h);
        r = Rect.fromLTWH(nl, nt, w, h);
        break;
    }
    // 锁定比例
    if (widget.aspectRatio != null && _activeHandle != 'move') {
      final ratio = widget.aspectRatio!;
      final imgRatio = widget.imageSize.width / widget.imageSize.height;
      final adjustedRatio = ratio / imgRatio;
      final cw = r.width;
      final ch = cw / adjustedRatio;
      if (_activeHandle == 'tl' || _activeHandle == 'bl') {
        r = Rect.fromLTRB(r.right - cw, _activeHandle == 'tl' ? r.bottom - ch : r.top, r.right, _activeHandle == 'tl' ? r.bottom : r.top + ch);
      } else {
        r = Rect.fromLTRB(r.left, _activeHandle == 'tr' ? r.bottom - ch : r.top, r.left + cw, _activeHandle == 'tr' ? r.bottom : r.top + ch);
      }
    }
    _cropRect = Rect.fromLTRB(
      r.left.clamp(0.0, 1.0), r.top.clamp(0.0, 1.0),
      r.right.clamp(0.0, 1.0), r.bottom.clamp(0.0, 1.0),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 裁切遮罩 Painter（缩略图用）
// ══════════════════════════════════════════════════════════

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(cropRect.left * size.width, cropRect.top * size.height,
        cropRect.right * size.width, cropRect.bottom * size.height);
    // 半透明遮罩
    final maskPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropPath = Path()..addRect(r);
    final combinedPath = Path.combine(PathOperation.difference, maskPath, cropPath);
    canvas.drawPath(combinedPath, Paint()..color = Colors.black.withOpacity(0.5));
    // 裁切框边框
    canvas.drawRect(r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // 三分线
    for (int i = 1; i <= 2; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), Paint()..color = Colors.white30..strokeWidth = 0.5);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), Paint()..color = Colors.white30..strokeWidth = 0.5);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter o) => cropRect != o.cropRect;
}

// ══════════════════════════════════════════════════════════
// 裁切手柄 Painter（全屏用）
// ══════════════════════════════════════════════════════════

class _CropHandlePainter extends CustomPainter {
  final Rect cropRect;
  _CropHandlePainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(cropRect.left * size.width, cropRect.top * size.height,
        cropRect.right * size.width, cropRect.bottom * size.height);
    // 半透明遮罩
    final maskPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropPath = Path()..addRect(r);
    final combinedPath = Path.combine(PathOperation.difference, maskPath, cropPath);
    canvas.drawPath(combinedPath, Paint()..color = Colors.black.withOpacity(0.6));
    // 裁切框边框
    canvas.drawRect(r, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    // 三分线
    for (int i = 1; i <= 2; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), Paint()..color = Colors.white38..strokeWidth = 0.8);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), Paint()..color = Colors.white38..strokeWidth = 0.8);
    }
    // 四角手柄
    const hs = 12.0;
    const hw = 3.0;
    final hp = Paint()..color = Colors.white..strokeWidth = hw..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    // 左上
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + hs, r.top), hp);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left, r.top + hs), hp);
    // 右上
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right - hs, r.top), hp);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + hs), hp);
    // 左下
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + hs, r.bottom), hp);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left, r.bottom - hs), hp);
    // 右下
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right - hs, r.bottom), hp);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - hs), hp);
  }

  @override
  bool shouldRepaint(covariant _CropHandlePainter o) => cropRect != o.cropRect;
}


// ══════════════════════════════════════════════════════════
// CustomPainter: 相机角度球体（围绕球体表面）
// ══════════════════════════════════════════════════════════

class _CameraSpherePainter extends CustomPainter {
  final double azimuth, elevation, distance;
  final ui.Image? refImage;

  _CameraSpherePainter({required this.azimuth, required this.elevation, required this.distance, this.refImage});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF2a2a2a));

    // 经纬线
    final lp = Paint()..color = Colors.white.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    _ellipse(canvas, c, r, r * 0.3, 0, lp);
    for (int i = 0; i < 8; i++) _ellipse(canvas, c, r * cos(i * pi / 8), r, pi / 2, lp);
    for (int i = 1; i <= 3; i++) {
      final lat = i * pi / 8; final cr = r * cos(lat); final y = r * sin(lat);
      _ellipse(canvas, c + Offset(0, -y), cr, cr * 0.3, 0, lp);
      if (i <= 2) _ellipse(canvas, c + Offset(0, y), cr, cr * 0.3, 0, lp);
    }
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 1.2);

    // 参考图（球体中心）
    final imgS = 44.0 + (10 - distance) * 3;
    final imgR = Rect.fromCenter(center: c, width: imgS, height: imgS);
    if (refImage != null) {
      canvas.save(); canvas.clipPath(Path()..addOval(imgR));
      paintImage(canvas: canvas, rect: imgR, image: refImage!, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
      canvas.restore();
      canvas.drawOval(imgR, Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }

    // 摄像机位置 — 始终在球体表面
    final azR = azimuth * pi / 180;
    final elR = elevation * pi / 180;
    final camPosX = c.dx + r * cos(elR) * sin(azR);
    final camPosY = c.dy - r * sin(elR);

    // 起点标记
    final startX = c.dx;
    final startY = c.dy;
    canvas.drawCircle(Offset(startX, startY + r * 0.02), 4, Paint()..color = const Color(0xFF4CAF50).withOpacity(0.6));

    // 轨迹弧线
    final hasMovement = azimuth.abs() > 1 || elevation.abs() > 1;
    if (hasMovement) {
      final trackPath = Path();
      const steps = 40;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final curAz = azimuth * t * pi / 180;
        final curEl = elevation * t * pi / 180;
        final px = c.dx + r * cos(curEl) * sin(curAz);
        final py = c.dy - r * sin(curEl);
        if (i == 0) { trackPath.moveTo(px, py); } else { trackPath.lineTo(px, py); }
      }
      final trackPaint = Paint()
        ..style = PaintingStyle.stroke..strokeWidth = 2.5
        ..shader = ui.Gradient.linear(Offset(startX, startY), Offset(camPosX, camPosY),
          [const Color(0xFF4CAF50), const Color(0xFFFF6B6B)]);
      canvas.drawPath(trackPath, trackPaint);
      canvas.drawPath(trackPath, Paint()..style = PaintingStyle.stroke..strokeWidth = 6
        ..color = const Color(0xFFFF6B6B).withOpacity(0.08)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // 连线
    canvas.drawLine(Offset(camPosX, camPosY), c,
        Paint()..color = const Color(0xFFFF6B6B).withOpacity(0.25)..strokeWidth = 1..style = PaintingStyle.stroke);

    // 摄像机图标
    canvas.save();
    canvas.translate(camPosX, camPosY);
    final toCenterAngle = atan2(c.dy - camPosY, c.dx - camPosX);
    canvas.rotate(toCenterAngle);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-7, -5, 14, 10), const Radius.circular(2)),
        Paint()..color = const Color(0xFFFF6B6B).withOpacity(0.85));
    canvas.drawPath(Path()..moveTo(7, -4)..lineTo(12, -6)..lineTo(12, 6)..lineTo(7, 4)..close(), Paint()..color = const Color(0xFFFF8A80));
    canvas.drawCircle(const Offset(-4, -6), 2.5, Paint()..color = const Color(0xFFFF8A80));
    canvas.drawRect(const Rect.fromLTWH(-3, -3, 6, 6), Paint()..color = const Color(0xFF64B5F6).withOpacity(0.6));
    canvas.drawCircle(Offset.zero, 14, Paint()..color = const Color(0xFFFF6B6B).withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.restore();

    // 角度文字
    final tp = TextPainter(text: TextSpan(text: '${azimuth.round()}° / ${elevation.round()}°',
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)), textDirection: TextDirection.ltr);
    tp.layout(); tp.paint(canvas, Offset(size.width - tp.width - 8, size.height - 18));
  }

  void _ellipse(Canvas canvas, Offset c, double rx, double ry, double rot, Paint p) {
    canvas.save(); canvas.translate(c.dx, c.dy); canvas.rotate(rot);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CameraSpherePainter o) =>
      azimuth != o.azimuth || elevation != o.elevation || distance != o.distance || refImage != o.refImage;
}


// ══════════════════════════════════════════════════════════
// CustomPainter: 灯光+立方体球体（围绕球体表面）
// ══════════════════════════════════════════════════════════

class _LightCubeSpherePainter extends CustomPainter {
  final double azimuth, elevation, intensity, colorTemp;
  final ui.Image? refImage;

  _LightCubeSpherePainter({required this.azimuth, required this.elevation,
      required this.intensity, required this.colorTemp, this.refImage});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.40;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF1e1e1e));

    final azR = azimuth * pi / 180; final elR = elevation * pi / 180;
    final lx = cos(elR) * sin(azR); final ly = -sin(elR); final lz = cos(elR) * cos(azR);
    final lColor = _tempColor(colorTemp);
    final iFactor = intensity / 10.0;

    // 立方体
    _drawCube(canvas, c, r * 0.45, lx, ly, lz, lColor, iFactor);

    // 经纬线
    final lp = Paint()..color = Colors.white.withOpacity(0.08)..style = PaintingStyle.stroke..strokeWidth = 0.6;
    _ellipse(canvas, c, r, r * 0.25, 0, lp);
    for (int i = 0; i < 6; i++) _ellipse(canvas, c, r * cos(i * pi / 6), r, pi / 2, lp);
    for (int i = 1; i <= 2; i++) {
      final lat = i * pi / 6; final cr = r * cos(lat); final y = r * sin(lat);
      _ellipse(canvas, c + Offset(0, -y), cr, cr * 0.25, 0, lp);
      _ellipse(canvas, c + Offset(0, y), cr, cr * 0.25, 0, lp);
    }
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 1.0);

    // 参考图
    if (refImage != null) {
      const imgS = 40.0;
      final imgR = Rect.fromCenter(center: c, width: imgS, height: imgS);
      canvas.save(); canvas.clipPath(Path()..addOval(imgR));
      paintImage(canvas: canvas, rect: imgR, image: refImage!, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
      canvas.restore();
      canvas.drawOval(imgR, Paint()..color = Colors.white.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 1.0);
    }

    // 灯光位置
    final lightPosX = c.dx + r * cos(elR) * sin(azR);
    final lightPosY = c.dy - r * sin(elR);

    // 起点标记
    canvas.drawCircle(Offset(c.dx, c.dy), 4, Paint()..color = const Color(0xFFFFD54F).withOpacity(0.5));

    // 轨迹弧线
    final hasMovement = azimuth.abs() > 1 || elevation.abs() > 1;
    if (hasMovement) {
      final trackPath = Path();
      const steps = 40;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final curAz = azimuth * t * pi / 180;
        final curEl = elevation * t * pi / 180;
        final px = c.dx + r * cos(curEl) * sin(curAz);
        final py = c.dy - r * sin(curEl);
        if (i == 0) { trackPath.moveTo(px, py); } else { trackPath.lineTo(px, py); }
      }
      final trackPaint = Paint()
        ..style = PaintingStyle.stroke..strokeWidth = 2.5
        ..shader = ui.Gradient.linear(c, Offset(lightPosX, lightPosY), [const Color(0xFF81C784), lColor]);
      canvas.drawPath(trackPath, trackPaint);
      canvas.drawPath(trackPath, Paint()..style = PaintingStyle.stroke..strokeWidth = 6
        ..color = lColor.withOpacity(0.08)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // 光线
    final rayP = Paint()
      ..shader = ui.Gradient.linear(Offset(lightPosX, lightPosY), c,
          [lColor.withOpacity(0.5 * iFactor), lColor.withOpacity(0.05)])
      ..strokeWidth = 2.0..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(lightPosX, lightPosY), c, rayP);

    // 散射光线
    final dx = c.dx - lightPosX; final dy = c.dy - lightPosY;
    final len = sqrt(dx * dx + dy * dy);
    if (len > 1) {
      final px = -dy / len * 6; final py = dx / len * 6;
      final sp = Paint()..color = lColor.withOpacity(0.06 * iFactor)..strokeWidth = 1.0;
      canvas.drawLine(Offset(lightPosX + px, lightPosY + py), Offset(c.dx + px * 0.3, c.dy + py * 0.3), sp);
      canvas.drawLine(Offset(lightPosX - px, lightPosY - py), Offset(c.dx - px * 0.3, c.dy - py * 0.3), sp);
    }

    // 灯泡图标
    canvas.save();
    canvas.translate(lightPosX, lightPosY);
    final lightAngle = atan2(c.dy - lightPosY, c.dx - lightPosX);
    canvas.rotate(lightAngle);
    canvas.drawCircle(Offset.zero, 16, Paint()..color = lColor.withOpacity(0.15 * iFactor)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(const Offset(3, 0), 6, Paint()..color = lColor.withOpacity(0.9));
    canvas.drawPath(Path()..moveTo(-2, -4)..lineTo(-6, -3)..lineTo(-6, 3)..lineTo(-2, 4)..close(), Paint()..color = Colors.white.withOpacity(0.6));
    canvas.drawLine(const Offset(-6, -1), const Offset(-8, -1), Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1);
    canvas.drawLine(const Offset(-6, 1), const Offset(-8, 1), Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1);
    canvas.drawCircle(Offset.zero, 12, Paint()..color = lColor.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.restore();

    // 角度文字
    final tp = TextPainter(text: TextSpan(text: '${azimuth.round()}° / ${elevation.round()}°',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)), textDirection: TextDirection.ltr);
    tp.layout(); tp.paint(canvas, Offset(size.width - tp.width - 8, size.height - 18));
  }

  void _drawCube(Canvas canvas, Offset c, double s, double lx, double ly, double lz, Color lColor, double iFactor) {
    final h = s / 2;
    final verts = [[-h,-h,-h],[h,-h,-h],[h,h,-h],[-h,h,-h],[-h,-h,h],[h,-h,h],[h,h,h],[-h,h,h]];
    const rX = 0.45, rY = 0.65;

    List<Offset> proj = [];
    for (final v in verts) {
      double x = v[0], y = v[1], z = v[2];
      double x1 = x * cos(rY) - z * sin(rY); double z1 = x * sin(rY) + z * cos(rY);
      double y1 = y * cos(rX) - z1 * sin(rX); double z2 = y * sin(rX) + z1 * cos(rX);
      final sc = 1.0 + z2 / (s * 4);
      proj.add(Offset(c.dx + x1 * sc, c.dy - y1 * sc));
    }

    final faces = [
      [[0,1,2,3], 0.0, 0.0, -1.0], [[5,4,7,6], 0.0, 0.0, 1.0],
      [[4,0,3,7], -1.0, 0.0, 0.0], [[1,5,6,2], 1.0, 0.0, 0.0],
      [[3,2,6,7], 0.0, 1.0, 0.0], [[0,4,5,1], 0.0, -1.0, 0.0],
    ];

    List<Map<String, dynamic>> toDraw = [];
    for (final f in faces) {
      final idx = f[0] as List<int>;
      double nx = f[1] as double, ny = f[2] as double, nz = f[3] as double;
      double nx1 = nx * cos(rY) - nz * sin(rY); double nz1 = nx * sin(rY) + nz * cos(rY);
      double ny1 = ny * cos(rX) - nz1 * sin(rX); double nz2 = ny * sin(rX) + nz1 * cos(rX);
      if (nz2 > -0.1) {
        double dot = (nx1 * lx + ny1 * (-ly) + nz2 * lz).clamp(0.0, 1.0);
        final b = (0.15 + dot * iFactor * 0.85).clamp(0.0, 1.0);
        final fc = Color.lerp(const Color(0xFF2a2a2a), lColor, b)!;
        double avgZ = 0;
        for (final i in idx) { final v = verts[i]; avgZ += v[1] * sin(rX) + (v[0] * sin(rY) + v[2] * cos(rY)) * cos(rX); }
        avgZ /= idx.length;
        toDraw.add({'idx': idx, 'color': fc, 'b': b, 'z': avgZ});
      }
    }
    toDraw.sort((a, b) => (b['z'] as double).compareTo(a['z'] as double));

    for (final f in toDraw) {
      final idx = f['idx'] as List<int>; final color = f['color'] as Color; final b = f['b'] as double;
      final path = Path()..moveTo(proj[idx[0]].dx, proj[idx[0]].dy);
      for (int i = 1; i < idx.length; i++) path.lineTo(proj[idx[i]].dx, proj[idx[i]].dy);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.1 + b * 0.2)..style = PaintingStyle.stroke..strokeWidth = 0.8);
    }
  }

  Color _tempColor(double t) {
    if (t <= 2) return const Color(0xFF6BB8FF);
    if (t <= 4) return const Color(0xFFB8D8FF);
    if (t <= 6) return const Color(0xFFFFF8E8);
    if (t <= 8) return const Color(0xFFFFD54F);
    return const Color(0xFFFFAB40);
  }

  void _ellipse(Canvas canvas, Offset c, double rx, double ry, double rot, Paint p) {
    canvas.save(); canvas.translate(c.dx, c.dy); canvas.rotate(rot);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LightCubeSpherePainter o) =>
      azimuth != o.azimuth || elevation != o.elevation || intensity != o.intensity || colorTemp != o.colorTemp || refImage != o.refImage;
}
