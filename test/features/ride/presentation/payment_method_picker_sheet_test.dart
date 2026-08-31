import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/domain/payment_method.dart';
import 'package:passenger/features/ride/presentation/payment_method_picker_sheet.dart';

/// Extraída de `home_screen.dart` en la Etapa 4 de `FARE-PANEL-R1` para
/// reutilizarla desde `OfferFareScreen` sin duplicar código — este
/// archivo cubre el widget en aislamiento; `home_screen_test.dart` y
/// `offer_fare_screen_test.dart` la ejercen indirectamente desde cada
/// pantalla que la abre.
void main() {
  final resultHolder = <PaymentMethod?>[];

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    required PaymentMethod current,
  }) async {
    resultHolder.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await showModalBottomSheet<PaymentMethod>(
                  context: context,
                  builder: (_) => PaymentMethodPickerSheet(current: current),
                );
                resultHolder.add(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra las tres opciones con un check sobre la actual', (
    tester,
  ) async {
    await pumpAndOpen(tester, current: PaymentMethod.yape);

    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Yape'), findsOneWidget);
    expect(find.text('Plin'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tocar una opción hace pop con el método tocado', (
    tester,
  ) async {
    await pumpAndOpen(tester, current: PaymentMethod.cash);

    await tester.tap(find.byKey(const ValueKey('payment-option-plin')));
    await tester.pumpAndSettle();

    expect(resultHolder, [PaymentMethod.plin]);
  });
}
