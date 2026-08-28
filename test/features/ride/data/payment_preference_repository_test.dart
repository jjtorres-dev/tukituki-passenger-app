import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/data/payment_preference_repository.dart';
import 'package:passenger/features/ride/domain/payment_method.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PaymentPreferenceRepository buildRepository() {
    return PaymentPreferenceRepository(const FlutterSecureStorage());
  }

  test('read() devuelve cash cuando no hay nada guardado', () async {
    FlutterSecureStorage.setMockInitialValues({});

    expect(await buildRepository().read(), PaymentMethod.cash);
  });

  test('write() y luego read() conservan el método elegido', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final repository = buildRepository();

    await repository.write(PaymentMethod.yape);
    expect(await repository.read(), PaymentMethod.yape);

    await repository.write(PaymentMethod.plin);
    expect(await repository.read(), PaymentMethod.plin);
  });

  test('read() cae en cash si el valor guardado no es soportado (CARD)', () async {
    FlutterSecureStorage.setMockInitialValues({'payment_method': 'CARD'});

    expect(await buildRepository().read(), PaymentMethod.cash);
  });

  test('write() guarda el wireValue exacto del backend', () async {
    FlutterSecureStorage.setMockInitialValues({});

    await buildRepository().write(PaymentMethod.yape);

    final raw = await const FlutterSecureStorage().read(key: 'payment_method');
    expect(raw, 'YAPE');
  });
}
