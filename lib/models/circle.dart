class CircleModel {
  const CircleModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    this.createdAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final DateTime? createdAt;

  factory CircleModel.fromJson(Map<String, dynamic> json) {
    return CircleModel(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      inviteCode: json['invite_code'] as String,
      createdAt:
          json['created_at'] == null ? null : DateTime.tryParse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'invite_code': inviteCode,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
