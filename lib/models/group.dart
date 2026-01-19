class Group {
  final int id;
  final String name;
  final String icon;
  final int memberCount;
  final String? description;
  final bool isPublic;
  final String? handle;

  const Group({
    required this.id,
    required this.name,
    required this.icon,
    required this.memberCount,
    this.description,
    this.isPublic = false,
    this.handle,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '',
      memberCount: (json['member_count'] as int?) ?? 0,
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      handle: json['handle'] as String?,
    );
  }
}
