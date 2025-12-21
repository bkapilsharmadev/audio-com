/// Chat message model
class ChatMessage {
  final String? userId;
  final String? userName;
  final String content;
  final DateTime timestamp;
  final bool isSystem;

  ChatMessage({
    this.userId,
    this.userName,
    required this.content,
    required this.timestamp,
    this.isSystem = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      userId: json['userId'] as String?,
      userName: json['userName'] as String?,
      content: json['content'] as String,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  factory ChatMessage.system(String content) {
    return ChatMessage(
      content: content,
      timestamp: DateTime.now(),
      isSystem: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isSystem': isSystem,
    };
  }
}
