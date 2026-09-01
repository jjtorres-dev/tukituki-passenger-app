import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/passenger_profile.dart';

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

  /// PATCH `passengers/me` — el backend ya soporta
  /// `UpdatePassengerProfileDto` (todos los campos opcionales). Solo se
  /// envían los campos no nulos: un `null` significa "no lo toques", no
  /// "bórralo". No toca `createMyProfile` (alta) ni `getMyProfile`
  /// (lectura, consumida por el resolver de sesión).
  Future<PassengerProfile> updateMyProfile({
    String? firstName,
    String? lastName,
  }) async {
    final body = <String, dynamic>{
      'firstName': ?firstName,
      'lastName': ?lastName,
    };

    final response = await _dio.patch<Map<String, dynamic>>(
      'passengers/me',
      data: body,
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return PassengerProfile.fromJson(data);
  }
}