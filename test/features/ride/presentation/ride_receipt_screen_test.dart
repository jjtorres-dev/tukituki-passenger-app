import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/ride_receipt.dart';
import 'package:passenger/features/ride/presentation/ride_receipt_screen.dart';

void main() {
  group('PENDING', () {
    testWidgets(
      'muestra agradecimiento, total real, método y estado pendiente',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetReceipt: () async =>
              _receipt(payment: _payment(status: 'PENDING')),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.text('¡Gracias por viajar!'), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('receipt-total-amount')),
              )
              .data,
          'S/ 8.50',
        );
        expect(find.text('Efectivo'), findsOneWidget);
        expect(find.text('Pendiente'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment-waiting-message')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'no existe confirmación de pago desde el pasajero ni Yape/tarjeta',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetReceipt: () async =>
              _receipt(payment: _payment(status: 'PENDING')),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.textContaining('Confirmar pago'), findsNothing);
        expect(find.textContaining('Ya pagué'), findsNothing);
        expect(find.textContaining('Marcar pagado'), findsNothing);
        expect(find.textContaining('Yape'), findsNothing);
        expect(find.textContaining('Tarjeta'), findsNothing);
        expect(find.textContaining('QR'), findsNothing);
        expect(find.textContaining('pasarela'), findsNothing);
      },
    );

    testWidgets('rating no puede enviarse mientras el pago está pendiente', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async =>
            _receipt(payment: _payment(status: 'PENDING')),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      final disabledCta = find.byKey(const ValueKey('rating-disabled-cta'));
      expect(disabledCta, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(disabledCta).onPressed,
        isNull,
      );
      expect(find.text('Enviar calificación'), findsNothing);
      expect(find.text('¿Cómo estuvo tu viaje?'), findsNothing);
      expect(repository.ratedScore, isNull);
    });

    testWidgets('distancia y duración reales se muestran cuando existen', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async => _receipt(
          actualDistanceMeters: 4200,
          actualDurationSeconds: 900,
          payment: _payment(status: 'PENDING'),
        ),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(
        find.byKey(const ValueKey('receipt-distance-row')),
        findsOneWidget,
      );
      expect(find.text('4.2 km'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('receipt-duration-row')),
        findsOneWidget,
      );
      expect(find.text('15 min'), findsOneWidget);
    });

    testWidgets('métricas en cero no muestran valores ficticios', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async => _receipt(
          actualDistanceMeters: 0,
          actualDurationSeconds: 0,
          payment: _payment(status: 'PENDING'),
        ),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(
        find.byKey(const ValueKey('receipt-distance-row')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('receipt-duration-row')),
        findsNothing,
      );
      expect(find.text('0.0 km'), findsNothing);
      expect(find.text('0 min'), findsNothing);
      expect(find.text('0 s'), findsNothing);
    });
  });

  group('PAID', () {
    testWidgets('muestra estado pagado y total real', (tester) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async =>
            _receipt(payment: _payment(status: 'PAID', amountDue: '8.50')),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Pagado'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('receipt-total-amount')),
            )
            .data,
        'S/ 8.50',
      );
    });

    testWidgets('cashReceived y changeGiven se muestran cuando existen', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async => _receipt(
          payment: _payment(
            status: 'PAID',
            cashReceived: '10.00',
            changeGiven: '1.50',
          ),
        ),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(
        find.byKey(const ValueKey('payment-cash-received')),
        findsOneWidget,
      );
      expect(find.text('S/ 10.00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment-change-given')),
        findsOneWidget,
      );
      expect(find.text('S/ 1.50'), findsOneWidget);
    });

    testWidgets('sin cashReceived/changeGiven no inventa valores', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async =>
            _receipt(payment: _payment(status: 'PAID')),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(
        find.byKey(const ValueKey('payment-cash-received')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment-change-given')),
        findsNothing,
      );
      expect(find.text('S/ 0.00'), findsNothing);
    });

    testWidgets(
      'rating queda habilitado y usable, submitRating no cambia de contrato',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetReceipt: () async =>
              _receipt(payment: _payment(status: 'PAID')),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.text('¿Cómo estuvo tu viaje?'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('rating-disabled-cta')),
          findsNothing,
        );

        final submitButton = find.text('Enviar calificación');
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await _flushAsync(tester);

        expect(repository.ratedRideId, 'ride-real');
        expect(repository.ratedScore, 5);
        expect(repository.ratedTags, isEmpty);
        expect(find.text('¡Gracias por calificarnos!'), findsOneWidget);
      },
    );
  });

  group('polling PENDING -> PAID', () {
    testWidgets(
      'la UI cambia automáticamente a pagado sin navegación manual',
      (tester) async {
        var call = 0;
        final repository = _FakeRideRepository(
          onGetReceipt: () async {
            call++;

            if (call == 1) {
              return _receipt(payment: _payment(status: 'PENDING'));
            }

            return _receipt(
              payment: _payment(
                status: 'PAID',
                cashReceived: '10.00',
                changeGiven: '1.50',
              ),
            );
          },
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.text('Pendiente'), findsOneWidget);
        expect(find.text('Pagado'), findsNothing);

        await tester.pump(const Duration(seconds: 2));
        await _flushAsync(tester);

        expect(find.text('Pagado'), findsOneWidget);
        expect(find.text('Pendiente'), findsNothing);
        expect(
          find.byKey(const ValueKey('payment-cash-received')),
          findsOneWidget,
        );
        expect(repository.receiptRequests, greaterThanOrEqualTo(2));
      },
    );
  });

  group('estados terminales', () {
    for (final status in const ['FAILED', 'EXPIRED', 'DISPUTED', 'VOIDED']) {
      testWidgets(
        '$status no crashea, no se muestra como pagado y no habilita rating',
        (tester) async {
          final repository = _FakeRideRepository(
            onGetReceipt: () async =>
                _receipt(payment: _payment(status: status)),
          );

          await _pumpScreen(tester, repository);
          addTearDown(() => _disposeScreen(tester));

          expect(tester.takeException(), isNull);
          expect(find.text('Pagado'), findsNothing);
          expect(find.text('¿Cómo estuvo tu viaje?'), findsNothing);
          expect(
            find.byKey(const ValueKey('rating-disabled-cta')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('payment-status-terminal')),
            findsOneWidget,
          );
        },
      );
    }
  });

  group('restore directo', () {
    testWidgets('COMPLETED + PENDING renderiza sin pasar por IN_PROGRESS', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async =>
            _receipt(status: 'COMPLETED', payment: _payment(status: 'PENDING')),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('¡Gracias por viajar!'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('COMPLETED + PAID renderiza sin pasar por IN_PROGRESS', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async =>
            _receipt(status: 'COMPLETED', payment: _payment(status: 'PAID')),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Pagado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('carga y error', () {
    testWidgets('error al cargar el recibo no crashea y muestra mensaje', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetReceipt: () async => throw _dioError(),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('No se pudo cargar el recibo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive', () {
    testWidgets('PENDING en 360x640 con dirección larga no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetReceipt: () async => _receipt(
          destinationAddress:
              'Jr. Los Alisos Manzana G Lote 15, Urbanización '
              'San Antonio de Padua, Tarapoto, San Martín',
          payment: _payment(status: 'PENDING'),
        ),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('receipt-scroll')),
        const Offset(0, -400),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'PAID con cashReceived/changeGiven en 390x844 no produce overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = _FakeRideRepository(
          onGetReceipt: () async => _receipt(
            payment: _payment(
              status: 'PAID',
              cashReceived: '10.00',
              changeGiven: '1.50',
            ),
          ),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({required this.onGetReceipt}) : super(Dio());

  final Future<RideReceipt> Function() onGetReceipt;

  int receiptRequests = 0;
  String? ratedRideId;
  int? ratedScore;
  String? ratedComment;
  List<String>? ratedTags;

  @override
  Future<RideReceipt> getReceipt(String rideId) {
    receiptRequests++;
    return onGetReceipt();
  }

  @override
  Future<void> submitRating({
    required String rideId,
    required int score,
    String? comment,
    List<String> tags = const [],
  }) async {
    ratedRideId = rideId;
    ratedScore = score;
    ratedComment = comment;
    ratedTags = tags;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  RideRepository repository, {
  String rideId = 'ride-real',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rideRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: RideReceiptScreen(rideId: rideId)),
    ),
  );

  await _flushAsync(tester);
}

Future<void> _flushAsync(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

DioException _dioError() {
  final requestOptions = RequestOptions(
    path: 'passenger/rides/ride-real/receipt',
  );

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(requestOptions: requestOptions, statusCode: 500),
  );
}

RideReceipt _receipt({
  String rideId = 'ride-real',
  String status = 'COMPLETED',
  String originAddress = 'Jr. Los Andes 120',
  String destinationAddress = 'Plaza de Armas',
  num actualDistanceMeters = 3200,
  num actualDurationSeconds = 780,
  String finalFare = '8.50',
  RideReceiptPayment? payment,
}) {
  return RideReceipt(
    rideId: rideId,
    status: status,
    originAddress: originAddress,
    destinationAddress: destinationAddress,
    startedAt: DateTime.utc(2026, 8, 9, 10),
    completedAt: DateTime.utc(2026, 8, 9, 10, 20),
    actualDistanceMeters: actualDistanceMeters,
    actualDurationSeconds: actualDurationSeconds,
    estimatedFare: finalFare,
    fare: _fare(finalFare: finalFare),
    payment: payment,
  );
}

RideReceiptFare _fare({String finalFare = '8.50'}) {
  return RideReceiptFare(
    baseFare: '3.00',
    distanceAmount: '3.00',
    timeAmount: '2.50',
    bookingFee: '0.00',
    subtotal: finalFare,
    adjustmentMultiplier: '1.000',
    calculatedFinalFare: finalFare,
    finalFare: finalFare,
    fareCapAmount: '0.00',
    fareWasCapped: false,
    currency: 'PEN',
  );
}

RideReceiptPayment _payment({
  String method = 'CASH',
  required String status,
  String amountDue = '8.50',
  String grossAmount = '8.50',
  String discountAmount = '0.00',
  String? cashReceived,
  String? changeGiven,
  DateTime? confirmedAt,
}) {
  return RideReceiptPayment(
    method: method,
    status: status,
    amountDue: amountDue,
    grossAmount: grossAmount,
    discountAmount: discountAmount,
    cashReceived: cashReceived,
    changeGiven: changeGiven,
    confirmedAt: confirmedAt,
  );
}
