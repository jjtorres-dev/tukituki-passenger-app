import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';
import 'package:passenger/features/ride/domain/passenger_ride_offer.dart';
import 'package:passenger/features/ride/presentation/ride_searching_screen.dart';

void main() {
  testWidgets('renderiza aceptación, lower bid y higher bid simultáneamente', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-a',
          driverName: 'María',
          proposedFare: '7.00',
          isCounterOffer: false,
        ),
        _offer(
          offerId: 'offer-b',
          driverName: 'Carlos',
          proposedFare: '6.00',
          isCounterOffer: false,
        ),
        _offer(
          offerId: 'offer-c',
          driverName: 'José',
          proposedFare: '8.00',
          isCounterOffer: true,
        ),
        _offer(
          offerId: 'expired',
          driverName: 'Expirado',
          proposedFare: '5.00',
          isCounterOffer: true,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(find.text('María'), findsOneWidget);
    expect(find.text('Carlos'), findsOneWidget);
    expect(find.text('José'), findsOneWidget);
    expect(find.text('Expirado'), findsNothing);
    expect(find.text('Acepta tu precio'), findsOneWidget);
    expect(find.text('Contraoferta del conductor'), findsNWidgets(2));
    expect(find.text('Elegir conductor'), findsNWidgets(3));
  });

  for (final statusCode in const [404, 409]) {
    testWidgets('$statusCode al refrescar limpia ofertas obsoletas', (
      tester,
    ) async {
      var offerRequests = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(),
        onGetRideOffers: (_) async {
          offerRequests++;

          if (offerRequests == 1) {
            return [
              _offer(
                offerId: 'offer-a',
                driverName: 'Carlos',
                proposedFare: '7.00',
                isCounterOffer: false,
              ),
            ];
          }

          throw _dioError(statusCode);
        },
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Carlos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      expect(offerRequests, 2);
      expect(find.text('Carlos'), findsNothing);
    });
  }

  testWidgets('el polling no inicia dos cargas de ride simultáneas', (
    tester,
  ) async {
    final pendingRide = Completer<PassengerRide?>();
    final repository = _FakeRideRepository(
      onGetActiveRide: () => pendingRide.future,
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository, flushInitialRequest: false);
    addTearDown(() => _disposeScreen(tester));

    expect(repository.activeRideRequests, 1);

    await tester.pump(const Duration(seconds: 3));

    expect(repository.activeRideRequests, 1);

    pendingRide.complete(_ride(status: 'DRIVER_ASSIGNED', agreedFare: '7.00'));
    await _flushAsync(tester);

    expect(find.text('¡Conductor encontrado!'), findsOneWidget);
  });

  testWidgets(
    'select usa ride real y una respuesta vieja no revierte el estado',
    (tester) async {
      final staleRideResponse = Completer<PassengerRide?>();
      var activeRequest = 0;
      final selectedRide = _ride(status: 'DRIVER_ASSIGNED', agreedFare: '6.00');
      final repository = _FakeRideRepository(
        onGetActiveRide: () {
          activeRequest++;

          if (activeRequest == 1) {
            return Future.value(_ride());
          }

          if (activeRequest == 2) {
            return staleRideResponse.future;
          }

          return Future.value(selectedRide);
        },
        onGetRideOffers: (_) async => [
          _offer(
            offerId: 'offer-b',
            driverName: 'Carlos',
            proposedFare: '6.00',
            isCounterOffer: true,
          ),
        ],
        onSelectRideOffer: ({required rideId, required offerId}) async =>
            selectedRide,
      );

      await _pumpScreen(tester, repository, routeRideId: 'ride-from-url');
      addTearDown(() => _disposeScreen(tester));

      await tester.pump(const Duration(seconds: 3));
      expect(repository.activeRideRequests, 2);

      final selectButton = find.text('Elegir conductor');
      await tester.ensureVisible(selectButton);
      await tester.tap(selectButton);
      await _flushAsync(tester);

      expect(repository.selectedRideId, 'ride-real');
      expect(repository.selectedOfferId, 'offer-b');
      expect(find.text('¡Conductor encontrado!'), findsOneWidget);
      expect(find.text('S/ 6.00'), findsOneWidget);

      staleRideResponse.complete(_ride());
      await _flushAsync(tester);

      expect(find.text('¡Conductor encontrado!'), findsOneWidget);
      expect(find.text('Buscando un conductor...'), findsNothing);
      expect(find.text('S/ 6.00'), findsOneWidget);
    },
  );

  testWidgets('no selecciona una oferta de otro ride', (tester) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-other',
          rideId: 'ride-other',
          driverName: 'Carlos',
          proposedFare: '6.00',
          isCounterOffer: true,
        ),
      ],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    final selectButton = find.text('Elegir conductor');
    await tester.ensureVisible(selectButton);
    await tester.tap(selectButton);
    await _flushAsync(tester);

    expect(repository.selectRequests, 0);
    expect(
      find.text('Esta propuesta no corresponde al viaje actual.'),
      findsOneWidget,
    );
  });
}

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({
    required this.onGetActiveRide,
    required this.onGetRideOffers,
    this.onSelectRideOffer,
  }) : super(Dio());

  final Future<PassengerRide?> Function() onGetActiveRide;
  final Future<List<PassengerRideOffer>> Function(String rideId)
  onGetRideOffers;
  final Future<PassengerRide> Function({
    required String rideId,
    required String offerId,
  })?
  onSelectRideOffer;

  int activeRideRequests = 0;
  int selectRequests = 0;
  String? selectedRideId;
  String? selectedOfferId;

  @override
  Future<PassengerRide?> getActiveRide() {
    activeRideRequests++;
    return onGetActiveRide();
  }

  @override
  Future<List<PassengerRideOffer>> getRideOffers(String rideId) {
    return onGetRideOffers(rideId);
  }

  @override
  Future<PassengerRide> selectRideOffer({
    required String rideId,
    required String offerId,
  }) {
    selectRequests++;
    selectedRideId = rideId;
    selectedOfferId = offerId;

    final handler = onSelectRideOffer;

    if (handler == null) {
      throw StateError('Select no configurado');
    }

    return handler(rideId: rideId, offerId: offerId);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  RideRepository repository, {
  String routeRideId = 'ride-real',
  bool flushInitialRequest = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rideRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: RideSearchingScreen(rideId: routeRideId)),
    ),
  );

  if (flushInitialRequest) {
    await _flushAsync(tester);
  }
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

