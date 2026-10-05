class Classroom {
  final String id;
  final String name;
  final String building;
  final String? gatewayId;

  const Classroom({
    required this.id,
    required this.name,
    required this.building,
    this.gatewayId,
  });

  factory Classroom.fromJson(Map<String, dynamic> json) {
    return Classroom(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Classroom',
      building: json['building'] as String? ?? 'Main Building',
      gatewayId: json['gateway_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'building': building,
      'gateway_id': gatewayId,
    };
  }
}
