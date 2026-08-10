import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';

void main() {
  test('parsea coordenadas anidadas de origen y destino', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {
          'latitude': -6.4877,
          'longitude': -76.3599,
          'address': 'Origen real',
        },
        destination: {
          'latitude': -6.4812,
          'longitude': -76.3721,
          'address': 'Destino real',
        },
      ),
    );

    expect(ride.originLatitude, -6.4877);
    expect(ride.originLongitude, -76.3599);
    expect(ride.destinationLatitude, -6.4812);
    expect(ride.destinationLongitude, -76.3721);
    expect(ride.originAddress, 'Origen real');
    expect(ride.destinationAddress, 'Destino real');
  });

  test('convierte coordenadas int, double y num a double', () {
    final num destinationLatitude = -6.5;
    final num destinationLongitude = -76;

    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'latitude': -6, 'longitude': -76.25, 'address': 'Origen'},
        destination: {
          'latitude': destinationLatitude,
          'longitude': destinationLongitude,
          'address': 'Destino',
        },
      ),
    );

    expect(ride.originLatitude, -6.0);
    expect(ride.originLongitude, -76.25);
    expect(ride.destinationLatitude, -6.5);
    expect(ride.destinationLongitude, -76.0);
  });

  test('coordenadas ausentes o inválidas quedan null y conserva métricas', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Ubicación actual del pasajero'},
        destination: {
          'latitude': 'inválida',
          'longitude': 200,
          'address': 'Destino conservado',
        },
        distanceMeters: 2100,
        estimatedDurationSeconds: 360,
      ),
    );

    expect(ride.originLatitude, isNull);
    expect(ride.originLongitude, isNull);
    expect(ride.destinationLatitude, isNull);
    expect(ride.destinationLongitude, isNull);
    expect(ride.originLatitude, isNot(0));
    expect(ride.destinationLongitude, isNot(0));
    expect(ride.originAddress, 'Ubicación actual del pasajero');
    expect(ride.destinationAddress, 'Destino conservado');
    expect(ride.distanceMeters, 2100);
    expect(ride.estimatedDurationSeconds, 360);
  });
}

Map<String, dynamic> _rideJson({
  required Object origin,
  required Object destination,
  num distanceMeters = 1500,
  num estimatedDurationSeconds = 600,
}) {
  return {
    'id': 'ride-1',
    'fareQuoteId': 'quote-1',
    'status': 'SEARCHING_DRIVER',
    'distanceMeters': distanceMeters,
    'estimatedDurationSeconds': estimatedDurationSeconds,
    'estimatedFare': '7.00',
    'estimatedPassengerFare': '7.00',
    'passengerOfferFare': '7.00',
    'agreedFare': null,
    'currency': 'PEN',
    'paymentMethod': 'CASH',
    'origin': origin,
    'destination': destination,
    'requestedAt': '2026-08-10T12:00:00.000Z',
    'searchExpiresAt': null,
  };
}