DioException _dioError(int statusCode) {
  final requestOptions = RequestOptions(
    path: 'passenger/rides/ride-real/offers',
  );

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(
      requestOptions: requestOptions,
      statusCode: statusCode,
    ),
  );
}

PassengerRide _ride({String status = 'SEARCHING_DRIVER', String? agreedFare}) {
  return PassengerRide(
    id: 'ride-real',
    fareQuoteId: 'quote-1',
    status: status,
    distanceMeters: 1500,
    estimatedDurationSeconds: 600,
    estimatedFare: '7.00',
    estimatedPassengerFare: '7.00',
    passengerOfferFare: '7.00',
    agreedFare: agreedFare,
    currency: 'PEN',
    paymentMethod: 'CASH',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    requestedAt: DateTime.utc(2026, 8, 9),
    searchExpiresAt: null,
  );
}

PassengerRideOffer _offer({
  required String offerId,
  required String driverName,
  required String proposedFare,
  required bool isCounterOffer,
  String rideId = 'ride-real',
  DateTime? expiresAt,
}) {
  return PassengerRideOffer(
    offerId: offerId,
    rideId: rideId,
    driverProfileId: 'driver-$offerId',
    driverFirstName: driverName,
    driverLastNameInitial: '',
    photoUrl: null,
    ratingAverage: 4.8,
    ratingCount: 10,
    distanceToOriginMeters: 300,
    passengerOfferFare: '7.00',
    proposedFare: proposedFare,
    isCounterOffer: isCounterOffer,
    currency: 'PEN',
    proposedAt: DateTime.utc(2026, 8, 9),
    expiresAt: expiresAt,
  );
}
