class PassengerRide {
  const PassengerRide({
    required this.id,
    required this.fareQuoteId,
    required this.status,
    required this.distanceMeters,
    required this.estimatedDurationSeconds,
    required this.estimatedFare,
    required this.estimatedPassengerFare,
    required this.currency,
    required this.paymentMethod,
    required this.originAddress,
    required this.destinationAddress,
    required this.requestedAt,
    required this.searchExpiresAt,
  });

  final String id;
  final String fareQuoteId;
  final String status;
  final num distanceMeters;
  final num estimatedDurationSeconds;
  final String estimatedFare;
  final String estimatedPassengerFare;
  final String currency;
  final String paymentMethod;
  final String originAddress;
  final String destinationAddress;
  final DateTime requestedAt;
  final DateTime searchExpiresAt;

  factory PassengerRide.fromJson(
    Map<String, dynamic> json,
  ) {
    final origin =
        json['origin'] as Map<String, dynamic>;

    final destination =
        json['destination'] as Map<String, dynamic>;

    return PassengerRide(
      id: json['id'] as String,
      fareQuoteId: json['fareQuoteId'] as String,
      status: json['status'] as String,
      distanceMeters: json['distanceMeters'] as num,
      estimatedDurationSeconds:
          json['estimatedDurationSeconds'] as num,
      estimatedFare: json['estimatedFare'] as String,
      estimatedPassengerFare:
          json['estimatedPassengerFare'] as String,
      currency: json['currency'] as String,
      paymentMethod: json['paymentMethod'] as String,
      originAddress: origin['address'] as String,
      destinationAddress:
          destination['address'] as String,
      requestedAt: DateTime.parse(
        json['requestedAt'] as String,
      ),
      searchExpiresAt: DateTime.parse(
        json['searchExpiresAt'] as String,
      ),
    );
  }
}