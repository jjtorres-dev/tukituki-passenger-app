class FareEstimate {
  const FareEstimate({
    required this.quoteId,
    required this.quoteStatus,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.estimatedFare,
    required this.currency,
    required this.expiresAt,
    required this.originAddress,
    required this.destinationAddress,
    required this.routePolyline,
  });

  final String quoteId;
  final String quoteStatus;
  final num distanceMeters;
  final num durationSeconds;
  final String estimatedFare;
  final String currency;
  final DateTime expiresAt;
  final String originAddress;
  final String destinationAddress;

  /*
   * Ruta real devuelta por Google Routes.
   *
   * Es opcional para mantener compatibilidad
   * si alguna respuesta antigua todavía
   * no incluye geometría.
   */
  final String? routePolyline;

  factory FareEstimate.fromJson(
    Map<String, dynamic> json,
  ) {
    final origin =
        json['origin'] as Map<String, dynamic>;

    final destination =
        json['destination'] as Map<String, dynamic>;

    final rawPolyline =
        json['routePolyline'];

    return FareEstimate(
      quoteId:
          json['quoteId'] as String,

      quoteStatus:
          json['quoteStatus'] as String,

      distanceMeters:
          json['distanceMeters'] as num,

      durationSeconds:
          json['durationSeconds'] as num,

      estimatedFare:
          json['estimatedFare'] as String,

      currency:
          json['currency'] as String,

      expiresAt:
          DateTime.parse(
        json['expiresAt'] as String,
      ),

      originAddress:
          origin['address'] as String,

      destinationAddress:
          destination['address'] as String,

      routePolyline:
          rawPolyline is String &&
                  rawPolyline.trim().isNotEmpty
              ? rawPolyline.trim()
              : null,
    );
  }
}