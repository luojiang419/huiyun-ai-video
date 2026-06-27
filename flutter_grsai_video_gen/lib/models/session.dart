import 'message.dart';

class Session {
  final String name;
  final int created;
  final List<Message> messages;

  Session({
    required this.name,
    required this.created,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'created': created,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        name: json['name'],
        created: json['created'],
        messages: (json['messages'] as List)
            .map((m) => Message.fromJson(m))
            .toList(),
      );
}
