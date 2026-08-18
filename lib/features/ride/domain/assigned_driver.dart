class AssignedDriverVehicle {
  const AssignedDriverVehicle({
    required this.plate,
    required this.brand,
    required this.model,
    required this.color,
    required this.vehicleType,
  });

  final String plate;
  final String brand;
  final String model;
  final String color;
  final String vehicleType;

  factory AssignedDriverVehicle.fromJson(Map<String, dynamic> json) {
    return AssignedDriverVehicle(
      plate: json['plate']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      vehicleType: json['vehicleType']?.toString() ?? '',
    );
  }
}

class AssignedDriver {
  const AssignedDriver({
    required this.profileId,
    required this.firstName,
    required this.lastNameInitial,
    this.photoUrl,
    required this.ratingAverage,
    required this.ratingCount,
    this.vehicle,
  });

  final String profileId;
  final String firstName;
  final String lastNameInitial;
  final String? photoUrl;
  final String ratingAverage;
  final int ratingCount;
  final AssignedDriverVehicle? vehicle;

  bool get hasRating {
    final average = double.tryParse(ratingAverage);

    return ratingCount > 0 &&
        average != null &&
        average.isFinite &&
        average > 0;
  }

  static AssignedDriver? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }

    return AssignedDriver.fromJson(Map<String, dynamic>.from(json));
  }

  factory AssignedDriver.fromJson(Map<String, dynamic> json) {
    final vehicleValue = json['vehicle'];

    final vehicle = vehicleValue is Map
        ? AssignedDriverVehicle.fromJson(Map<String, dynamic>.from(vehicleValue))
        : null;

    int toInt(dynamic value) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return AssignedDriver(
      profileId: json['profileId']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastNameInitial: json['lastNameInitial']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      ratingAverage: json['ratingAverage']?.toString() ?? '0.00',
      ratingCount: toInt(json['ratingCount']),
      vehicle: vehicle,
    );
  }
}
