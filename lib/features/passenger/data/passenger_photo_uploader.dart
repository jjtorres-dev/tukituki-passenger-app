import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final passengerPhotoUploaderProvider = Provider<PassengerPhotoUploader>((ref) {
  return PassengerPhotoUploader();
});

/// `PUT` directo a una URL presignada de Railway Storage.
///
/// CRÍTICO DE SEGURIDAD: usa un `Dio` efímero, sin `AuthInterceptor`
/// — el `dioProvider` compartido agregaría el Bearer token de sesión
/// de TukiTuki a un dominio de bucket externo, filtrando la
/// credencial. Mismo patrón que `_performRefresh` en
/// `core/network/api_client.dart` y que `DriverPhotoUploader` en el
/// conductor.
///
/// Envía únicamente el header `Content-Type` exacto que exige el
/// presign — nada de `Authorization`, cookies ni headers adicionales.
///
/// DESVIACIÓN DELIBERADA respecto al conductor: el `Dio` efímero fija
/// timeouts propios (15s conexión, 60s envío, 30s recepción). La URL
/// presignada vive 300s; no tiene sentido dejar que una subida colgada
/// espere el timeout infinito por defecto de Dio.
///
/// `dioFactory` es inyectable (por defecto crea el `Dio` con timeouts
/// de arriba) para que los tests puedan sustituirlo por un `Dio` con
/// un `HttpClientAdapter` fijo y verificar el request real sin red,
/// mismo patrón sin librerías de mocking del resto del repo.
class PassengerPhotoUploader {
  PassengerPhotoUploader({Dio Function()? dioFactory})
    : _dioFactory = dioFactory ?? defaultDio;

  final Dio Function() _dioFactory;

  /// `Dio` efímero por defecto: sin interceptores y con timeouts
  /// propios (desviación deliberada respecto al conductor — ver doc de
  /// la clase). Expuesto para test para poder afirmar esos timeouts sin
  /// tocar la red.
  @visibleForTesting
  static Dio defaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  Future<void> upload({
    required String uploadUrl,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final dio = _dioFactory();

    await dio.put<void>(
      uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }
}
