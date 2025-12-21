/// User model
class User {
  final String id;
  final String name;
  String? roomId;
  bool isMuted;
  bool isDeafened;
  bool isSpeaking;
  String networkStatus; // 'good', 'weak', 'disconnected', 'reconnecting'
  final DateTime? connectedAt;
  final String? token;

  User({
    required this.id,
    required this.name,
    this.roomId,
    this.isMuted = false,
    this.isDeafened = false,
    this.isSpeaking = false,
    this.networkStatus = 'good',
    this.connectedAt,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      roomId: json['roomId'] as String?,
      isMuted: json['isMuted'] as bool? ?? false,
      isDeafened: json['isDeafened'] as bool? ?? false,
      isSpeaking: json['isSpeaking'] as bool? ?? false,
      networkStatus: json['networkStatus'] as String? ?? 'good',
      connectedAt: json['connectedAt'] != null 
          ? DateTime.parse(json['connectedAt'] as String) 
          : null,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roomId': roomId,
      'isMuted': isMuted,
      'isDeafened': isDeafened,
      'isSpeaking': isSpeaking,
      'networkStatus': networkStatus,
      'connectedAt': connectedAt?.toIso8601String(),
      'token': token,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? roomId,
    bool? isMuted,
    bool? isDeafened,
    bool? isSpeaking,
    String? networkStatus,
    DateTime? connectedAt,
    String? token,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      roomId: roomId ?? this.roomId,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      networkStatus: networkStatus ?? this.networkStatus,
      connectedAt: connectedAt ?? this.connectedAt,
      token: token ?? this.token,
    );
  }
}
