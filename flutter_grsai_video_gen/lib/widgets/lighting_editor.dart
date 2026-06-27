import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// 3D灯光编辑器
/// 灯光方位 azimuth: 0°~360°
/// 灯光高度 elevation: -30°~90°
/// 灯光强度 intensity: 0~10
/// 灯光色温 colorTemp: 0~10 (冷光→暖光)
class LightingEditor extends StatefulWidget {
  final String imagePath;

  /// 点击"提交生成"：直接生成
  final void Function(String prompt, String imagePath) onGenerate;

  /// 点击"返回输入"：把 prompt 填回输入框
  final void Function(String prompt, String imagePath)? onReturnToInput;

  const LightingEditor({
    super.key,
    required this.imagePath,
    required this.onGenerate,
    this.onReturnToInput,
  });

  @override
  State<LightingEditor> createState() => _LightingEditorState();
}

class _LightingEditorState extends State<LightingEditor> {
  double _azimuth = 225; // 默认左上方
  double _elevation = 45; // 默认45°高
  double _intensity = 5; // 中等强度
  double _colorTemp = 6; // 偏暖
  String _lightType = '柔光';
  bool _showPrompt = false;
  String _activePreset = '主光源';

  ui.Image? _refImage;

  static const _lightTypes = ['柔光', '硬光', '漫射光', '聚光'];

