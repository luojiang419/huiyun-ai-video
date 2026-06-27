import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../constants/app_colors.dart';

class StoryboardGalleryScreen extends StatefulWidget {
  const StoryboardGalleryScreen({super.key});

  @override
  State<StoryboardGalleryScreen> createState() => _StoryboardGalleryScreenState();
}

class _StoryboardGalleryScreenState extends State<StoryboardGalleryScreen> {
  List<String> _projects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final galleryDir = Directory(path.join(appDir.path, 'data', '分镜图'));

      if (await galleryDir.exists()) {
        final entities = await galleryDir.list().toList();
        // 按文件夹修改时间降序排列（最新的在最前面）
        final dirs = entities.whereType<Directory>()
            .where((e) => path.basename(e.path).endsWith('-分镜图')).toList();
        final statFutures = dirs.map((e) => e.stat()).toList();
        final stats = await Future.wait(statFutures);
        final dirWithStat = List.generate(dirs.length, (i) => MapEntry(dirs[i], stats[i]));
        dirWithStat.sort((a, b) => b.value.modified.compareTo(a.value.modified));
        final projects = dirWithStat
            .map((e) => path.basename(e.key.path).replaceAll('-分镜图', ''))
            .toList();
        
        if (mounted) {
          setState(() {
            _projects = projects;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navbar,
        title: const Text('分镜图管理', style: TextStyle(color: AppColors.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.text),
            onPressed: _loadProjects,
            tooltip: '刷新列表',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('暂无分镜项目', style: TextStyle(color: AppColors.textSecondary)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final project = _projects[index];
                    return _buildProjectCard(project);
                  },
                ),
    );
  }

  Widget _buildProjectCard(String projectName) {
    return GestureDetector(
      onTap: () => _openProject(projectName),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.sidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_special, color: AppColors.primary, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                projectName,
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_open, color: AppColors.textSecondary, size: 20),
                  onPressed: () => _openInExplorer(projectName),
                  tooltip: '打开文件夹',
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _deleteProject(projectName),
                  tooltip: '删除项目',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProject(String projectName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProjectDetailScreen(projectName: projectName)),
    );
    _loadProjects(); // 返回后刷新
  }

  Future<void> _openInExplorer(String projectName) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final pathStr = path.join(appDir.path, 'data', '分镜图', '$projectName-分镜图');
    if (await Directory(pathStr).exists()) {
      // Windows
      if (Platform.isWindows) {
        Process.run('explorer', [pathStr]);
      } else if (Platform.isMacOS) {
        Process.run('open', [pathStr]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [pathStr]);
      }
    }
  }

  Future<void> _deleteProject(String projectName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text('确定要永久删除项目 "$projectName" 及其所有图片吗？此操作不可恢复。', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final appDir = File(Platform.resolvedExecutable).parent;
        final projectDir = Directory(path.join(appDir.path, 'data', '分镜图', '$projectName-分镜图'));
        if (await projectDir.exists()) {
          await projectDir.delete(recursive: true);
        }
        _loadProjects();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('项目已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }
}

class ProjectDetailScreen extends StatefulWidget {
  final String projectName;

  const ProjectDetailScreen({super.key, required this.projectName});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<Directory> _batches = [];
  bool _isLoading = true;
  List<File> _allImages = [];
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => _isLoading = true);
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final projectDir = Directory(path.join(appDir.path, 'data', '分镜图', '${widget.projectName}-分镜图'));

      if (await projectDir.exists()) {
        final entities = await projectDir.list().toList();
        final batches = entities.whereType<Directory>().toList();
        
        // 按名称排序 (批次1, 批次2...)
        batches.sort((a, b) {
          final nameA = path.basename(a.path);
          final nameB = path.basename(b.path);
          return nameA.compareTo(nameB); // 简单排序，如果需要数字排序可能需要正则
        });

        if (mounted) {
          setState(() {
            _batches = batches;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navbar,
        title: Text('${widget.projectName} - 图片管理', style: const TextStyle(color: AppColors.text)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.text),
            onPressed: _loadBatches,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? const Center(child: Text('该项目暂无生成批次', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _batches.length,
                  itemBuilder: (context, index) {
                    final batchDir = _batches[index];
                    return _buildBatchSection(batchDir);
                  },
                ),
    );
  }

  Widget _buildBatchSection(Directory batchDir) {
    final batchName = path.basename(batchDir.path);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border1),
      ),
      child: ExpansionTile(
        initiallyExpanded: true, // 默认展开
        title: Text(batchName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.folder, color: AppColors.primary),
        childrenPadding: const EdgeInsets.all(16),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
             IconButton(
              icon: const Icon(Icons.folder_open, color: AppColors.textSecondary, size: 20),
              onPressed: () {
                if (Platform.isWindows) {
                  Process.run('explorer', [batchDir.path]);
                }
              },
              tooltip: '打开文件夹',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _deleteBatch(batchDir),
              tooltip: '删除批次',
            ),
          ],
        ),
        children: [
          FutureBuilder<List<FileSystemEntity>>(
            future: batchDir.list().toList(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('加载失败: ${snapshot.error}', style: const TextStyle(color: Colors.red));
              }
              
              final files = snapshot.data
                  ?.whereType<File>()
                  .where((f) {
                    final ext = path.extension(f.path).toLowerCase();
                    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
                  })
                  .toList() ?? [];

              if (files.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无图片', style: TextStyle(color: AppColors.textSecondary)),
                );
              }

              // 按文件名排序
              files.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.0,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index] as File;
                  return _buildImageCard(file);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(File file) {
    return GestureDetector(
      onTap: () => _showImagePreview(file),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: AppColors.textSecondary),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  path.basename(file.path),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(File file) async {
    await _loadAllImages();
    _currentImageIndex = _allImages.indexWhere((f) => f.path == file.path);
    if (_currentImageIndex == -1) _currentImageIndex = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: KeyboardListener(
            focusNode: FocusNode()..requestFocus(),
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _currentImageIndex > 0) {
                  setState(() => _currentImageIndex--);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && _currentImageIndex < _allImages.length - 1) {
                  setState(() => _currentImageIndex++);
                }
              }
            },
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(_allImages[_currentImageIndex]),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: AppColors.sidebar,
                                title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
                                content: const Text('确定要删除这张图片吗？', style: TextStyle(color: AppColors.textSecondary)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              try {
                                await _allImages[_currentImageIndex].delete();
                                _allImages.removeAt(_currentImageIndex);
                                if (_currentImageIndex >= _allImages.length && _allImages.isNotEmpty) {
                                  _currentImageIndex = _allImages.length - 1;
                                }
                                if (_allImages.isEmpty) {
                                  if (context.mounted) Navigator.pop(context);
                                } else {
                                  setState(() {});
                                }
                                if (mounted) this.setState(() {});
                              } catch (e) {
                                // ignore error
                              }
                            }
                          },
                          tooltip: '删除图片',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: '关闭预览',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAllImages() async {
    _allImages.clear();
    for (final batchDir in _batches) {
      final files = await batchDir.list().toList();
      final imageFiles = files.whereType<File>().where((f) {
        final ext = path.extension(f.path).toLowerCase();
        return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
      }).toList();
      imageFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
      _allImages.addAll(imageFiles);
    }
  }

  Future<void> _deleteBatch(Directory batchDir) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text('确定要删除批次 "${path.basename(batchDir.path)}" 及其所有图片吗？', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await batchDir.delete(recursive: true);
        _loadBatches();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }
}
