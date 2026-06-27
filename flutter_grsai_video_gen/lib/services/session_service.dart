import 'dart:io';
import 'dart:convert';
import '../models/session.dart';

class SessionInfo {
  final String name;
  final int created;
  final int messageCount;

  SessionInfo({required this.name, required this.created, this.messageCount = 0});

  Map<String, dynamic> toJson() => {'name': name, 'created': created, 'messageCount': messageCount};
  factory SessionInfo.fromJson(Map<String, dynamic> json) =>
      SessionInfo(name: json['name'], created: json['created'], messageCount: json['messageCount'] ?? 0);
}

class SessionService {
  String getSessionDirectory() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    return '$exeDir/data/Session';
  }

  Future<void> createSession(String sessionName) async {
    final sessionDir = getSessionDirectory();
    final dir = Directory('$sessionDir/$sessionName');
    await dir.create(recursive: true);
  }

  Future<void> saveSession(Session session) async {
    final sessionDir = getSessionDirectory();
    final file = File('$sessionDir/${session.name}/session.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<Session?> loadSession(String sessionName) async {
    final sessionDir = getSessionDirectory();
    final file = File('$sessionDir/$sessionName/session.json');

    if (!await file.exists()) return null;

    final content = await file.readAsString();
    return Session.fromJson(jsonDecode(content));
  }

  Future<List<SessionInfo>> getAllSessions() async {
    final sessionDir = getSessionDirectory();
    final dir = Directory(sessionDir);

    if (!await dir.exists()) return [];

    final sessions = <SessionInfo>[];
    await for (var entity in dir.list()) {
      if (entity is Directory) {
        final file = File('${entity.path}/session.json');
        if (await file.exists()) {
          final content = await file.readAsString();
          final data = jsonDecode(content);
          final messages = data['messages'] as List? ?? [];
          final userMessageCount = messages.where((m) => m['type'] == 'user').length;
          sessions.add(SessionInfo(
            name: data['name'],
            created: data['created'],
            messageCount: userMessageCount,
          ));
        }
      }
    }

    return sessions;
  }

  Future<void> deleteSession(String sessionName) async {
    final sessionDir = getSessionDirectory();
    final dir = Directory('$sessionDir/$sessionName');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> renameSession(String oldName, String newName) async {
    final sessionDir = getSessionDirectory();
    final oldDir = Directory('$sessionDir/$oldName');
    final newDir = Directory('$sessionDir/$newName');

    if (await oldDir.exists()) {
      await oldDir.rename(newDir.path);

      final file = File('${newDir.path}/session.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        data['name'] = newName;
        await file.writeAsString(jsonEncode(data));
      }
    }
  }
}