  static const _presets = {
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

  @override
  void initState() {
    super.initState();
    _loadRefImage();
  }

  Future<void> _loadRefImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 120,
        targetHeight: 120,
      );
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _refImage = frame.image);
    } catch (_) {}
  }

  // ── 提示词生成 ──

  String get _promptText {
    final dir = _directionToText(_azimuth, _elevation);
    final intens = _intensityToText(_intensity);
    final temp = _colorTempToText(_colorTemp);
    final type = _lightTypeToText(_lightType);
    return 'Relight the image with: $type $temp light $dir, $intens';
  }

  String get _promptTextCN {
    final dir = _directionToTextCN(_azimuth, _elevation);
    final intens = _intensityToTextCN(_intensity);
    final temp = _colorTempToTextCN(_colorTemp);
    return '重新打光：$dir，$_lightType，$temp，$intens';
  }

  String _directionToText(double az, double el) {
    az = az % 360;
    String hDir;
    if (az < 22.5 || az >= 337.5) {
      hDir = 'from front';
    } else if (az < 67.5) {
      hDir = 'from front-left at ${az.round()}°';
    } else if (az < 112.5) {
      hDir = 'from left at ${az.round()}°';
    } else if (az < 157.5) {
      hDir = 'from back-left at ${az.round()}°';
    } else if (az < 202.5) {
      hDir = 'from behind';
    } else if (az < 247.5) {
      hDir = 'from back-right at ${az.round()}°';
    } else if (az < 292.5) {
      hDir = 'from right at ${az.round()}°';
    } else {
      hDir = 'from front-right at ${az.round()}°';
    }

    String vDir;
    if (el > 75) {
      vDir = 'directly above';
    } else if (el > 45) {
      vDir = 'high angle ${el.round()}°';
    } else if (el > 15) {
      vDir = 'upper ${el.round()}°';
    } else if (el > -10) {
      vDir = 'eye level ${el.round()}°';
    } else {
      vDir = 'below ${el.round()}°';
    }

    return '$hDir, $vDir';
  }

  String _directionToTextCN(double az, double el) {
    az = az % 360;
    String hDir;
    if (az < 22.5 || az >= 337.5) {
      hDir = '正前方';
    } else if (az < 67.5) {
      hDir = '左前方${az.round()}°';
    } else if (az < 112.5) {
      hDir = '左侧${az.round()}°';
    } else if (az < 157.5) {
      hDir = '左后方${az.round()}°';
    } else if (az < 202.5) {
      hDir = '正后方';
    } else if (az < 247.5) {
      hDir = '右后方${az.round()}°';
    } else if (az < 292.5) {
      hDir = '右侧${az.round()}°';
    } else {
      hDir = '右前方${az.round()}°';
    }

    String vDir;
    if (el > 75) {
      vDir = '正上方';
    } else if (el > 45) {
      vDir = '高角度${el.round()}°';
    } else if (el > 15) {
      vDir = '上方${el.round()}°';
    } else if (el > -10) {
      vDir = '平射${el.round()}°';
    } else {
      vDir = '下方${el.round()}°';
    }

    return '$hDir $vDir';
  }

  String _intensityToText(double v) {
    if (v <= 2) return 'subtle intensity';
    if (v <= 4) return 'gentle intensity';
    if (v <= 6) return 'medium intensity';
    if (v <= 8) return 'strong intensity';
    return 'dramatic intensity';
  }

  String _intensityToTextCN(double v) {
    if (v <= 2) return '微弱';
    if (v <= 4) return '柔和';
    if (v <= 6) return '中等';
    if (v <= 8) return '强烈';
    return '极强';
  }

  String _colorTempToText(double v) {
    if (v <= 2) return 'cool blue';
    if (v <= 4) return 'cool neutral';
    if (v <= 6) return 'neutral warm';
    if (v <= 8) return 'warm golden';
    return 'deep warm orange';
  }

  String _colorTempToTextCN(double v) {
    if (v <= 2) return '冷蓝光';
    if (v <= 4) return '冷白光';
    if (v <= 6) return '自然光';
    if (v <= 8) return '暖金光';
    return '暖橙光';
  }

  String _lightTypeToText(String type) {
    switch (type) {
      case '柔光':
        return 'soft';
      case '硬光':
        return 'hard';
      case '漫射光':
        return 'diffused';
      case '聚光':
        return 'spotlight';
      default:
        return 'soft';
    }
  }

  void _applyPreset(String name) {
    final values = _presets[name];
    setState(() {
      _activePreset = name;
      if (values != null) {
        _azimuth = (values[0] as num).toDouble();
        _elevation = (values[1] as num).toDouble();
        _intensity = (values[2] as num).toDouble();
        _colorTemp = (values[3] as num).toDouble();
        _lightType = values[4] as String;
      }
    });
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a1a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 780,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.light_mode, color: Color(0xFFFFD54F), size: 20),
                  const SizedBox(width: 8),
                  const Text('3D灯光编辑器',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // 预设按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _presets.keys.map((name) {
                  final isActive = _activePreset == name;
                  return InkWell(
                    onTap: () => _applyPreset(name),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFFFD54F)
                            : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(name,
                          style: TextStyle(
                            color: isActive ? Colors.black : Colors.white,
                            fontSize: 12,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ),
            // 主体：球体+立方体 + 控制面板
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSphereArea(),
                  const SizedBox(width: 24),
                  Expanded(child: _buildControlPanel()),
                ],
              ),
            ),
            // 提示词预览
            if (_showPrompt)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2a2a2a),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_promptTextCN,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(_promptText,
                        style: const TextStyle(
                            color: Color(0xFFFFD54F), fontSize: 11)),
                  ],
                ),
              ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onReturnToInput != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.onReturnToInput!(
                            _promptText, widget.imagePath);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.edit_outlined,
                          size: 16, color: Colors.white70),
                      label: const Text('返回输入',
                          style: TextStyle(color: Colors.white70)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.onGenerate(_promptText, widget.imagePath);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.auto_awesome,
                        size: 16, color: Colors.black87),
                    label: const Text('提交生成',
                        style: TextStyle(color: Colors.black87)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
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

  Widget _buildSphereArea() {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _azimuth = (_azimuth + details.delta.dx * 0.8) % 360;
                _elevation =
                    (_elevation - details.delta.dy * 0.5).clamp(-30.0, 90.0);
                _activePreset = '自定义';
              });
            },
            child: CustomPaint(
              size: const Size(300, 300),
              painter: _LightingSpherePainter(
                azimuth: _azimuth,
                elevation: _elevation,
                intensity: _intensity,
                colorTemp: _colorTemp,
                refImage: _refImage,
              ),
            ),
          ),
          // 方向微调箭头
          Positioned(
            top: 0, left: 0, right: 0,
            child: Center(
              child: IconButton(
                onPressed: () => setState(() {
                  _elevation = (_elevation + 5).clamp(-30.0, 90.0);
                  _activePreset = '自定义';
                }),
                icon: const Icon(Icons.keyboard_arrow_up,
                    color: Colors.white54, size: 28),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Center(
              child: IconButton(
                onPressed: () => setState(() {
                  _elevation = (_elevation - 5).clamp(-30.0, 90.0);
                  _activePreset = '自定义';
                }),
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white54, size: 28),
              ),
            ),
          ),
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Center(
              child: IconButton(
                onPressed: () => setState(() {
                  _azimuth = (_azimuth - 15) % 360;
                  _activePreset = '自定义';
                }),
                icon: const Icon(Icons.keyboard_arrow_left,
                    color: Colors.white54, size: 28),
              ),
            ),
          ),
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: Center(
              child: IconButton(
                onPressed: () => setState(() {
                  _azimuth = (_azimuth + 15) % 360;
                  _activePreset = '自定义';
                }),
                icon: const Icon(Icons.keyboard_arrow_right,
                    color: Colors.white54, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSliderRow('灯光方位', _azimuth, 0, 360, '${_azimuth.round()}°',
            (v) {
          setState(() {
            _azimuth = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 14),
        _buildSliderRow(
            '灯光高度', _elevation, -30, 90, '${_elevation.round()}°', (v) {
          setState(() {
            _elevation = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 14),
        _buildSliderRow(
            '灯光强度', _intensity, 0, 10, _intensityToTextCN(_intensity),
            (v) {
          setState(() {
            _intensity = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 14),
        _buildSliderRow(
            '灯光色温', _colorTemp, 0, 10, _colorTempToTextCN(_colorTemp),
            (v) {
          setState(() {
            _colorTemp = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 14),
        // 灯光类型下拉
        Row(
          children: [
            const SizedBox(
                width: 60,
                child: Text('灯光类型',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            ...(_lightTypes.map((type) {
              final isActive = _lightType == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() {
                    _lightType = type;
                    _activePreset = '自定义';
                  }),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFFFD54F)
                          : const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(type,
                        style: TextStyle(
                          color: isActive ? Colors.black : Colors.white,
                          fontSize: 12,
                        )),
                  ),
                ),
              );
            })),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('提示词',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Switch(
              value: _showPrompt,
              onChanged: (v) => setState(() => _showPrompt = v),
              activeColor: const Color(0xFFFFD54F),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      String display, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFFFFD54F),
              inactiveTrackColor: Colors.white24,
              thumbColor: const Color(0xFFFFD54F),
              overlayColor: const Color(0xFFFFD54F).withOpacity(0.2),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child:
                Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
            width: 60,
            child: Text(display,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.right)),
      ],
    );
  }
}


/// 3D灯光球体绘制器 — 球体内含透视立方体，灯光照射时各面明暗实时变化
class _LightingSpherePainter extends CustomPainter {
  final double azimuth;
  final double elevation;
  final double intensity;
  final double colorTemp;
  final ui.Image? refImage;

  _LightingSpherePainter({
    required this.azimuth,
    required this.elevation,
    required this.intensity,
    required this.colorTemp,
    this.refImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.40;

    // 背景
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF1e1e1e));

    // 灯光方向向量（归一化）
    final azRad = azimuth * pi / 180;
    final elRad = elevation * pi / 180;
    final lightDirX = cos(elRad) * sin(azRad);
    final lightDirY = -sin(elRad);
    final lightDirZ = cos(elRad) * cos(azRad);

    // 灯光颜色（根据色温）
    final lightColor = _colorTempToColor(colorTemp);
    final intensityFactor = intensity / 10.0;

    // ── 绘制透视立方体 ──
    _drawLitCube(canvas, center, radius * 0.45, lightDirX, lightDirY, lightDirZ,
        lightColor, intensityFactor);

    // ── 绘制球体经纬线（半透明覆盖） ──
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    // 赤道线
    _drawEllipse(canvas, center, radius, radius * 0.25, 0, linePaint);
    // 经线
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 6;
      _drawEllipse(
          canvas, center, radius * cos(angle), radius, pi / 2, linePaint);
    }
    // 纬线
    for (int i = 1; i <= 2; i++) {
      final lat = i * pi / 6;
      final r = radius * cos(lat);
      final y = radius * sin(lat);
      _drawEllipse(
          canvas, center + Offset(0, -y), r, r * 0.25, 0, linePaint);
      _drawEllipse(
          canvas, center + Offset(0, y), r, r * 0.25, 0, linePaint);
    }

    // 外圆
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white.withOpacity(0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // ── 中心参考图（小圆形） ──
    if (refImage != null) {
      final imgSize = 40.0;
      final imgRect =
          Rect.fromCenter(center: center, width: imgSize, height: imgSize);
      canvas.save();
      canvas.clipPath(Path()..addOval(imgRect));
      paintImage(
        canvas: canvas,
        rect: imgRect,
        image: refImage!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
      canvas.drawOval(
          imgRect,
          Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
    }

    // ── 灯光指示器 ──
    final lightX = center.dx + radius * 0.75 * cos(elRad) * sin(azRad);
    final lightY = center.dy - radius * 0.75 * sin(elRad);

    // 灯光到中心的连线（光线）
    _drawLightRay(canvas, Offset(lightX, lightY), center, lightColor, intensityFactor);

    // 灯光点（发光效果）
    // 外圈光晕
    canvas.drawCircle(
        Offset(lightX, lightY),
        14,
        Paint()
          ..color = lightColor.withOpacity(0.15 * intensityFactor)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(
        Offset(lightX, lightY),
        8,
        Paint()
          ..color = lightColor.withOpacity(0.3 * intensityFactor)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // 实心灯光点
    canvas.drawCircle(
        Offset(lightX, lightY), 5, Paint()..color = lightColor);
    // 灯光图标
    final iconPainter = TextPainter(
      text: const TextSpan(text: '💡', style: TextStyle(fontSize: 10)),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas,
        Offset(lightX - iconPainter.width / 2, lightY - 20));

    // ── 角度标注 ──
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${azimuth.round()}° / ${elevation.round()}°',
        style:
            TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas,
        Offset(size.width - textPainter.width - 8, size.height - 18));
  }

  /// 绘制带光照的透视立方体
  void _drawLitCube(Canvas canvas, Offset center, double cubeSize,
      double lx, double ly, double lz, Color lightColor, double intensityFactor) {
    // 简单等轴测透视：将3D坐标投影到2D
    // 立方体8个顶点（中心在原点，边长=cubeSize）
    final half = cubeSize / 2;

    // 3D顶点 [x, y, z]
    final vertices3D = [
      [-half, -half, -half], // 0: 前左下
      [half, -half, -half],  // 1: 前右下
      [half, half, -half],   // 2: 前右上
      [-half, half, -half],  // 3: 前左上
      [-half, -half, half],  // 4: 后左下
      [half, -half, half],   // 5: 后右下
      [half, half, half],    // 6: 后右上
      [-half, half, half],   // 7: 后左上
    ];

    // 等轴测投影（带轻微旋转让立方体有立体感）
    const rotX = 0.45; // 绕X轴旋转角度
    const rotY = 0.65; // 绕Y轴旋转角度

    List<Offset> projected = [];
    for (final v in vertices3D) {
      double x = v[0], y = v[1], z = v[2];

      // 绕Y轴旋转
      double x1 = x * cos(rotY) - z * sin(rotY);
      double z1 = x * sin(rotY) + z * cos(rotY);

      // 绕X轴旋转
      double y1 = y * cos(rotX) - z1 * sin(rotX);
      double z2 = y * sin(rotX) + z1 * cos(rotX);

      // 简单透视投影
      final scale = 1.0 + z2 / (cubeSize * 4);
      projected.add(Offset(
        center.dx + x1 * scale,
        center.dy - y1 * scale,
      ));
    }

    // 6个面的定义 [顶点索引, 法线方向]
    // 法线也需要经过同样的旋转
    final faces = [
      // [顶点索引列表, 原始法线 nx, ny, nz]
      [[0, 1, 2, 3], 0.0, 0.0, -1.0],  // 前面 (z-)
      [[5, 4, 7, 6], 0.0, 0.0, 1.0],   // 后面 (z+)
      [[4, 0, 3, 7], -1.0, 0.0, 0.0],  // 左面 (x-)
      [[1, 5, 6, 2], 1.0, 0.0, 0.0],   // 右面 (x+)
      [[3, 2, 6, 7], 0.0, 1.0, 0.0],   // 顶面 (y+)
      [[0, 4, 5, 1], 0.0, -1.0, 0.0],  // 底面 (y-)
    ];

    // 计算每个面的光照强度并排序（画家算法：先画远的面）
    List<Map<String, dynamic>> facesToDraw = [];

    for (final face in faces) {
      final indices = face[0] as List<int>;
      double nx = face[1] as double;
      double ny = face[2] as double;
      double nz = face[3] as double;

      // 旋转法线
      double nx1 = nx * cos(rotY) - nz * sin(rotY);
      double nz1 = nx * sin(rotY) + nz * cos(rotY);
      double ny1 = ny * cos(rotX) - nz1 * sin(rotX);
      double nz2 = ny * sin(rotX) + nz1 * cos(rotX);

      // 背面剔除：法线z分量 > 0 的面朝向观察者
      if (nz2 > -0.1) {
        // 计算光照：法线与灯光方向的点积
        double dot = nx1 * lx + ny1 * (-ly) + nz2 * lz;
        dot = dot.clamp(0.0, 1.0);

        // 环境光 + 漫反射
        final ambient = 0.15;
        final diffuse = dot * intensityFactor * 0.85;
        final brightness = (ambient + diffuse).clamp(0.0, 1.0);

        // 混合灯光颜色
        final faceColor = Color.lerp(
          const Color(0xFF2a2a2a),
          lightColor,
          brightness,
        )!;

        // 计算面的平均深度（用于排序）
        double avgZ = 0;
        for (final idx in indices) {
          final v = vertices3D[idx];
          double z = v[2];
          double z1r = v[0] * sin(rotY) + z * cos(rotY);
          avgZ += v[1] * sin(rotX) + z1r * cos(rotX);
        }
        avgZ /= indices.length;

        facesToDraw.add({
          'indices': indices,
          'color': faceColor,
          'brightness': brightness,
          'depth': avgZ,
        });
      }
    }

    // 按深度排序（远的先画）
    facesToDraw.sort((a, b) => (b['depth'] as double).compareTo(a['depth'] as double));

    // 绘制面
    for (final face in facesToDraw) {
      final indices = face['indices'] as List<int>;
      final color = face['color'] as Color;
      final brightness = face['brightness'] as double;

      final path = Path();
      path.moveTo(projected[indices[0]].dx, projected[indices[0]].dy);
      for (int i = 1; i < indices.length; i++) {
        path.lineTo(projected[indices[i]].dx, projected[indices[i]].dy);
      }
      path.close();

      // 填充
      canvas.drawPath(path, Paint()..color = color);

      // 边框
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(0.1 + brightness * 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }
  }

  /// 绘制灯光射线（从灯光点到中心，带渐变）
  void _drawLightRay(Canvas canvas, Offset from, Offset to,
      Color lightColor, double intensityFactor) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        from,
        to,
        [
          lightColor.withOpacity(0.5 * intensityFactor),
          lightColor.withOpacity(0.05),
        ],
      )
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);

    // 额外画几条散射光线
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    final perpX = -dy / len * 8;
    final perpY = dx / len * 8;

    final scatterPaint = Paint()
      ..color = lightColor.withOpacity(0.08 * intensityFactor)
      ..strokeWidth = 1.0;

    canvas.drawLine(
        Offset(from.dx + perpX, from.dy + perpY),
        Offset(to.dx + perpX * 0.3, to.dy + perpY * 0.3),
        scatterPaint);
    canvas.drawLine(
        Offset(from.dx - perpX, from.dy - perpY),
        Offset(to.dx - perpX * 0.3, to.dy - perpY * 0.3),
        scatterPaint);
  }

  /// 色温值映射到颜色
  Color _colorTempToColor(double temp) {
    // 0=冷蓝 5=白 10=暖橙
    if (temp <= 2) return const Color(0xFF6BB8FF); // 冷蓝
    if (temp <= 4) return const Color(0xFFB8D8FF); // 冷白
    if (temp <= 6) return const Color(0xFFFFF8E8); // 自然白
    if (temp <= 8) return const Color(0xFFFFD54F); // 暖金
    return const Color(0xFFFFAB40); // 暖橙
  }

  void _drawEllipse(Canvas canvas, Offset center, double rx, double ry,
      double rotation, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final rect =
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    canvas.drawOval(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LightingSpherePainter oldDelegate) {
    return azimuth != oldDelegate.azimuth ||
        elevation != oldDelegate.elevation ||
        intensity != oldDelegate.intensity ||
        colorTemp != oldDelegate.colorTemp ||
        refImage != oldDelegate.refImage;
  }
}
