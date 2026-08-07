import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/passenger_ride.dart';

final rideRepositoryProvider =
    Provider<RideRepository>((ref) {
  return RideRepository(
    ref.watch(dioProvider),
  );
});

class RideRepository {
  RideRepository(this._dio);

  final Dio _dio;

  Future<PassengerRide> createRide({
    required String fareQuoteId,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'passenger/rides',
      data: {
        'fareQuoteId': fareQuoteId,
        'paymentMethod': 'CASH',
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return PassengerRide.fromJson(data);
  }

  Future<PassengerRide> getRide(
    String rideId,
  ) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'passenger/rides/$rideId',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El viaje no pudo ser consultado.',
      );
    }

    return PassengerRide.fromJson(data);
  }
}