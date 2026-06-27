import 'dart:async';
import 'dart:io';

enum Wan2gpStatus { stopped, starting, running, error }

class Wan2gpBridgeService {
  static const int _startupTimeoutSeconds = 30;

  Process? _process;
  bool _isRunning = false;
  String _lastError = '';
  String _logFilePath = '';
  final _statusController = StreamController<Wan2gpStatus>.broadcast();

  bool get isRunning => _isRunning;
  String get lastError => _lastError;
  String get logFilePath => _logFilePath;
  Stream<Wan2gpStatus> get statusStream => _statusController.stream;

  Future<bool> launch({
    required String pythonPath,
    required String scriptPath,
    int port = 7861,
  }) async {
    if (_isRunning) return true;

    _lastError = '';
    _emitStatus(Wan2gpStatus.starting);

    try {
      if (!File(pythonPath).existsSync()) {
        _lastError = 'Python 不存在: $pythonPath';
        _emitStatus(Wan2gpStatus.error);
        return false;
      }
      if (!File(scriptPath).existsSync()) {
        _lastError = '脚本不存在: $scriptPath';
        _emitStatus(Wan2gpStatus.error);
        return false;
      }

      final launchPythonPath = _resolveSilentPythonPath(pythonPath);
      _logFilePath = _buildBridgeLogPath(scriptPath);
      Directory(File(_logFilePath).parent.path).createSync(recursive: true);

      _process = await Process.start(
        launchPythonPath,
        [scriptPath],
        runInShell: false,
        workingDirectory: File(scriptPath).parent.path,
        environment: {
          'PYTHONUNBUFFERED': '1',
          'WANGP_BRIDGE_LOG_FILE': _logFilePath,
          'WANGP_BRIDGE_PORT': '$port',
        },
      );

      _process!.exitCode.then((code) {
        _isRunning = false;
        if (code != 0) {
          _lastError = '进程退出(code=$code)，日志: $_logFilePath';
          _emitStatus(Wan2gpStatus.error);
        } else {
          _emitStatus(Wan2gpStatus.stopped);
        }
      });

      final ready = await _waitUntilHealthy(port);
      if (!ready) {
        _lastError = '桥接服务启动超时，端口 $port 未在 ${_startupTimeoutSeconds}s 内就绪';
        await stop();
        _emitStatus(Wan2gpStatus.error);
        return false;
      }

      _isRunning = true;
      _emitStatus(Wan2gpStatus.running);
      return true;
    } catch (e) {
      _lastError = e.toString();
      _isRunning = false;
      _emitStatus(Wan2gpStatus.error);
      return false;
    }
  }

  Future<void> stop() async {
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    _isRunning = false;
    _emitStatus(Wan2gpStatus.stopped);
  }

  Future<bool> healthCheck(String host, int port) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse('http://$host:$port/api/health'),
      );
      final response = await request.close();
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitUntilHealthy(int port) async {
    final deadline = DateTime.now().add(
      const Duration(seconds: _startupTimeoutSeconds),
    );
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) return false;
      if (await healthCheck('127.0.0.1', port)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  String _resolveSilentPythonPath(String pythonPath) {
    final file = File(pythonPath.trim());
    final lowerName = file.uri.pathSegments.isEmpty
        ? ''
        : file.uri.pathSegments.last.toLowerCase();
    if (lowerName != 'python.exe') {
      return pythonPath;
    }
    final pythonw = File(
      '${file.parent.path}${Platform.pathSeparator}pythonw.exe',
    );
    return pythonw.existsSync() ? pythonw.path : pythonPath;
  }

  String _buildBridgeLogPath(String scriptPath) {
    final scriptDir = File(scriptPath).parent.path;
    return '$scriptDir${Platform.pathSeparator}bridge_output'
        '${Platform.pathSeparator}wan2gp_bridge_server.log';
  }

  void _emitStatus(Wan2gpStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
