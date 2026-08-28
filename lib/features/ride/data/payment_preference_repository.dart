import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/storage/secure_storage.dart';
import '../domain/payment_method.dart';

final paymentPreferenceRepositoryProvider = Provider<PaymentPreferenceRepository>(
  (ref) => PaymentPreferenceRepository(ref.watch(secureStorageProvider)),
);

/// Persiste localmente el método de pago elegido por el pasajero para
/// recordarlo en el próximo viaje (`FARE-PANEL-R1`).
///
/// Guarda en `flutter_secure_storage` — el único almacenamiento local
/// que ya usa la app (no hay `shared_preferences` en `pubspec.yaml`).
/// El método de pago no es un secreto; se usa este mecanismo solo para
/// no agregar una dependencia nueva. Es un dato **por dispositivo, no
/// por cuenta**: al cambiar de celular el pasajero elige de nuevo, sin
/// consecuencia.
class PaymentPreferenceRepository {
  PaymentPreferenceRepository(this._storage);

  final FlutterSecureStorage _storage;

  /// Método guardado, o [PaymentMethod.cash] si no hay nada guardado o
  /// si el valor almacenado no es uno de los tres soportados.
  Future<PaymentMethod> read() async {
    final raw = await _storage.read(key: StorageKeys.paymentMethod);
    return PaymentMethod.parse(raw);
  }

  Future<void> write(PaymentMethod method) {
    return _storage.write(
      key: StorageKeys.paymentMethod,
      value: method.wireValue,
    );
  }
}
