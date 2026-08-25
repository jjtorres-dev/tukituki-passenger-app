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

  /// Reverse geocoding liviano de un punto GPS (ORIGIN-ADDRESS-R1):
  /// resuelve la dirección real de [latitude]/[longitude] sin generar
  /// una cotización completa. A diferencia de [estimateRide], nunca
  /// lanza por un fallo de Google Geocoding del lado del backend —
  /// ese caso ya devuelve un fallback honesto (`'Ubicación
  /// seleccionada'`) con 200. Sí puede lanzar por [DioException] (sin
  /// conexión, timeout, o 429 si el pasajero superó el límite de
  /// solicitudes) — responsabilidad del caller decidir qué mostrar en
  /// ese caso (ver `home_screen.dart`).
  Future<String> getOriginAddress({
    required double latitude,
    required double longitude,
  }) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'fares/origin-address',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return data['address']?.toString() ?? '';
  }

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