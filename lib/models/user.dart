class User {
  final int id;
  final String username;
  final String email;
  final String fullName;
  final String avatar;
  final bool isOnline;
  final DateTime? lastSeen;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.avatar,
    required this.isOnline,
    this.lastSeen,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      fullName: json['full_name'] ?? '',
      avatar: json['avatar'] ?? '',
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'avatar': avatar,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }
}
