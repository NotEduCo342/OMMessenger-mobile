class Group {
  final int id;
  final String name;
  final String icon;
  final int memberCount;

  const Group({
    required this.id,
    required this.name,
    required this.icon,
    required this.memberCount,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? '',
      memberCount: (json['member_count'] as int?) ?? 0,
    );
  }
}
