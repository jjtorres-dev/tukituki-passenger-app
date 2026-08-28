import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/domain/payment_method.dart';

void main() {
  test('values expone exactamente Efectivo, Yape, Plin en ese orden', () {
    expect(PaymentMethod.values, [
      PaymentMethod.cash,
      PaymentMethod.yape,
      PaymentMethod.plin,
    ]);
  });

  group('wireValue', () {
    test('mapea cada método al string exacto del backend', () {
      expect(PaymentMethod.cash.wireValue, 'CASH');
      expect(PaymentMethod.yape.wireValue, 'YAPE');
      expect(PaymentMethod.plin.wireValue, 'PLIN');
    });
  });

  group('label', () {
    test('etiqueta visible en español', () {
      expect(PaymentMethod.cash.label, 'Efectivo');
      expect(PaymentMethod.yape.label, 'Yape');
      expect(PaymentMethod.plin.label, 'Plin');
    });
  });

  group('parse', () {
    test('reconoce los tres soportados, sin importar caja ni espacios', () {
      expect(PaymentMethod.parse('CASH'), PaymentMethod.cash);
      expect(PaymentMethod.parse('yape'), PaymentMethod.yape);
      expect(PaymentMethod.parse('  Plin '), PaymentMethod.plin);
    });

    test('CARD cae en cash — la app no ofrece tarjeta', () {
      expect(PaymentMethod.parse('CARD'), PaymentMethod.cash);
    });

    test('null, vacío o basura caen en cash', () {
      expect(PaymentMethod.parse(null), PaymentMethod.cash);
      expect(PaymentMethod.parse(''), PaymentMethod.cash);
      expect(PaymentMethod.parse('   '), PaymentMethod.cash);
      expect(PaymentMethod.parse('xyz'), PaymentMethod.cash);
    });
  });
}
