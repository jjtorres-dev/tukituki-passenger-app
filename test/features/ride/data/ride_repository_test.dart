import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';

void main() {
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
