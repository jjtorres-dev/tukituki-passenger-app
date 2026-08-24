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
    /// true = el destino se eligió tocando el mapa (nunca
    /// autocomplete). Reemplaza la señal implícita que antes se
    /// infería comparando [destinationAddress] contra un literal de
    /// copy de UI — ver `home_screen.dart` (G4B-CONTRACT-R1) y
    /// `fares.service.ts` en el backend.
    bool destinationIsManualSelection = false,
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
          'isManualSelection': destinationIsManualSelection,
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