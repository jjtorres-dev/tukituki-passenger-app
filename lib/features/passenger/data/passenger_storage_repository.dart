import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Única categoría de Storage que esta app necesita hoy:
/// `StorageCategory.PASSENGER_PROFILE_PHOTO` en el backend
/// (`storage-category.policy.ts`). A diferencia del conductor —que sube
/// también licencia/SOAT/TIV— acá la categoría va hardcodeada: no hay
/// segundo caso de uso que justifique parametrizarla.
const String passengerProfilePhotoStorageCategory = 'PASSENGER_PROFILE_PHOTO';

final passengerStorageRepositoryProvider = Provider<PassengerStorageRepository>((
  ref,
) {
  return PassengerStorageRepository(ref.watch(dioProvider));
});

/// Resultado de `POST storage/uploads/presign`.
class PassengerPresignedUpload {
  const PassengerPresignedUpload({
    required this.objectKey,
    required this.uploadUrl,
    required this.contentType,
  });

  final String objectKey;
  final String uploadUrl;

  /// `requiredHeaders['Content-Type']` tal como lo devuelve el backend
  /// — el único header exigido por la URL presignada.
  final String contentType;
}

/// `POST storage/uploads/presign` + `POST storage/uploads/complete`
/// contra el backend de TukiTuki (autenticado, vía `dioProvider`).
///
/// El `PUT` real al bucket NO vive acá — ver [PassengerPhotoUploader],
/// que usa un `Dio` aislado sin `AuthInterceptor` para no filtrar el
/// Bearer token de TukiTuki a un dominio de bucket externo. Mismo
/// patrón que `DriverStorageRepository` en el conductor, recortado a
/// una sola categoría.
class PassengerStorageRepository {
  PassengerStorageRepository(this._dio);

  final Dio _dio;

  Future<PassengerPresignedUpload> presignProfilePhotoUpload({
    required String contentType,
    required int fileSize,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'storage/uploads/presign',
      data: {
        'category': passengerProfilePhotoStorageCategory,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    final objectKey = data['objectKey'] as String?;
    final uploadUrl = data['uploadUrl'] as String?;
    final requiredHeaders = data['requiredHeaders'] as Map<String, dynamic>?;
    final requiredContentType = requiredHeaders?['Content-Type'] as String?;

    if (objectKey == null ||
        objectKey.isEmpty ||
        uploadUrl == null ||
        uploadUrl.isEmpty ||
        requiredContentType == null ||
        requiredContentType.isEmpty) {
      throw Exception('La respuesta de presign de Storage es inválida.');
    }

    return PassengerPresignedUpload(
      objectKey: objectKey,
      uploadUrl: uploadUrl,
      contentType: requiredContentType,
    );
  }

  Future<void> completeProfilePhotoUpload({required String objectKey}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'storage/uploads/complete',
      data: {
        'category': passengerProfilePhotoStorageCategory,
        'objectKey': objectKey,
      },
    );

    if (response.data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }
  }
}
