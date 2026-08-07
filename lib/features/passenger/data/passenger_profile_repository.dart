import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final passengerProfileRepositoryProvider =
    Provider<PassengerProfileRepository>((ref) {
  return PassengerProfileRepository(
    ref.watch(dioProvider),
  );
});

class PassengerProfileRepository {
  PassengerProfileRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>(
        'passengers/me',
      );

      return response.data;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  Future<Map<String, dynamic>> createMyProfile({
    required String firstName,
    required String lastName,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'passengers/me',
      data: {
        'firstName': firstName,
        'lastName': lastName,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return data;
  }
}