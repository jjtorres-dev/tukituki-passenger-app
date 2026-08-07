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

  Future<FareEstimate> estimateRide() async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'fares/estimate',
      data: {
        'origin': {
          'latitude': -6.4877,
          'longitude': -76.3599,
          'address': 'Centro de Tarapoto',
        },
        'destination': {
          'latitude': -6.4685,
          'longitude': -76.3430,
          'address': 'Destino de prueba Tarapoto',
        },
        'distanceMeters': 3200,
        'durationSeconds': 720,
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