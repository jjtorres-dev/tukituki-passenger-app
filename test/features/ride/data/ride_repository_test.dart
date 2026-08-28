import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';

void main() {
  test('createRide manda POST a passenger/rides con el paymentMethod recibido', () async {
    late RequestOptions capturedRequest;
    final dio = _dioReturning(
      _cancelledRideJson(),
      onRequest: (request) {
        capturedRequest = request;
      },
    );

    await RideRepository(dio).createRide(
      fareQuoteId: 'quote-1',
      passengerOfferFare: '8.00',
      paymentMethod: 'YAPE',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, 'passenger/rides');
    expect(capturedRequest.data, {
      'fareQuoteId': 'quote-1',
      'passengerOfferFare': '8.00',
      'paymentMethod': 'YAPE',
    });
  });

  test('createRide ya no fuerza CASH: pasa el método tal cual (PLIN)', () async {
    late RequestOptions capturedRequest;
    final dio = _dioReturning(
      _cancelledRideJson(),
      onRequest: (request) {
        capturedRequest = request;
      },
    );

    await RideRepository(dio).createRide(
      fareQuoteId: 'q',
      passengerOfferFare: '3.00',
      paymentMethod: 'PLIN',
    );

    expect((capturedRequest.data as Map)['paymentMethod'], 'PLIN');
  });

  test('cancelRide usa PATCH, path y payload exactos', () async {
    late RequestOptions capturedRequest;
    final dio = _dioReturning(
      _cancelledRideJson(),
      onRequest: (request) {
        capturedRequest = request;
      },
    );
    final repository = RideRepository(dio);

    await repository.cancelRide(rideId: 'ride-123');

    expect(capturedRequest.method, 'PATCH');
    expect(capturedRequest.path, 'passenger/rides/ride-123/cancel');
    expect(capturedRequest.data, {'reason': 'Ya no necesito el viaje'});
  });

  test('cancelRide parsea PassengerRide CANCELLED', () async {
    final repository = RideRepository(_dioReturning(_cancelledRideJson()));

    final ride = await repository.cancelRide(rideId: 'ride-123');

    expect(ride.id, 'ride-123');
    expect(ride.status, 'CANCELLED');
    expect(ride.originLatitude, -6.4877);
    expect(ride.destinationLongitude, -76.3721);
  });

  test('getHistory usa GET, path y query params exactos', () async {
    late RequestOptions capturedRequest;
    final dio = _dioReturning(
      _historyResponseJson(),
      onRequest: (request) {
        capturedRequest = request;
      },
    );
    final repository = RideRepository(dio);

    await repository.getHistory();

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.path, 'passenger/rides/history');
    expect(capturedRequest.queryParameters, {'status': 'COMPLETED', 'limit': 50});
  });

  test('getHistory respeta status/limit explícitos', () async {
    late RequestOptions capturedRequest;
    final dio = _dioReturning(
      _historyResponseJson(),
      onRequest: (request) {
        capturedRequest = request;
      },
    );
    final repository = RideRepository(dio);

    await repository.getHistory(status: 'CANCELLED', limit: 10);

    expect(capturedRequest.queryParameters, {'status': 'CANCELLED', 'limit': 10});
  });

  test('getHistory parsea los ítems, incluidas las coordenadas del destino', () async {
    final repository = RideRepository(_dioReturning(_historyResponseJson()));

    final items = await repository.getHistory();

    expect(items, hasLength(1));
    expect(items.single.rideId, 'ride-1');
    expect(items.single.destinationAddress, 'UPEU');
    expect(items.single.destinationLatitude, -6.4877);
    expect(items.single.destinationLongitude, -76.3599);
  });

  test('getHistory ignora elementos malformados de items en vez de lanzar', () async {
    final repository = RideRepository(
      _dioReturning({
        'items': [
          'esto no es un objeto',
          {
            'rideId': 'ride-1',
            'destinationAddress': 'UPEU',
            'destinationLatitude': -6.4877,
            'destinationLongitude': -76.3599,
            'requestedAt': '2026-08-20T15:00:00.000Z',
          },
        ],
        'pagination': {
          'page': 1,
          'limit': 50,
          'totalItems': 1,
          'totalPages': 1,
          'hasNextPage': false,
          'hasPreviousPage': false,
        },
      }),
    );

    final items = await repository.getHistory();

    expect(items, hasLength(1));
  });
}

Dio _dioReturning(
  Map<String, dynamic> responseData, {
  void Function(RequestOptions request)? onRequest,
}) {
  final dio = Dio();

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: responseData,
          ),
        );
      },
    ),
  );

  return dio;
}

Map<String, dynamic> _cancelledRideJson() {
  return {
    'id': 'ride-123',
    'fareQuoteId': 'quote-1',
    'status': 'CANCELLED',
    'distanceMeters': 1500,
    'estimatedDurationSeconds': 600,
    'estimatedFare': '7.00',
    'estimatedPassengerFare': '7.00',
    'passengerOfferFare': '7.00',
    'agreedFare': null,
    'currency': 'PEN',
    'paymentMethod': 'CASH',
    'origin': {'latitude': -6.4877, 'longitude': -76.3599, 'address': 'Origen'},
    'destination': {
      'latitude': -6.4812,
      'longitude': -76.3721,
      'address': 'Destino',
    },
    'requestedAt': '2026-08-10T12:00:00.000Z',
    'searchExpiresAt': null,
  };
}

Map<String, dynamic> _historyResponseJson() {
  return {
    'items': [
      {
        'rideId': 'ride-1',
        'status': 'COMPLETED',
        'originAddress': 'Jr. Lima 250, Tarapoto',
        'destinationAddress': 'UPEU',
        'destinationLatitude': -6.4877,
        'destinationLongitude': -76.3599,
        'requestedAt': '2026-08-20T15:00:00.000Z',
        'startedAt': '2026-08-20T15:05:00.000Z',
        'completedAt': '2026-08-20T15:20:00.000Z',
        'cancelledAt': null,
        'actualDistanceMeters': 3200,
        'actualDurationSeconds': 900,
        'estimatedFare': '7.40',
        'finalFare': '7.80',
        'currency': 'PEN',
        'driver': null,
        'ratingSubmitted': false,
        'canRate': false,
      },
    ],
    'pagination': {
      'page': 1,
      'limit': 50,
      'totalItems': 1,
      'totalPages': 1,
      'hasNextPage': false,
      'hasPreviousPage': false,
    },
  };
}
