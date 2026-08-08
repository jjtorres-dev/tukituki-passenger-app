import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/place_details.dart';
import '../domain/place_prediction.dart';

final placesRepositoryProvider =
    Provider<PlacesRepository>((ref) {
  return PlacesRepository(
    ref.watch(dioProvider),
  );
});

class PlacesRepository {
  PlacesRepository(this._dio);

  final Dio _dio;

  Future<List<PlacePrediction>> autocomplete({
    required String input,
    required double latitude,
    required double longitude,
    required String sessionToken,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'places/autocomplete',
      data: {
        'input': input,
        'latitude': latitude,
        'longitude': longitude,
        'sessionToken': sessionToken,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    final rawItems = data['items'];

    if (rawItems is! List) {
      return const [];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => PlacePrediction.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where(
          (item) =>
              item.placeId.isNotEmpty &&
              item.primaryText.isNotEmpty,
        )
        .toList();
  }

  Future<PlaceDetails> getDetails({
    required String placeId,
    required String sessionToken,
  }) async {
    final encodedPlaceId =
        Uri.encodeComponent(placeId);

    final response =
        await _dio.get<Map<String, dynamic>>(
      'places/$encodedPlaceId',
      queryParameters: {
        'sessionToken': sessionToken,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return PlaceDetails.fromJson(data);
  }
}