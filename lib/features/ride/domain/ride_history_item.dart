/// SUGGESTED-DESTINATIONS-R1: un ítem del historial de viajes del
/// pasajero (`GET passenger/rides/history`), reducido a lo que la
/// pantalla Home necesita para ofrecer destinos sugeridos. No modela
/// el recibo/estado completo del viaje — para eso está `PassengerRide`.
class RideHistoryItem {
  const RideHistoryItem({
    required this.rideId,
    required this.destinationAddress,
    this.destinationLatitude,
    this.destinationLongitude,
    required this.requestedAt,
  });

  final String rideId;
  final String destinationAddress;

  /// Backend las expone opcionales (defensivo — `Ride.destinationPosition`
  /// es `NOT NULL` en la base hoy, así que en la práctica siempre
  /// vienen). Un ítem sin coordenadas no puede usarse como sugerencia
  /// tocable: se filtra en `resolveSuggestedDestinations`.
  final double? destinationLatitude;
  final double? destinationLongitude;

  final DateTime requestedAt;

  factory RideHistoryItem.fromJson(Map<String, dynamic> json) {
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

    return RideHistoryItem(
      rideId: json['rideId']?.toString() ?? '',
      destinationAddress: json['destinationAddress']?.toString() ?? '',
      destinationLatitude: coordinate(
        json['destinationLatitude'],
        minimum: -90,
        maximum: 90,
      ),
      destinationLongitude: coordinate(
        json['destinationLongitude'],
        minimum: -180,
        maximum: 180,
      ),
      requestedAt:
          DateTime.tryParse(json['requestedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
