import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// 3D球形相机角度控制器
/// 水平环绕 azimuth: 0°~360°
/// 垂直俯仰 elevation: -30°~60°
/// 景别缩放 distance: 0~10 (映射到 close-up / medium / wide)
class MultiAngleEditor extends StatefulWidget {
  final String imagePath;

  /// 点击"提交生成"：直接生成
  final void Function(String prompt, String imagePath) onGenerate;

  /// 点击"返回输入"：把 prompt 填回输入框，用户可继续编辑
  final void Function(String prompt, String imagePath)? onReturnToInput;

  const MultiAngleEditor({
    super.key,
    required this.imagePath,
    required this.onGenerate,
    this.onReturnToInput,
  });

  @override
  State<MultiAngleEditor> createState() => _MultiAngleEditorState();
}

class _MultiAngleEditorState extends State<MultiAngleEditor> {
  double _azimuth = 0;
  double _elevation = 0;
  double _distance = 5;
  bool _showPrompt = false;
  String _activePreset = '自定义';

  /// 加载好的参考图，用于球体中心绘制
  ui.Image? _refImage;

  static const _presets = {
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

  String get _promptText {
    final az = _azimuthToText(_azimuth);
    final el = _elevationToText(_elevation);
    final dist = _distanceToText(_distance);
    return 'Change the camera angle to: $az, $el, $dist';
  }

  String get _promptTextCN {
    final az = _azimuthToTextCN(_azimuth);
    final el = _elevationToTextCN(_elevation);
    final dist = _distanceToTextCN(_distance);
    return '将相机角度调整为：$az，$el，$dist';
  }

  String _azimuthToText(double deg) {
    deg = deg % 360;
    if (deg < 22.5 || deg >= 337.5) return 'front view';
    if (deg < 67.5) return 'front-right ${deg.round()}° view';
    if (deg < 112.5) return 'right side ${deg.round()}° view';
    if (deg < 157.5) return 'back-right ${deg.round()}° view';
    if (deg < 202.5) return 'back view';
    if (deg < 247.5) return 'back-left ${deg.round()}° view';
    if (deg < 292.5) return 'left side ${deg.round()}° view';
    return 'front-left ${deg.round()}° view';
  }

  String _elevationToText(double deg) {
    if (deg <= -20) return 'low-angle shot ${deg.round()}°';
    if (deg <= 10) return 'eye-level shot ${deg.round()}°';
    if (deg <= 40) return 'elevated shot ${deg.round()}°';
    return 'high-angle shot ${deg.round()}°';
  }

  String _distanceToText(double dist) {
    if (dist <= 3) return 'close-up';
    if (dist <= 7) return 'medium shot';
    return 'wide shot';
  }

  String _azimuthToTextCN(double deg) {
    deg = deg % 360;
    if (deg < 22.5 || deg >= 337.5) return '正面视角';
    if (deg < 67.5) return '右前方${deg.round()}°';
    if (deg < 112.5) return '右侧${deg.round()}°';
    if (deg < 157.5) return '右后方${deg.round()}°';
    if (deg < 202.5) return '背面视角';
    if (deg < 247.5) return '左后方${deg.round()}°';
    if (deg < 292.5) return '左侧${deg.round()}°';
    return '左前方${deg.round()}°';
  }

  String _elevationToTextCN(double deg) {
    if (deg <= -20) return '仰拍${deg.round()}°';
    if (deg <= 10) return '平视${deg.round()}°';
    if (deg <= 40) return '俯拍${deg.round()}°';
    return '高角度俯拍${deg.round()}°';
  }

  String _distanceToTextCN(double dist) {
    if (dist <= 3) return '近景';
    if (dist <= 7) return '中景';
    return '远景';
  }

  void _applyPreset(String name) {
    final values = _presets[name];
    setState(() {
      _activePreset = name;
      if (values != null) {
        _azimuth = values[0];
        _elevation = values[1];
        _distance = values[2];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1a1a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text('多角度编辑器',
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
                            ? Colors.white
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
            // 主体：球体 + 控制面板
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
                            color: AppColors.primary, fontSize: 11)),
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
                        size: 16, color: Colors.white),
                    label: const Text('提交生成',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
      width: 280,
      height: 280,
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _azimuth = (_azimuth + details.delta.dx * 0.8) % 360;
                _elevation =
                    (_elevation - details.delta.dy * 0.4).clamp(-30.0, 60.0);
                _activePreset = '自定义';
              });
            },
            child: CustomPaint(
              size: const Size(280, 280),
              painter: _SpherePainter(
                azimuth: _azimuth,
                elevation: _elevation,
                distance: _distance,
                refImage: _refImage,
              ),
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: Center(
              child: IconButton(
                onPressed: () => setState(() {
                  _elevation = (_elevation + 5).clamp(-30.0, 60.0);
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
                  _elevation = (_elevation - 5).clamp(-30.0, 60.0);
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
        const SizedBox(height: 16),
        _buildSliderRow('水平环绕', _azimuth, 0, 360, '${_azimuth.round()}°',
            (v) {
          setState(() {
            _azimuth = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 20),
        _buildSliderRow(
            '垂直俯仰', _elevation, -30, 60, '${_elevation.round()}°', (v) {
          setState(() {
            _elevation = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 20),
        _buildSliderRow(
            '景别缩放', _distance, 0, 10, _distanceToTextCN(_distance), (v) {
          setState(() {
            _distance = v;
            _activePreset = '自定义';
          });
        }),
        const SizedBox(height: 24),
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
              activeColor: AppColors.primary,
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
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
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

/// 3D经纬线球体绘制器，中心显示参考图
class _SpherePainter extends CustomPainter {
  final double azimuth;
  final double elevation;
  final double distance;
  final ui.Image? refImage;

  _SpherePainter({
    required this.azimuth,
    required this.elevation,
    required this.distance,
    this.refImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;

    // 背景
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF2a2a2a));

    // 球体经纬线
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    _drawEllipse(canvas, center, radius, radius * 0.3, 0, linePaint);
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 8;
      _drawEllipse(
          canvas, center, radius * cos(angle), radius, pi / 2, linePaint);
    }
    for (int i = 1; i <= 3; i++) {
      final lat = i * pi / 8;
      final r = radius * cos(lat);
      final y = radius * sin(lat);
      _drawEllipse(
          canvas, center + Offset(0, -y), r, r * 0.3, 0, linePaint);
      if (i <= 2) {
        _drawEllipse(
            canvas, center + Offset(0, y), r, r * 0.3, 0, linePaint);
      }
    }

    // 外圆
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // 中心参考图（圆形裁剪）
    final imgSize = 44.0 + (10 - distance) * 3;
    final imgRect =
        Rect.fromCenter(center: center, width: imgSize, height: imgSize);

    if (refImage != null) {
      canvas.save();
      final clipPath = Path()..addOval(imgRect);
      canvas.clipPath(clipPath);
      paintImage(
        canvas: canvas,
        rect: imgRect,
        image: refImage!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
      // 圆形边框
      canvas.drawOval(
          imgRect,
          Paint()
            ..color = Colors.white.withOpacity(0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    } else {
      canvas.drawRect(
          imgRect,
          Paint()
            ..color = Colors.white.withOpacity(0.1)
            ..style = PaintingStyle.fill);
      canvas.drawRect(
          imgRect,
          Paint()
            ..color = Colors.white.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    // 相机指示器
    final azRad = azimuth * pi / 180;
    final elRad = elevation * pi / 180;
    final camX = center.dx + radius * 0.7 * cos(elRad) * sin(azRad);
    final camY = center.dy - radius * 0.7 * sin(elRad);

    canvas.drawLine(
        Offset(camX, camY),
        center,
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..strokeWidth = 1);

    canvas.drawCircle(
        Offset(camX, camY), 6, Paint()..color = const Color(0xFFFF6B6B));
    canvas.drawCircle(
        Offset(camX, camY),
        10,
        Paint()
          ..color = const Color(0xFFFF6B6B).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // 角度标注
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${azimuth.round()}° / ${elevation.round()}°',
        style:
            TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas,
        Offset(size.width - textPainter.width - 8, size.height - 18));
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
  bool shouldRepaint(covariant _SpherePainter oldDelegate) {
    return azimuth != oldDelegate.azimuth ||
        elevation != oldDelegate.elevation ||
        distance != oldDelegate.distance ||
        refImage != oldDelegate.refImage;
  }
}
