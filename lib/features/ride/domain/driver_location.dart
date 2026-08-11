class DriverLocation {
  const DriverLocation({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speed,
    this.accuracy,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final DateTime? recordedAt;

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  static DriverLocation? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(json);

    final latitude = _toDouble(map['latitude']);
    final longitude = _toDouble(map['longitude']);

    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return DriverLocation(
      latitude: latitude,
      longitude: longitude,
      heading: _toDouble(map['heading']),
      speed: _toDouble(map['speed']),
      accuracy: _toDouble(map['accuracy']),
      recordedAt: DateTime.tryParse(map['recordedAt']?.toString() ?? ''),
    );
  }
}
