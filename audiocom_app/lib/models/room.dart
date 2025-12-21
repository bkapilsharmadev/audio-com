/// Room model
class Room {
  final String id;
  final String name;
  final String? description;
  final int userCount;
  final int maxUsers;
  final bool isPrivate;
  final bool isPasswordProtected;
  final List<String>? userIds;

  Room({
    required this.id,
    required this.name,
    this.description,
    this.userCount = 0,
    this.maxUsers = 25,
    this.isPrivate = false,
    this.isPasswordProtected = false,
    this.userIds,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      userCount: json['userCount'] as int? ?? 0,
      maxUsers: json['maxUsers'] as int? ?? 25,
      isPrivate: json['isPrivate'] as bool? ?? false,
      isPasswordProtected: json['isPasswordProtected'] as bool? ?? false,
      userIds: json['users'] != null 
          ? (json['users'] as List).map((u) => u is String ? u : u['id'] as String).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'userCount': userCount,
      'maxUsers': maxUsers,
      'isPrivate': isPrivate,
      'isPasswordProtected': isPasswordProtected,
      'users': userIds,
    };
  }

  Room copyWith({
    String? id,
    String? name,
    String? description,
    int? userCount,
    int? maxUsers,
    bool? isPrivate,
    bool? isPasswordProtected,
    List<String>? userIds,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      userCount: userCount ?? this.userCount,
      maxUsers: maxUsers ?? this.maxUsers,
      isPrivate: isPrivate ?? this.isPrivate,
      isPasswordProtected: isPasswordProtected ?? this.isPasswordProtected,
      userIds: userIds ?? this.userIds,
    );
  }
}
