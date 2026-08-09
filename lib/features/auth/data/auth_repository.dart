import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/public_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(secureStorageProvider),
  );
});

class AuthRepository {
  AuthRepository(
    this._dio,
    this._storage,
  );

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<void> registerPassenger({
    required String phoneE164,
    required String password,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      'auth/register/passenger',
      data: {
        'phoneE164': phoneE164,
        'password': password,
      },
    );
  }

  Future<String?> requestOtp({
    required String phoneE164,
  }) async {
    final response = await _dio.post(
      'auth/otp/request',
      data: {
        'phoneE164': phoneE164,
      },
    );

    final data = response.data;

    if (data is Map) {
      final debugOtp = data['debugOtp'];

      if (debugOtp != null) {
        return debugOtp.toString();
      }
    }

    return null;
  }

  Future<void> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    await _dio.post(
      'auth/otp/verify',
      data: {
        'phoneE164': phoneE164,
        'code': code,
      },
    );
  }

  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/login',
      data: {
        'phoneE164': phoneE164,
        'password': password,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final sessionId = data['sessionId'] as String?;

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      throw Exception(
        'La respuesta de inicio de sesión es inválida.',
      );
    }

    try {
      await _storage.write(
        key: StorageKeys.accessToken,
        value: accessToken,
      );

      await _storage.write(
        key: StorageKeys.refreshToken,
        value: refreshToken,
      );

      await _storage.write(
        key: StorageKeys.sessionId,
        value: sessionId,
      );
    } catch (_) {
      await clearSession();
      rethrow;
    }
  }

  Future<bool> hasSession() async {
    final accessToken = await _storage.read(
      key: StorageKeys.accessToken,
    );

    final refreshToken = await _storage.read(
      key: StorageKeys.refreshToken,
    );

    final sessionId = await _storage.read(
      key: StorageKeys.sessionId,
    );

    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty;
  }

  Future<PublicUser> getMe() async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'auth/me',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend no devolvió los datos del usuario.',
      );
    }

    return PublicUser.fromJson(data);
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>(
        'auth/logout',
      );
    } on DioException {
      // El cierre remoto es best-effort.
      // Aunque el token esté vencido, Railway no responda
      // o el backend devuelva 401, la sesión local debe cerrarse.
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(
      key: StorageKeys.accessToken,
    );

    await _storage.delete(
      key: StorageKeys.refreshToken,
    );

    await _storage.delete(
      key: StorageKeys.sessionId,
    );
  }
}