import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/fare_estimate.dart';

final fareRepositoryProvider =
    Provider<FareRepository>((ref) {
  return FareRepository(
    ref.watch(dioProvider),
  );
});

class FareRepository {
  FareRepository(this._dio);

  final Dio _dio;

  Future<FareEstimate> estimateRide({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required String destinationAddress,
    String originAddress =
        'Ubicación actual del pasajero',
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'fares/estimate',
      data: {
        'origin': {
          'latitude': originLatitude,
          'longitude': originLongitude,
          'address': originAddress,
        },
        'destination': {
          'latitude': destinationLatitude,
          'longitude': destinationLongitude,
          'address': destinationAddress,
        },
        'isNight': false,
        'isRaining': false,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return FareEstimate.fromJson(data);
  }
}