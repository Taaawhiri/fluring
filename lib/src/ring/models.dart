/// A camera or doorbell as Ring describes it in `clients_api/ring_devices`.
class RingCamera {
  const RingCamera({
    required this.id,
    required this.description,
    required this.kind,
    required this.batteryLife,
    required this.isDoorbell,
  });

  /// Ring's device list groups cameras under several keys; [isDoorbell] records
  /// which group this one came from so the UI can badge it.
  factory RingCamera.fromJson(Map<String, dynamic> json,
      {required bool isDoorbell}) {
    return RingCamera(
      id: (json['id'] as num).toInt(),
      description: (json['description'] as String?)?.trim().isNotEmpty == true
          ? json['description'] as String
          : 'Camera ${json['id']}',
      kind: json['kind'] as String? ?? 'unknown',
      batteryLife: _parseBattery(json['battery_life']),
      isDoorbell: isDoorbell,
    );
  }

  final int id;
  final String description;
  final String kind;

  /// Percentage, or null for mains-powered cameras that never report one.
  final int? batteryLife;
  final bool isDoorbell;

  /// Ring reports battery as either a number or a numeric string depending on
  /// the device generation.
  static int? _parseBattery(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
