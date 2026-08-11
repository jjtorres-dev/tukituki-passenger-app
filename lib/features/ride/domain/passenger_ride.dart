import 'assigned_driver.dart';
import 'driver_location.dart';

class PassengerRide {
  const PassengerRide({
    required this.id,
    required this.fareQuoteId,
    required this.status,
    required this.distanceMeters,
    required this.estimatedDurationSeconds,
    required this.estimatedFare,
    required this.estimatedPassengerFare,
    required this.passengerOfferFare,
    required this.agreedFare,
    required this.currency,
    required this.paymentMethod,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    required this.originAddress,
    required this.destinationAddress,
    required this.requestedAt,
    required this.searchExpiresAt,
    this.driver,
    this.driverLocation,
    this.driverAssignedAt,
    this.driverArrivingAt,
    this.driverArrivedAt,
    this.arrivalDistanceMeters,
  });

  final String id;
  final String fareQuoteId;
  final String status;

  final num distanceMeters;
  final num estimatedDurationSeconds;

  final String estimatedFare;
  final String estimatedPassengerFare;
  final String passengerOfferFare;
  final String? agreedFare;

  final String currency;
  final String paymentMethod;

  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  final String originAddress;
  final String destinationAddress;

  final DateTime requestedAt;
  final DateTime? searchExpiresAt;

  final AssignedDriver? driver;
  final DriverLocation? driverLocation;

  final DateTime? driverAssignedAt;
  final DateTime? driverArrivingAt;
  final DateTime? driverArrivedAt;
  final String? arrivalDistanceMeters;

  factory PassengerRide.fromJson(Map<String, dynamic> json) {
    final originValue = json['origin'];
    final origin = originValue is Map
        ? Map<String, dynamic>.from(originValue)
        : const <String, dynamic>{};

    final destinationValue = json['destination'];
    final destination = destinationValue is Map
        ? Map<String, dynamic>.from(destinationValue)
        : const <String, dynamic>{};

    double? coordinate(
      dynamic value, {
      required double minimum,
      required double maximum,
    }) {
      if (value is! num) {
        return null;
      }

      final coordinate = value.toDouble();

      if (!coordinate.isFinite ||
          coordinate < minimum ||
          coordinate > maximum) {
        return null;
      }

      return coordinate;
    }

    final estimatedFare = json['estimatedFare']?.toString() ?? '0.00';

    final estimatedPassengerFare =
        json['estimatedPassengerFare']?.toString() ?? estimatedFare;

    final passengerOfferFare =
        json['passengerOfferFare']?.toString() ?? estimatedFare;

    final requestedAtValue = json['requestedAt']?.toString();

    final searchExpiresAtValue = json['searchExpiresAt']?.toString();

    return PassengerRide(
      id: json['id']?.toString() ?? '',
      fareQuoteId: json['fareQuoteId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',

      distanceMeters: json['distanceMeters'] as num? ?? 0,

      estimatedDurationSeconds: json['estimatedDurationSeconds'] as num? ?? 0,

      estimatedFare: estimatedFare,

      estimatedPassengerFare: estimatedPassengerFare,

      passengerOfferFare: passengerOfferFare,

      agreedFare: json['agreedFare']?.toString(),

      currency: json['currency']?.toString() ?? 'PEN',

      paymentMethod: json['paymentMethod']?.toString() ?? 'CASH',

      originLatitude: coordinate(origin['latitude'], minimum: -90, maximum: 90),

      originLongitude: coordinate(
        origin['longitude'],
        minimum: -180,
        maximum: 180,
      ),

      destinationLatitude: coordinate(
        destination['latitude'],
        minimum: -90,
        maximum: 90,
      ),

      destinationLongitude: coordinate(
        destination['longitude'],
        minimum: -180,
        maximum: 180,
      ),

      originAddress: origin['address']?.toString() ?? 'Origen',

      destinationAddress: destination['address']?.toString() ?? 'Destino',

      requestedAt: requestedAtValue != null
          ? DateTime.parse(requestedAtValue)
          : DateTime.now(),

      searchExpiresAt: searchExpiresAtValue != null
          ? DateTime.tryParse(searchExpiresAtValue)
          : null,

      driver: AssignedDriver.tryParse(json['driver']),

      driverLocation: DriverLocation.tryParse(json['driverLocation']),

      driverAssignedAt: DateTime.tryParse(
        json['driverAssignedAt']?.toString() ?? '',
      ),

      driverArrivingAt: DateTime.tryParse(
        json['driverArrivingAt']?.toString() ?? '',
      ),

      driverArrivedAt: DateTime.tryParse(
        json['driverArrivedAt']?.toString() ?? '',
      ),

      arrivalDistanceMeters: json['arrivalDistanceMeters']?.toString(),
    );
  }
}
