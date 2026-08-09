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
  final String passengerOfferFare;
  final String? agreedFare;

  final String currency;
  final String paymentMethod;

  final String originAddress;
  final String destinationAddress;

  final DateTime requestedAt;
  final DateTime? searchExpiresAt;

  factory PassengerRide.fromJson(
    Map<String, dynamic> json,
  ) {
    final origin =
        json['origin'] as Map<String, dynamic>? ?? {};

    final destination =
        json['destination'] as Map<String, dynamic>? ?? {};

    final estimatedFare =
        json['estimatedFare']?.toString() ?? '0.00';

    final estimatedPassengerFare =
        json['estimatedPassengerFare']?.toString() ??
            estimatedFare;

    final passengerOfferFare =
        json['passengerOfferFare']?.toString() ??
            estimatedFare;

    final requestedAtValue =
        json['requestedAt']?.toString();

    final searchExpiresAtValue =
        json['searchExpiresAt']?.toString();

    return PassengerRide(
      id: json['id']?.toString() ?? '',
      fareQuoteId:
          json['fareQuoteId']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'UNKNOWN',

      distanceMeters:
          json['distanceMeters'] as num? ?? 0,

      estimatedDurationSeconds:
          json['estimatedDurationSeconds'] as num? ?? 0,

      estimatedFare: estimatedFare,

      estimatedPassengerFare:
          estimatedPassengerFare,

      passengerOfferFare:
          passengerOfferFare,

      agreedFare:
          json['agreedFare']?.toString(),

      currency:
          json['currency']?.toString() ?? 'PEN',

      paymentMethod:
          json['paymentMethod']?.toString() ?? 'CASH',

      originAddress:
          origin['address']?.toString() ?? 'Origen',

      destinationAddress:
          destination['address']?.toString() ??
              'Destino',

      requestedAt: requestedAtValue != null
          ? DateTime.parse(requestedAtValue)
          : DateTime.now(),

      searchExpiresAt:
          searchExpiresAtValue != null
              ? DateTime.tryParse(
                  searchExpiresAtValue,
                )
              : null,
    );
  }
}