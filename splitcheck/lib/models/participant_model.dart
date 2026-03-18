class Participant {
  final String id;
  final String name;
  final bool isOwner;
  final DateTime joinedAt;

  Participant({
    required this.id,
    required this.name,
    this.isOwner = false,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'isOwner': isOwner,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  factory Participant.fromMap(String id, Map<String, dynamic> data) {
    return Participant(
      id: id,
      name: data['name'] ?? '',
      isOwner: data['isOwner'] ?? false,
      joinedAt: DateTime.tryParse(data['joinedAt'] ?? '') ?? DateTime.now(),
    );
  }
}
