import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

class StorageKeys {
  const StorageKeys._();

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const sessionId = 'session_id';

  /// FARE-PANEL-R1: método de pago referencial elegido por el pasajero,
  /// recordado para el próximo viaje. No es un secreto; vive acá solo
  /// porque `flutter_secure_storage` es el único almacenamiento local
  /// que ya usa la app (sin `shared_preferences`).
  static const paymentMethod = 'payment_method';

  /// `PASSENGER-PUSH-R1`: identificador estable **por instalación de la
  /// app**, no por cuenta. Se genera una sola vez (`DeviceIdStore`,
  /// `Uuid().v4()`) y se envía a Backend en `POST /me/devices` como
  /// `deviceId`.
  ///
  /// Deliberadamente **no** se borra en `AuthRepository.clearSession()`
  /// ni en `AuthInterceptor._clearSession()` (ambos borran una lista
  /// explícita de claves y esta no está en ella): cerrar sesión termina
  /// la sesión, no la identidad del dispositivo. Debe sobrevivir
  /// logout, cambio de cuenta y cerrar/reabrir la app, para que Backend
  /// pueda seguir revocando el registro anterior por `deviceId` cuando
  /// otro pasajero inicia sesión en el mismo teléfono.
  static const deviceId = 'device_id';
}