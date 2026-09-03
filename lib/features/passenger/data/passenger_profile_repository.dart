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

  /// Centinela para distinguir "no toques el correo" (parámetro
  /// omitido) de "borra el correo" (`email: null` explícito). Un
  /// `String?` no alcanza: `null` sería ambiguo entre ambos. La clave
  /// `email` solo viaja en el body cuando el llamador pasó algo
  /// distinto de este centinela.
  static const Object _emailUnchanged = Object();

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
  /// `UpdatePassengerProfileDto` (todos los campos opcionales). Para
  /// `firstName`/`lastName` se usa el patrón null-aware: un `null` (o
  /// ausente) significa "no lo toques" y la clave ni siquiera viaja.
  ///
  /// `email` es distinto: además de "no lo toques" (parámetro omitido →
  /// centinela) tiene que poder expresar "bórralo" (`email: null`
  /// explícito → clave `email` con valor `null` en el body, que el
  /// backend interpreta como limpiar el campo). No toca `createMyProfile`
  /// (alta) ni `getMyProfile` (lectura, consumida por el resolver de
  /// sesión).
  Future<PassengerProfile> updateMyProfile({
    String? firstName,
    String? lastName,
    Object? email = _emailUnchanged,
  }) async {
    final body = <String, dynamic>{
      'firstName': ?firstName,
      'lastName': ?lastName,
    };

    if (!identical(email, _emailUnchanged)) {
      body['email'] = email;
    }

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