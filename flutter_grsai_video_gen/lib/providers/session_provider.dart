import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../services/session_service.dart';
import '../services/storage_service.dart';

final sessionServiceProvider = Provider((ref) => SessionService());
final storageServiceProvider = Provider((ref) => StorageService());

final currentSessionProvider =
    StateNotifierProvider<CurrentSessionNotifier, Session?>((ref) {
      return CurrentSessionNotifier(
        ref.read(sessionServiceProvider),
        ref.read(storageServiceProvider),
      );
    });

class CurrentSessionNotifier extends StateNotifier<Session?> {
  final SessionService _service;
  final StorageService _storage;

  CurrentSessionNotifier(this._service, this._storage) : super(null);

  Future<void> createNewSession() async {
    final allSessions = await _service.getAllSessions();

    // 解析现有会话名称，找出最大序号
    String letter = 'A';
    int number = 1;

    final pattern = RegExp(r'绘云AI-([A-Z])(\d{3})');
    for (final sessionInfo in allSessions) {
      final match = pattern.firstMatch(sessionInfo.name);
      if (match != null) {
        final currentLetter = match.group(1)!;
        final currentNumber = int.parse(match.group(2)!);

        if (currentLetter.compareTo(letter) > 0 ||
            (currentLetter == letter && currentNumber >= number)) {
          letter = currentLetter;
          number = currentNumber + 1;

          // 如果超过999，进位到下一个字母
          if (number > 999) {
            letter = String.fromCharCode(letter.codeUnitAt(0) + 1);
            number = 1;
          }
        }
      }
    }

    final name = '绘云AI-$letter${number.toString().padLeft(3, '0')}';
    final session = Session(
      name: name,
      created: DateTime.now().millisecondsSinceEpoch,
      messages: [],
    );
    await _service.createSession(name);
    await _service.saveSession(session);
    await _storage.saveLastSession(name);
    state = session;
  }

  Future<void> loadLastSession() async {
    final lastSessionName = await _storage.loadLastSession();
    if (lastSessionName != null) {
      final session = await _service.loadSession(lastSessionName);
      if (session != null) {
        state = session;
        return;
      }
    }
    await createNewSession();
  }

  Future<void> loadSession(String name) async {
    final session = await _service.loadSession(name);
    await _storage.saveLastSession(name);
    state = session;
  }

  Future<void> addMessage(Message message) async {
    if (state == null) return;
    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: [...state!.messages, message],
    );
    // Optimistic update
    state = updatedSession;
    await _service.saveSession(updatedSession);
    await _storage.saveLastSession(updatedSession.name);
  }

  Future<void> deleteSession(String name) async {
    await _service.deleteSession(name);
    if (state?.name == name) {
      state = null;
    }
  }

  Future<void> renameSession(String oldName, String newName) async {
    if (state == null || state!.name != oldName) return;
    final updatedSession = Session(
      name: newName,
      created: state!.created,
      messages: state!.messages,
    );
    await _service.deleteSession(oldName);
    await _service.saveSession(updatedSession);
    state = updatedSession;
  }

  Future<void> deleteMessage(int index) async {
    if (state == null || index >= state!.messages.length) return;
    final messages = List<Message>.from(state!.messages);

    if (messages[index].type == 'assistant' &&
        index > 0 &&
        messages[index - 1].type == 'user') {
      messages.removeAt(index);
      messages.removeAt(index - 1);
    } else {
      messages.removeAt(index);
    }

    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: messages,
    );
    await _service.saveSession(updatedSession);
    state = updatedSession;
  }

  Future<void> updateMessage(int index, Message message) async {
    if (state == null || index >= state!.messages.length) return;
    final messages = List<Message>.from(state!.messages);
    messages[index] = message;
    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: messages,
    );
    // Optimistic update
    state = updatedSession;
    await _service.saveSession(updatedSession);
  }

  Future<void> updateMessageById(String messageId, Message message) async {
    if (state == null) return;
    final index = state!.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    await updateMessage(index, message);
  }

  Future<void> deleteMessageById(String messageId) async {
    if (state == null) return;
    final index = state!.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    await deleteMessage(index);
  }

  Future<void> updateLastMessage(
    String text, {
    List<String>? images,
    List<String>? videos,
    Map<String, dynamic>? params,
  }) async {
    if (state == null || state!.messages.isEmpty) return;
    final messages = List<Message>.from(state!.messages);
    final lastIndex = messages.length - 1;
    messages[lastIndex] = Message(
      id: messages[lastIndex].id,
      type: messages[lastIndex].type,
      text: text,
      images: images ?? messages[lastIndex].images,
      videos: videos ?? messages[lastIndex].videos,
      params: params ?? messages[lastIndex].params,
    );
    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: messages,
    );
    await _service.saveSession(updatedSession);
    state = updatedSession;
  }

  Future<void> removeImageFromMessages(String imagePath) async {
    if (state == null) return;
    final messages = List<Message>.from(state!.messages);
    for (var i = messages.length - 1; i >= 0; i--) {
      final updatedImages = messages[i].images
          .where((img) => img != imagePath)
          .toList();
      if (updatedImages.length != messages[i].images.length) {
        if (updatedImages.isEmpty &&
            messages[i].videos.isEmpty &&
            messages[i].type == 'assistant') {
          messages.removeAt(i);
        } else {
          messages[i] = Message(
            id: messages[i].id,
            type: messages[i].type,
            text: messages[i].text,
            images: updatedImages,
            videos: messages[i].videos,
            params: messages[i].params,
          );
        }
      }
    }
    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: messages,
    );
    await _service.saveSession(updatedSession);
    state = updatedSession;
  }

  Future<void> removeVideoFromMessages(String videoPath) async {
    if (state == null) return;
    final messages = List<Message>.from(state!.messages);
    for (var i = messages.length - 1; i >= 0; i--) {
      final updatedVideos = messages[i].videos
          .where((video) => video != videoPath)
          .toList();
      if (updatedVideos.length != messages[i].videos.length) {
        if (updatedVideos.isEmpty &&
            messages[i].images.isEmpty &&
            messages[i].type == 'assistant') {
          messages.removeAt(i);
        } else {
          messages[i] = Message(
            id: messages[i].id,
            type: messages[i].type,
            text: messages[i].text,
            images: messages[i].images,
            videos: updatedVideos,
            params: messages[i].params,
          );
        }
      }
    }
    final updatedSession = Session(
      name: state!.name,
      created: state!.created,
      messages: messages,
    );
    await _service.saveSession(updatedSession);
    state = updatedSession;
  }
}
