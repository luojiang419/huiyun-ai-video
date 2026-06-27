import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String filePath;
  final bool autoPlay;
  final bool showControls;
  final Widget? unavailablePlaceholder;

  const VideoPlayerWidget({
    super.key,
    required this.filePath,
    this.autoPlay = false,
    this.showControls = true,
    this.unavailablePlaceholder,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final Player _player;
  late final VideoController _controller;
  bool _hasPlayableFile = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _syncMedia();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.autoPlay != widget.autoPlay) {
      _syncMedia();
    }
  }

  Future<void> _syncMedia() async {
    final hasFile =
        widget.filePath.trim().isNotEmpty && File(widget.filePath).existsSync();
    if (!hasFile) {
      await _player.stop();
      if (mounted) {
        setState(() => _hasPlayableFile = false);
      }
      return;
    }

    try {
      await _player.open(Media(widget.filePath));
      if (widget.autoPlay) {
        await _player.play();
      } else {
        await _player.pause();
      }
      if (mounted) {
        setState(() => _hasPlayableFile = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasPlayableFile = false);
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPlayableFile) {
      return widget.unavailablePlaceholder ?? const _VideoUnavailableView();
    }
    return Video(
      controller: _controller,
      controls: widget.showControls ? MaterialVideoControls : NoVideoControls,
    );
  }
}

void openFullscreenVideo(BuildContext context, String filePath) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => _FullscreenPlayer(filePath: filePath)),
  );
}

class _FullscreenPlayer extends StatefulWidget {
  final String filePath;

  const _FullscreenPlayer({required this.filePath});

  @override
  State<_FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<_FullscreenPlayer> {
  late final FocusNode _focusNode;
  late final Player _player;
  late final VideoController _controller;
  bool _hasPlayableFile = false;
  bool _isPlaying = true;
  double _volume = 100;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'fullscreen-video-player');
    _player = Player();
    _controller = VideoController(_player);
    _openMedia();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _openMedia() async {
    final hasFile =
        widget.filePath.trim().isNotEmpty && File(widget.filePath).existsSync();
    if (!hasFile) {
      if (mounted) {
        setState(() => _hasPlayableFile = false);
      }
      return;
    }
    try {
      await _player.open(Media(widget.filePath));
      await _player.setVolume(_volume);
      await _player.play();
      if (mounted) {
        setState(() {
          _hasPlayableFile = true;
          _isPlaying = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasPlayableFile = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (!_hasPlayableFile) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) {
      setState(() => _isPlaying = !_isPlaying);
    }
  }

  Future<void> _adjustVolume(double delta) async {
    if (!_hasPlayableFile) return;
    _volume = (_volume + delta).clamp(0, 100);
    await _player.setVolume(_volume);
    if (mounted) {
      setState(() {});
    }
  }

  void _closeFullscreen() {
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeFullscreen,
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          _adjustVolume(10);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          _adjustVolume(-10);
        },
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _closeFullscreen();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayback();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _adjustVolume(10);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _adjustVolume(-10);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: _hasPlayableFile
                      ? Video(
                          controller: _controller,
                          controls: MaterialVideoControls,
                        )
                      : const _VideoUnavailableView(),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Esc 退出全屏  Space 播放/暂停  ↑↓ 音量 ${_volume.round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  onPressed: _closeFullscreen,
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoUnavailableView extends StatelessWidget {
  const _VideoUnavailableView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_file_outlined, color: Colors.white54, size: 40),
          SizedBox(height: 8),
          Text(
            '视频文件不存在或暂时无法播放',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
