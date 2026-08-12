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

  test('parsea driver, vehicle y driverLocation reales tras la asignación', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: {
          'driver': {
            'profileId': 'driver-1',
            'firstName': 'Carlos',
            'photoUrl': 'https://cdn.tukituki.pe/carlos.jpg',
            'ratingAverage': '4.92',
            'ratingCount': 128,
            'vehicle': {
              'plate': '1234-AB',
              'brand': 'Bajaj',
              'model': 'RE 4S',
              'color': 'Rojo',
              'vehicleType': 'MOTOTAXI',
            },
          },
          'driverLocation': {
            'latitude': -6.4879,
            'longitude': -76.3601,
            'heading': 90,
            'speed': 7.5,
            'accuracy': 8,
            'recordedAt': '2026-08-10T12:05:00.000Z',
          },
          'driverAssignedAt': '2026-08-10T12:01:00.000Z',
          'driverArrivingAt': '2026-08-10T12:02:00.000Z',
          'driverArrivedAt': null,
          'arrivalDistanceMeters': null,
        },
      ),
    );

    expect(ride.driver, isNotNull);
    expect(ride.driver!.profileId, 'driver-1');
    expect(ride.driver!.firstName, 'Carlos');
    expect(ride.driver!.photoUrl, 'https://cdn.tukituki.pe/carlos.jpg');
    expect(ride.driver!.ratingAverage, '4.92');
    expect(ride.driver!.ratingCount, 128);
    expect(ride.driver!.hasRating, isTrue);

    expect(ride.driver!.vehicle, isNotNull);
    expect(ride.driver!.vehicle!.plate, '1234-AB');
    expect(ride.driver!.vehicle!.brand, 'Bajaj');
    expect(ride.driver!.vehicle!.model, 'RE 4S');
    expect(ride.driver!.vehicle!.color, 'Rojo');
    expect(ride.driver!.vehicle!.vehicleType, 'MOTOTAXI');

    expect(ride.driverLocation, isNotNull);
    expect(ride.driverLocation!.latitude, -6.4879);
    expect(ride.driverLocation!.longitude, -76.3601);
    expect(ride.driverLocation!.heading, 90);
    expect(ride.driverLocation!.speed, 7.5);
    expect(ride.driverLocation!.accuracy, 8);
    expect(
      ride.driverLocation!.recordedAt,
      DateTime.parse('2026-08-10T12:05:00.000Z'),
    );

    expect(
      ride.driverAssignedAt,
      DateTime.parse('2026-08-10T12:01:00.000Z'),
    );
    expect(
      ride.driverArrivingAt,
      DateTime.parse('2026-08-10T12:02:00.000Z'),
    );
    expect(ride.driverArrivedAt, isNull);
    expect(ride.arrivalDistanceMeters, isNull);
  });

  test('driver ausente antes de la asignación no rompe el parsing', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
      ),
    );

    expect(ride.driver, isNull);
    expect(ride.driverLocation, isNull);
    expect(ride.driverAssignedAt, isNull);
    expect(ride.driverArrivingAt, isNull);
    expect(ride.driverArrivedAt, isNull);
    expect(ride.arrivalDistanceMeters, isNull);
  });

  test('conductor sin historial respeta el rating real 0.00/0', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: {
          'driver': {
            'profileId': 'driver-2',
            'firstName': 'Nuevo',
            'photoUrl': null,
            'ratingAverage': '0.00',
            'ratingCount': 0,
            'vehicle': {
              'plate': '5678-CD',
              'brand': 'Honda',
              'model': 'CB1',
              'color': 'Negro',
              'vehicleType': 'MOTOTAXI',
            },
          },
        },
      ),
    );

    expect(ride.driver!.ratingAverage, '0.00');
    expect(ride.driver!.ratingCount, 0);
    expect(ride.driver!.hasRating, isFalse);
    expect(ride.driver!.photoUrl, isNull);
  });

  test('driverLocation inválida no rompe el parsing', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: {
          'driverLocation': {'latitude': 'no-numero', 'longitude': 200},
        },
      ),
    );

    expect(ride.driverLocation, isNull);
  });

  _cancellationTests();
}

void _cancellationTests() {
  test('cancelledAt/cancelledBy/cancellationReason: campos ausentes quedan null', () {
    final ride = PassengerRide.fromJson(
      _rideJson(origin: {'address': 'Origen'}, destination: {'address': 'Destino'}),
    );

    expect(ride.cancelledAt, isNull);
    expect(ride.cancelledBy, isNull);
    expect(ride.cancellationReason, isNull);
  });

  test('cancelledAt/cancelledBy/cancellationReason: null explícito de Backend queda null', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {
          'cancelledAt': null,
          'cancelledBy': null,
          'cancellationReason': null,
        },
      ),
    );

    expect(ride.cancelledAt, isNull);
    expect(ride.cancelledBy, isNull);
    expect(ride.cancellationReason, isNull);
  });

  test('cancelledAt parsea una fecha real', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {'cancelledAt': '2026-08-12T15:30:00.000Z'},
      ),
    );

    expect(ride.cancelledAt, DateTime.utc(2026, 8, 12, 15, 30));
  });

  test('cancelledBy preserva el valor real de Backend (DRIVER)', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {'status': 'CANCELLED', 'cancelledBy': 'DRIVER'},
      ),
    );

    expect(ride.cancelledBy, 'DRIVER');
  });

  test('cancelledBy preserva el valor real de Backend (PASSENGER)', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {'status': 'CANCELLED', 'cancelledBy': 'PASSENGER'},
      ),
    );

    expect(ride.cancelledBy, 'PASSENGER');
  });

  test('status CANCELLED sin cancelledBy NUNCA infiere DRIVER', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {'status': 'CANCELLED'},
      ),
    );

    expect(ride.status, 'CANCELLED');
    expect(ride.cancelledBy, isNull);
  });

  test('cancellationReason conserva el string real de Backend', () {
    final ride = PassengerRide.fromJson(
      _rideJson(
        origin: {'address': 'Origen'},
        destination: {'address': 'Destino'},
        extra: const {
          'status': 'CANCELLED',
          'cancelledBy': 'DRIVER',
          'cancellationReason': 'VEHICLE_PROBLEM',
        },
      ),
    );

    expect(ride.cancellationReason, 'VEHICLE_PROBLEM');
  });
}

Map<String, dynamic> _rideJson({
  required Object origin,
  required Object destination,
  num distanceMeters = 1500,
  num estimatedDurationSeconds = 600,
  Map<String, dynamic> extra = const {},
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
    ...extra,
  };
}
