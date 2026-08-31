import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/home/domain/offer_fare_result.dart';
import 'package:passenger/features/home/offer_fare_screen.dart';
import 'package:passenger/features/ride/domain/payment_method.dart';

void main() {
  const originAddress = 'Jr. Lima 123, Tarapoto';
  const destinationName = 'Plaza de Armas';
  const destinationAddress = 'Jr. San Martín 100, Tarapoto';

  /// Mismo motivo que `search_destination_screen_test.dart`: el
  /// `Future` de `Navigator.push` recién se completa cuando la
  /// pantalla hace `pop`, mucho después de que `pumpAndPush` ya
  /// volvió — los tests que necesitan el resultado lo leen de acá.
  final resultHolder = <OfferFareResult?>[];

  Future<void> pumpAndPush(
    WidgetTester tester, {
    int offerCents = 300,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    resultHolder.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push<OfferFareResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OfferFareScreen(
                      offerCents: offerCents,
                      paymentMethod: paymentMethod,
                      originAddress: originAddress,
                      destinationName: destinationName,
                      destinationAddress: destinationAddress,
                    ),
                  ),
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

  final amountFieldFinder = find.byKey(
    const ValueKey('offer-fare-amount-field'),
  );
  final confirmButtonFinder = find.byKey(
    const ValueKey('offer-fare-confirm-button'),
  );

  String shownAmount(WidgetTester tester) =>
      tester.widget<TextField>(amountFieldFinder).controller!.text;

  testWidgets(
    'muestra el monto, origen y destino iniciales que recibe por '
    'constructor',
    (tester) async {
      await pumpAndPush(
        tester,
        offerCents: 350,
        paymentMethod: PaymentMethod.yape,
      );

      expect(shownAmount(tester), '3.50');
      expect(find.text(originAddress), findsOneWidget);
      expect(find.text(destinationName), findsOneWidget);
      expect(find.text(destinationAddress), findsOneWidget);
      expect(find.text('Yape'), findsOneWidget);
    },
  );

  testWidgets(
    'escribir un monto válido habilita el CTA; confirmar devuelve el '
    'resultado por pop',
    (tester) async {
      await pumpAndPush(tester);

      await tester.enterText(amountFieldFinder, '15.75');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
      );

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(resultHolder, hasLength(1));
      expect(resultHolder.single!.offerCents, 1575);
      expect(resultHolder.single!.paymentMethod, PaymentMethod.cash);
    },
  );

  testWidgets(
    'un monto fuera de rango deshabilita el CTA con la línea explicativa',
    (tester) async {
      await pumpAndPush(tester);

      await tester.enterText(amountFieldFinder, '100');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNull,
      );
      expect(
        find.text('Ingresa un monto entre S/3.00 y S/50.00 para continuar.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'un monto por encima del máximo se ajusta a S/50.00 al perder el foco',
    (tester) async {
      await pumpAndPush(tester);

      await tester.enterText(amountFieldFinder, '100');
      await tester.pump();

      // `TextInputAction.done` sin `onEditingComplete` propio dispara el
      // comportamiento por defecto de `EditableText`: quita el foco del
      // campo, disparando el listener de `FocusNode` que hace el clamp.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(shownAmount(tester), '50.00');
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'un monto por debajo del mínimo se ajusta a S/3.00 al perder el foco',
    (tester) async {
      await pumpAndPush(tester, offerCents: 1000);

      await tester.enterText(amountFieldFinder, '0.50');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(shownAmount(tester), '3.00');
    },
  );

  testWidgets(
    'un campo vacío vuelve al último monto válido al perder el foco',
    (tester) async {
      await pumpAndPush(tester, offerCents: 700);

      await tester.enterText(amountFieldFinder, '');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNull,
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(shownAmount(tester), '7.00');
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'el selector de método de pago abre la hoja compartida y actualiza '
    'la fila al elegir uno nuevo',
    (tester) async {
      await pumpAndPush(tester);

      expect(find.text('Efectivo'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('offer-fare-payment-method-row')),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Cómo vas a pagar?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payment-option-plin')));
      await tester.pumpAndSettle();

      expect(find.text('Plin'), findsOneWidget);

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(resultHolder.single!.paymentMethod, PaymentMethod.plin);
    },
  );

  testWidgets('el botón "Cerrar" hace pop sin resultado', (tester) async {
    await pumpAndPush(tester);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(resultHolder, [null]);
  });
}
