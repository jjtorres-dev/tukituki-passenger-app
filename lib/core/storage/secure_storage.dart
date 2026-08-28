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
}