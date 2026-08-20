import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/assigned_driver.dart';
import 'package:passenger/features/ride/domain/driver_location.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';
import 'package:passenger/features/ride/domain/passenger_ride_offer.dart';
import 'package:passenger/features/ride/domain/passenger_ride_start_code.dart';
import 'package:passenger/features/ride/presentation/ride_searching_screen.dart';

void main() {
  testWidgets('SEARCHING_DRIVER muestra viaje real, métricas y estado vacío', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(
        passengerOfferFare: '5.70',
        originAddress: 'Jr. Los Andes 120',
        destinationAddress: 'Plaza de Armas',
        distanceMeters: 2100,
        estimatedDurationSeconds: 360,
      ),
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(find.text('Buscando un conductor...'), findsOneWidget);
    expect(find.text('TukiTuki'), findsOneWidget);
    expect(find.text('Tu TukiTuki'), findsNothing);
    expect(
      find.byKey(const ValueKey('cancel-search-close-button')),
      findsOneWidget,
    );
    expect(find.text('TU OFERTA'), findsOneWidget);
    expect(find.text('S/ 5.70'), findsOneWidget);
    expect(find.text('Jr. Los Andes 120'), findsOneWidget);
    expect(find.text('Plaza de Armas'), findsOneWidget);
    expect(find.text('2.1 km'), findsOneWidget);
    expect(find.text('6 min'), findsOneWidget);
    expect(
      find.text('Todavía no hay conductores interesados.'),
      findsOneWidget,
    );
    expect(find.text('Seguimos buscando por ti.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('offers-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('métricas no válidas no reservan chips falsos', (tester) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async =>
          _ride(distanceMeters: 0, estimatedDurationSeconds: -1),
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(find.byKey(const ValueKey('ride-distance-chip')), findsNothing);
    expect(find.byKey(const ValueKey('ride-duration-chip')), findsNothing);
    expect(find.text('0 m'), findsNothing);
    expect(find.text('0 min'), findsNothing);
  });

  testWidgets('oferta muestra identidad, rating, distancia y precio reales', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(passengerOfferFare: '5.70'),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-julio',
          driverName: 'Julio',
          driverLastNameInitial: 'R',
          proposedFare: '6.00',
          isCounterOffer: true,
          ratingAverage: 4.9,
          ratingCount: 21,
          distanceToOriginMeters: 850,
          passengerOfferFare: '5.70',
        ),
        _offer(
          offerId: 'offer-new',
          driverName: 'Conductor',
          proposedFare: '5.70',
          isCounterOffer: false,
          ratingAverage: 0,
          ratingCount: 0,
          distanceToOriginMeters: 0,
          passengerOfferFare: '5.70',
        ),
      ],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(find.text('Julio R.'), findsOneWidget);
    expect(find.text('JR'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text('A 850 m de tu origen'), findsOneWidget);
    expect(find.text('S/ 6.00'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('offers-count')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('coordenadas válidas construyen el GoogleMap real', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(
        originLatitude: -6.4877,
        originLongitude: -76.3599,
        destinationLatitude: -6.4812,
        destinationLongitude: -76.3651,
      ),
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(
      find.byKey(const ValueKey('ride-search-google-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-search-map-placeholder')),
      findsNothing,
    );
  });

  testWidgets('sin coordenadas no construye mapa ni LatLng de fallback', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(find.byKey(const ValueKey('ride-search-google-map')), findsNothing);
    expect(
      find.byKey(const ValueKey('ride-search-map-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('una sola coordenada válida mantiene disponible el mapa', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async =>
          _ride(originLatitude: -6.4877, originLongitude: -76.3599),
      onGetRideOffers: (_) async => const [],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(
      find.byKey(const ValueKey('ride-search-google-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-search-map-placeholder')),
      findsNothing,
    );
  });

  testWidgets('viewport 360x640 soporta varias ofertas sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        for (var index = 0; index < 5; index++)
          _offer(
            offerId: 'offer-$index',
            driverName: 'Conductor $index',
            proposedFare: '${7 + index}.00',
            isCounterOffer: index > 0,
          ),
      ],
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('ride-search-scroll')),
      const Offset(0, -1800),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('cancel-search-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('X superior abre la misma confirmación de cancelación', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await tester.tap(find.byKey(const ValueKey('cancel-search-close-button')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('¿Cancelar la búsqueda?'), findsOneWidget);
    expect(find.text('Tu solicitud de viaje será cancelada.'), findsOneWidget);
    expect(repository.cancelRequests, 0);
  });

  testWidgets('COMPLETED conserva navegación al receipt', (tester) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(status: 'COMPLETED'),
      onGetRideOffers: (_) async => const [],
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    expect(
      router.routeInformationProvider.value.uri.path,
      '/ride/ride-real/receipt',
    );
    expect(find.text('RECEIPT_DESTINATION'), findsOneWidget);
  });

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
    expect(find.text('Aceptar'), findsNWidgets(3));
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

      final selectButton = find.text('Aceptar');
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

    final selectButton = find.text('Aceptar');
    await tester.ensureVisible(selectButton);
    await tester.tap(selectButton);
    await _flushAsync(tester);

    expect(repository.selectRequests, 0);
    expect(
      find.text('Esta propuesta no corresponde al viaje actual.'),
      findsOneWidget,
    );
  });

  testWidgets('SEARCHING_DRIVER permite iniciar cancelación', (tester) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    final cancelButton = find.byKey(const ValueKey('cancel-search-button'));
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNotNull);

    await _openCancelDialog(tester);

    expect(find.text('¿Cancelar la búsqueda?'), findsOneWidget);
    expect(find.text('Tu solicitud de viaje será cancelada.'), findsOneWidget);
  });

  testWidgets('Seguir buscando cierra diálogo sin llamar cancelRide', (
    tester,
  ) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await _openCancelDialog(tester);
    await tester.tap(find.text('Seguir buscando'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.cancelRequests, 0);
    expect(router.routeInformationProvider.value.uri.path, '/ride/ride-real');
    expect(find.text('Buscando un conductor...'), findsOneWidget);
  });

  testWidgets('confirmar y doble tap producen una sola cancelación', (
    tester,
  ) async {
    final pendingCancellation = Completer<PassengerRide>();
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
      onCancelRide: (_) => pendingCancellation.future,
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await _openCancelDialog(tester);
    await tester.tap(find.text('Cancelar viaje'));
    await _flushAsync(tester);

    final cancelButton = find.byKey(const ValueKey('cancel-search-button'));
    expect(repository.cancelRequests, 1);
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNull);

    await tester.tap(cancelButton);
    await _flushAsync(tester);
    expect(repository.cancelRequests, 1);

    pendingCancellation.completeError(_dioCancelError(409));
    await _flushAsync(tester);
  });

  testWidgets('cancelación CANCELLED limpia y navega a home', (tester) async {
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-a',
          driverName: 'Carlos',
          proposedFare: '7.00',
          isCounterOffer: false,
        ),
      ],
      onCancelRide: (_) async => _ride(status: 'CANCELLED'),
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    expect(find.text('Carlos'), findsOneWidget);

    await _openCancelDialog(tester);
    await tester.tap(find.text('Cancelar viaje'));
    await tester.pumpAndSettle();

    expect(repository.cancelRequests, 1);
    expect(repository.cancelledRideId, 'ride-real');
    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.text('HOME_DESTINATION'), findsOneWidget);
    expect(find.text('Carlos'), findsNothing);
  });

  testWidgets('error de cancelación mantiene pantalla y reanuda polling', (
    tester,
  ) async {
    final pendingCancellation = Completer<PassengerRide>();
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => const [],
      onCancelRide: (_) => pendingCancellation.future,
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await _openCancelDialog(tester);
    await tester.tap(find.text('Cancelar viaje'));
    await _flushAsync(tester);

    await tester.pump(const Duration(seconds: 3));
    expect(repository.activeRideRequests, 1);

    pendingCancellation.completeError(_dioCancelNetworkError());
    await _flushAsync(tester);

    expect(router.routeInformationProvider.value.uri.path, '/ride/ride-real');
    expect(
      find.text(
        'No se pudo conectar con TukiTuki. '
        'Revisa tu conexión e intenta nuevamente.',
      ),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('ride-search-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('offers-empty-state')), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await _flushAsync(tester);
    expect(repository.activeRideRequests, 2);
  });

  testWidgets('mientras selecciona oferta la cancelación está bloqueada', (
    tester,
  ) async {
    final pendingSelection = Completer<PassengerRide>();
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-a',
          driverName: 'Carlos',
          proposedFare: '7.00',
          isCounterOffer: false,
        ),
        _offer(
          offerId: 'offer-b',
          driverName: 'María',
          proposedFare: '8.00',
          isCounterOffer: true,
        ),
      ],
      onSelectRideOffer: ({required rideId, required offerId}) =>
          pendingSelection.future,
    );

    await _pumpScreen(tester, repository);
    addTearDown(() => _disposeScreen(tester));

    final firstSelectButton = find.byKey(
      const ValueKey('accept-offer-offer-a'),
    );
    await tester.ensureVisible(firstSelectButton);
    await tester.tap(firstSelectButton);
    await _flushAsync(tester);

    final cancelButton = find.byKey(const ValueKey('cancel-search-button'));
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNull);
    expect(find.text('Aceptando...'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('accept-offer-offer-a')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('accept-offer-offer-b')),
          )
          .onPressed,
      isNull,
    );
    expect(repository.cancelRequests, 0);

    pendingSelection.complete(
      _ride(status: 'DRIVER_ASSIGNED', agreedFare: '7.00'),
    );
    await _flushAsync(tester);
  });

  testWidgets('mientras cancela no permite aceptar propuesta', (tester) async {
    final pendingCancellation = Completer<PassengerRide>();
    final repository = _FakeRideRepository(
      onGetActiveRide: () async => _ride(),
      onGetRideOffers: (_) async => [
        _offer(
          offerId: 'offer-a',
          driverName: 'Carlos',
          proposedFare: '7.00',
          isCounterOffer: false,
        ),
      ],
      onCancelRide: (_) => pendingCancellation.future,
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await _openCancelDialog(tester);
    await tester.tap(find.text('Cancelar viaje'));
    await _flushAsync(tester);

    final selectButton = find.widgetWithText(FilledButton, 'Aceptar');
    expect(tester.widget<FilledButton>(selectButton).onPressed, isNull);
    expect(repository.selectRequests, 0);

    pendingCancellation.complete(_ride(status: 'CANCELLED'));
    await tester.pumpAndSettle();
  });

  testWidgets('polling viejo no revierte cancelación exitosa', (tester) async {
    final staleRideResponse = Completer<PassengerRide?>();
    var activeRequest = 0;
    final repository = _FakeRideRepository(
      onGetActiveRide: () {
        activeRequest++;

        if (activeRequest == 1) {
          return Future.value(_ride());
        }

        return staleRideResponse.future;
      },
      onGetRideOffers: (_) async => const [],
      onCancelRide: (_) async => _ride(status: 'CANCELLED'),
    );
    final router = await _pumpRoutedScreen(tester, repository);
    addTearDown(router.dispose);
    addTearDown(() => _disposeScreen(tester));

    await tester.pump(const Duration(seconds: 3));
    expect(repository.activeRideRequests, 2);

    await _openCancelDialog(tester);
    await tester.tap(find.text('Cancelar viaje'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/home');

    staleRideResponse.complete(_ride());
    await _flushAsync(tester);

    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.text('Buscando un conductor...'), findsNothing);
  });

  group('DRIVER_ASSIGNED', () {
    testWidgets('muestra conductor encontrado, driver real y agreedFare', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ASSIGNED',
          agreedFare: '6.50',
          driver: _assignedDriver(firstName: 'Julio'),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('¡Conductor encontrado!'), findsOneWidget);
      expect(find.text('Tu mototaxi está en camino'), findsOneWidget);
      expect(find.text('Julio M.'), findsOneWidget);
      expect(find.text('S/ 6.50'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assigned-driver-plate')),
        findsOneWidget,
      );
      expect(find.text('1234-AB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin driver ni driverLocation no crashea y omite la ficha', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async =>
            _ride(status: 'DRIVER_ASSIGNED', agreedFare: '7.00'),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('¡Conductor encontrado!'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assigned-driver-card')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('foto ausente muestra inicial sin romper el layout', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ASSIGNED',
          agreedFare: '7.00',
          driver: _assignedDriver(firstName: 'Julio', photoUrl: null),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('J'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Seguir mi viaje solo oculta el CTA, no cambia ride.status',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'DRIVER_ASSIGNED',
            agreedFare: '7.00',
            driver: _assignedDriver(),
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        final followButton = find.byKey(const ValueKey('follow-ride-button'));
        expect(followButton, findsOneWidget);

        await tester.tap(followButton);
        await tester.pump();

        expect(followButton, findsNothing);
        expect(find.text('¡Conductor encontrado!'), findsOneWidget);
        expect(repository.selectRequests, 0);
        expect(repository.cancelRequests, 0);
      },
    );
  });

  group('DRIVER_ARRIVING', () {
    testWidgets('muestra seguimiento real sin ETA ficticia', (tester) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVING',
          agreedFare: '7.00',
          driver: _assignedDriver(),
          driverLocation: _driverLocation(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Tu conductor está en camino'), findsOneWidget);
      expect(find.text('Carlos M.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(
                r'\bmin\b',
                caseSensitive: false,
              ).hasMatch(widget.data ?? ''),
        ),
        findsNothing,
      );
      expect(find.textContaining('ETA'), findsNothing);

      final map = tester.widget<GoogleMap>(
        find.byKey(const ValueKey('ride-search-google-map')),
      );
      expect(
        map.markers.any((marker) => marker.markerId == const MarkerId('ride-driver')),
        isTrue,
      );
    });

    testWidgets(
      'R4.3C: aunque haya foto real, la tarjeta NO es tappable en DRIVER_ARRIVING (solo DRIVER_ARRIVED)',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'DRIVER_ARRIVING',
            agreedFare: '7.00',
            driver: _assignedDriver(
              photoUrl: 'https://cdn.tukituki.pe/carlos.jpg',
            ),
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(find.text('Tu conductor está en camino'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsNothing,
        );
      },
    );

    testWidgets('driverLocation null no agrega marker ni crashea', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVING',
          agreedFare: '7.00',
          driver: _assignedDriver(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      final map = tester.widget<GoogleMap>(
        find.byKey(const ValueKey('ride-search-google-map')),
      );
      expect(
        map.markers.any((marker) => marker.markerId == const MarkerId('ride-driver')),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('DRIVER_ARRIVED', () {
    testWidgets('obtiene y muestra el PIN real con intentos reales', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVED',
          agreedFare: '7.00',
          driver: _assignedDriver(),
        ),
        onGetRideOffers: (_) async => const [],
        onGetStartCode: (_) async => _startCode(
          code: '4821',
          remainingAttempts: 4,
        ),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));
      await _flushAsync(tester);

      expect(find.text('Tu conductor ya llegó'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('4 intentos disponibles'), findsOneWidget);
      expect(repository.startCodeRequests, 1);
    });

    testWidgets(
      'identificación completa: nombre real, foto/placeholder y vehículo visibles, nunca "Por llegar"',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'DRIVER_ARRIVED',
            agreedFare: '7.00',
            driver: _assignedDriver(firstName: 'Juan', photoUrl: null),
          ),
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async => _startCode(
            code: '4821',
            remainingAttempts: 4,
          ),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(find.text('Tu conductor ya llegó'), findsOneWidget);
        expect(
          find.text('Identifica a tu conductor antes de subir.'),
          findsOneWidget,
        );
        expect(find.text('Juan M.'), findsOneWidget);
        expect(find.text('J'), findsOneWidget);
        expect(find.text('Bajaj · RE 4S · Rojo'), findsOneWidget);
        expect(find.text('1234-AB'), findsOneWidget);

        expect(find.textContaining('Por llegar'), findsNothing);
        expect(find.textContaining('DNI'), findsNothing);
        expect(find.textContaining('@'), findsNothing);

        // R4.3C: sin foto real, el avatar/placeholder NUNCA es tappable
        // — nunca se abre un viewer vacío.
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'R4.3C: con foto real, el avatar es tappable (sin agrandar toda la tarjeta)',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'DRIVER_ARRIVED',
            agreedFare: '7.00',
            driver: _assignedDriver(
              firstName: 'Juan',
              photoUrl: 'https://cdn.tukituki.pe/juan.jpg',
            ),
          ),
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async => _startCode(
            code: '4821',
            remainingAttempts: 4,
          ),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        // La tarjeta sigue siendo la misma compacta — sin variante
        // "prominent": mismo tamaño de fuente que DRIVER_ASSIGNED/ARRIVING.
        final nameText = tester.widget<Text>(
          find.byKey(const ValueKey('assigned-driver-name')),
        );
        expect(nameText.style?.fontSize, 18);

        // Tap abre el viewer ampliado. Se evita pumpAndSettle() a
        // propósito: el polling activo del ride (Timer.periodic) nunca
        // deja que la pantalla llegue a quiescencia; se pumpea el
        // tiempo suficiente para cubrir la transición del diálogo.
        await tester.tap(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('driver-photo-viewer')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver-photo-viewer-close')),
          findsOneWidget,
        );

        // Cerrar con X regresa exactamente al mismo ride en DRIVER_ARRIVED,
        // sin refresh/routing/request nueva.
        await tester.tap(
          find.byKey(const ValueKey('driver-photo-viewer-close')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('driver-photo-viewer')),
          findsNothing,
        );
        expect(find.text('Tu conductor ya llegó'), findsOneWidget);
        expect(repository.activeRideRequests, 1);
      },
    );

    testWidgets('error al obtener el PIN muestra estado seguro sin PIN falso', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async =>
            _ride(status: 'DRIVER_ARRIVED', agreedFare: '7.00'),
        onGetRideOffers: (_) async => const [],
        onGetStartCode: (_) async => throw _dioStartCodeError(),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));
      await _flushAsync(tester);

      expect(
        find.byKey(const ValueKey('start-code-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('start-code-retry')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('start-code-value')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('R4.3E: DRIVER PHOTO STABILITY (polling)', () {
    testWidgets(
      'poll transitorio con photoUrl null conserva la última foto válida del mismo Driver',
      (tester) async {
        var callCount = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            callCount++;

            return _ride(
              status: 'DRIVER_ARRIVED',
              agreedFare: '7.00',
              driver: _assignedDriver(
                photoUrl: callCount == 1
                    ? 'https://cdn.tukituki.pe/carlos-a.jpg'
                    : null,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async =>
              _startCode(code: '4821', remainingAttempts: 4),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        // El poll #2 llegó con photoUrl null (transitorio, mismo
        // Driver/ride) — la foto A sigue visible y tappable, no cae a
        // placeholder.
        expect(callCount, greaterThanOrEqualTo(2));
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'rotación de capability URL (misma foto, distinto token) no tumba el avatar y el viewer usa la más reciente',
      (tester) async {
        var callCount = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            callCount++;

            return _ride(
              status: 'DRIVER_ARRIVED',
              agreedFare: '7.00',
              driver: _assignedDriver(
                photoUrl: callCount == 1
                    ? 'https://cdn.tukituki.pe/avatars/driver-1?token=aaa'
                    : 'https://cdn.tukituki.pe/avatars/driver-1?token=bbb',
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async =>
              _startCode(code: '4821', remainingAttempts: 4),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        expect(callCount, greaterThanOrEqualTo(2));
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const ValueKey('driver-photo-viewer')),
          findsOneWidget,
        );

        final viewerImage = tester.widget<Image>(
          find.descendant(
            of: find.byKey(const ValueKey('driver-photo-viewer')),
            matching: find.byType(Image),
          ),
        );
        final viewerProvider = viewerImage.image as NetworkImage;

        // El estado final usa la capability más reciente (token=bbb),
        // nunca la primera URL ya rotada.
        expect(viewerProvider.url, contains('token=bbb'));
      },
    );

    testWidgets(
      'cambio legítimo de Driver descarta la foto anterior y nunca la conserva para el nuevo Driver',
      (tester) async {
        var callCount = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            callCount++;

            if (callCount == 1) {
              return _ride(
                status: 'DRIVER_ARRIVED',
                agreedFare: '7.00',
                driver: _assignedDriver(
                  profileId: 'driver-a',
                  firstName: 'Carlos',
                  photoUrl: 'https://cdn.tukituki.pe/carlos.jpg',
                ),
              );
            }

            return _ride(
              status: 'DRIVER_ARRIVED',
              agreedFare: '7.00',
              driver: _assignedDriver(
                profileId: 'driver-b',
                firstName: 'Renzo',
                photoUrl: null,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async =>
              _startCode(code: '4821', remainingAttempts: 4),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        expect(callCount, greaterThanOrEqualTo(2));
        expect(find.text('Renzo M.'), findsOneWidget);
        // El nuevo Driver (driver-b) no tiene foto propia -> placeholder,
        // NUNCA tappable, y jamás hereda la foto de Carlos (driver-a).
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'un ride activo distinto entre polls no contamina la foto con la del ride anterior',
      (tester) async {
        var callCount = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            callCount++;

            if (callCount == 1) {
              return _ride(
                id: 'ride-one',
                status: 'DRIVER_ARRIVED',
                agreedFare: '7.00',
                driver: _assignedDriver(
                  profileId: 'driver-a',
                  photoUrl: 'https://cdn.tukituki.pe/carlos.jpg',
                ),
              );
            }

            return _ride(
              id: 'ride-two',
              status: 'DRIVER_ARRIVED',
              agreedFare: '7.00',
              driver: _assignedDriver(profileId: 'driver-a', photoUrl: null),
            );
          },
          onGetRideOffers: (_) async => const [],
          onGetStartCode: (_) async =>
              _startCode(code: '4821', remainingAttempts: 4),
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));
        await _flushAsync(tester);

        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        expect(callCount, greaterThanOrEqualTo(2));
        // Mismo profileId ('driver-a') pero OTRO ride (ride-two): la
        // memoria en RAM está scoped por ride, así que NO hereda la
        // foto de ride-one aunque el profileId coincida.
        expect(
          find.byKey(const ValueKey('assigned-driver-avatar-tap')),
          findsNothing,
        );
      },
    );
  });

  group('IN_PROGRESS', () {
    testWidgets(
      'muestra viaje en curso con agreedFare, destino y driver reales',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'IN_PROGRESS',
            agreedFare: '7.50',
            destinationAddress: 'Jr. Amazonas 450',
            driver: _assignedDriver(firstName: 'Julio'),
            driverLocation: _driverLocation(),
            originLatitude: -6.4877,
            originLongitude: -76.3599,
            destinationLatitude: -6.4812,
            destinationLongitude: -76.3651,
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.text('Viaje en curso'), findsOneWidget);
        expect(
          find.text('TukiTuki está en camino a tu destino.'),
          findsOneWidget,
        );
        expect(find.text('S/ 7.50'), findsOneWidget);
        expect(find.text('Jr. Amazonas 450'), findsOneWidget);
        expect(find.text('Julio M.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('assigned-driver-plate')),
          findsOneWidget,
        );
        expect(find.text('1234-AB'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final map = tester.widget<GoogleMap>(
          find.byKey(const ValueKey('ride-search-google-map')),
        );
        expect(
          map.markers.any(
            (marker) => marker.markerId == const MarkerId('ride-driver'),
          ),
          isTrue,
        );
      },
    );

    testWidgets('driverLocation null no agrega marker ni crashea', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          driver: _assignedDriver(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      final map = tester.widget<GoogleMap>(
        find.byKey(const ValueKey('ride-search-google-map')),
      );
      expect(
        map.markers.any(
          (marker) => marker.markerId == const MarkerId('ride-driver'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin driver no crashea y omite la ficha', (tester) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async =>
            _ride(status: 'IN_PROGRESS', agreedFare: '7.50'),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Viaje en curso'), findsOneWidget);
      expect(find.byKey(const ValueKey('assigned-driver-card')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no muestra métricas ficticias ni acciones fuera de alcance', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          driver: _assignedDriver(),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('0.0 km'), findsNothing);
      expect(find.text('0 min'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(
                r'\bmin\b',
                caseSensitive: false,
              ).hasMatch(widget.data ?? ''),
        ),
        findsNothing,
      );
      expect(find.textContaining('ETA'), findsNothing);
      expect(find.text('Cancelar viaje'), findsNothing);
      expect(find.byKey(const ValueKey('cancel-search-button')), findsNothing);
      expect(find.byIcon(Icons.phone), findsNothing);
      expect(find.byIcon(Icons.chat), findsNothing);
      expect(find.textContaining('SOS'), findsNothing);
    });

    testWidgets('estado de progreso es representacional, no numérico', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          driver: _assignedDriver(),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(
        find.byKey(const ValueKey('trip-progress-indicator')),
        findsOneWidget,
      );
      expect(find.text('RECOJO'), findsOneWidget);
      expect(find.text('DESTINO'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('restore directo a IN_PROGRESS renderiza sin pasar por PIN', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          driver: _assignedDriver(firstName: 'Julio'),
          driverLocation: _driverLocation(),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Viaje en curso'), findsOneWidget);
      expect(find.text('Julio M.'), findsOneWidget);
      expect(repository.startCodeRequests, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('COMPLETED sigue navegando al receipt desde IN_PROGRESS', (
      tester,
    ) async {
      var callCount = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async {
          callCount++;

          if (callCount == 1) {
            return _ride(status: 'IN_PROGRESS', agreedFare: '7.50');
          }

          return _ride(status: 'COMPLETED', agreedFare: '7.50');
        },
        onGetRideOffers: (_) async => const [],
      );
      final router = await _pumpRoutedScreen(tester, repository);
      addTearDown(router.dispose);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Viaje en curso'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      expect(
        router.routeInformationProvider.value.uri.path,
        '/ride/ride-real/receipt',
      );
      expect(find.text('RECEIPT_DESTINATION'), findsOneWidget);
    });
  });

  group('CANCELLED externo (Checkpoint G1P)', () {
    testWidgets(
      'cancelledBy == DRIVER muestra la experiencia dedicada completa',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'CANCELLED',
            agreedFare: '12.50',
            originAddress: 'Jr. Lima 250, Tarapoto',
            destinationAddress: 'Plaza de Armas de Morales',
            cancelledBy: 'DRIVER',
            cancellationReason: 'VEHICLE_PROBLEM',
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(find.text('Viaje cancelado'), findsOneWidget);
        expect(find.text('Este viaje no llegó a completarse'), findsOneWidget);
        expect(find.text('Cancelado por el conductor'), findsOneWidget);
        expect(
          find.text(
            'El conductor canceló el viaje.\n'
            'Puedes solicitar uno nuevo cuando quieras.',
          ),
          findsOneWidget,
        );
        expect(find.text('Solicitar otro viaje'), findsOneWidget);
        expect(find.text('Volver al inicio'), findsOneWidget);
        expect(find.text('Jr. Lima 250, Tarapoto'), findsOneWidget);
        expect(find.text('Plaza de Armas de Morales'), findsOneWidget);
        expect(find.text('S/ 12.50'), findsOneWidget);
      },
    );

    testWidgets('cancelledBy null usa copy neutral, nunca atribuye al conductor', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async =>
            _ride(status: 'CANCELLED', agreedFare: '7.00'),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Viaje cancelado'), findsOneWidget);
      expect(find.text('Este viaje no llegó a completarse'), findsOneWidget);
      expect(find.text('El viaje fue cancelado.'), findsOneWidget);
      expect(find.text('Cancelado por el conductor'), findsNothing);
    });

    testWidgets('usa datos reales del ride, no textos del mockup', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '38.90',
          originAddress: 'Av. Circunvalación 900',
          destinationAddress: 'Terminal Terrestre Tarapoto',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Av. Circunvalación 900'), findsOneWidget);
      expect(find.text('Terminal Terrestre Tarapoto'), findsOneWidget);
      expect(find.text('S/ 38.90'), findsOneWidget);
      expect(find.text('S/ 5.00'), findsNothing);
    });

    testWidgets('sin tarifa real disponible, omite la fila en vez de S/ 0.00', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: null,
          passengerOfferFare: '0.00',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Tarifa que aplicaba'), findsNothing);
      expect(
        find.byKey(const ValueKey('cancelled-trip-fare-value')),
        findsNothing,
      );
      expect(find.text('S/ 0.00'), findsNothing);
    });

    testWidgets('NUNCA muestra copy de cobro/no-cobro', (tester) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.textContaining('cobro'), findsNothing);
      expect(find.textContaining('cargo'), findsNothing);
      expect(find.textContaining('cobrar'), findsNothing);
    });

    testWidgets('NUNCA muestra el motivo técnico crudo de Backend', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
          cancellationReason: 'VEHICLE_PROBLEM',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.textContaining('VEHICLE_PROBLEM'), findsNothing);
    });

    testWidgets('NUNCA muestra el reasonDetail escrito por el Driver', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
          cancellationReason: 'Se pinchó una llanta',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.textContaining('Se pinchó una llanta'), findsNothing);
    });

    testWidgets('CTA primario "Solicitar otro viaje" navega a Home', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );
      final router = await _pumpRoutedScreen(tester, repository);
      addTearDown(router.dispose);
      addTearDown(() => _disposeScreen(tester));

      final button = find.byKey(
        const ValueKey('cancelled-request-again-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _flushAsync(tester);

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('HOME_DESTINATION'), findsOneWidget);
      expect(repository.cancelRequests, 0);
      expect(repository.selectRequests, 0);
    });

    testWidgets('CTA secundario "Volver al inicio" navega a Home', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );
      final router = await _pumpRoutedScreen(tester, repository);
      addTearDown(router.dispose);
      addTearDown(() => _disposeScreen(tester));

      final goHomeButton = find.byKey(
        const ValueKey('cancelled-go-home-button'),
      );
      await tester.ensureVisible(goHomeButton);
      await tester.tap(goHomeButton);
      await _flushAsync(tester);

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('HOME_DESTINATION'), findsOneWidget);
    });

    testWidgets('después de cualquier CTA, back no reabre el Ride cancelado', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '7.00',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );
      final router = await _pumpRoutedScreen(tester, repository);
      addTearDown(router.dispose);
      addTearDown(() => _disposeScreen(tester));

      final goHomeButton = find.byKey(
        const ValueKey('cancelled-go-home-button'),
      );
      await tester.ensureVisible(goHomeButton);
      await tester.tap(goHomeButton);
      await _flushAsync(tester);

      expect(find.text('HOME_DESTINATION'), findsOneWidget);

      final canPop =
          router.routerDelegate.navigatorKey.currentState?.canPop() ?? false;

      expect(canPop, isFalse);
    });

    testWidgets('cancelación externa detectada por polling detiene el polling', (
      tester,
    ) async {
      var callCount = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async {
          callCount++;

          if (callCount == 1) {
            return _ride(
              status: 'DRIVER_ASSIGNED',
              agreedFare: '7.00',
              driver: _assignedDriver(),
            );
          }

          return _ride(
            status: 'CANCELLED',
            agreedFare: '7.00',
            cancelledBy: 'DRIVER',
          );
        },
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(find.text('Viaje cancelado'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      expect(find.text('Viaje cancelado'), findsOneWidget);

      final callsAfterCancel = repository.activeRideRequests;

      await tester.pump(const Duration(seconds: 6));
      await _flushAsync(tester);

      expect(repository.activeRideRequests, callsAfterCancel);
    });

    testWidgets(
      'GET active null (404) + GET by id CANCELLED renderiza la nueva UI',
      (tester) async {
        final repository = _FakeRideRepository(
          onGetActiveRide: () async => null,
          onGetRide: (rideId) async => _ride(
            status: 'CANCELLED',
            agreedFare: '7.00',
            cancelledBy: 'DRIVER',
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(repository.getRideRequests, 1);
        expect(find.text('Viaje cancelado'), findsOneWidget);
        expect(find.text('Cancelado por el conductor'), findsOneWidget);
      },
    );
  });

  group('responsive', () {
    testWidgets('DRIVER_ARRIVED en 360x640 no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVED',
          agreedFare: '7.00',
          driver: _assignedDriver(
            vehicle: const AssignedDriverVehicle(
              plate: '1234-AB',
              brand: 'Bajaj Boxer muy largo',
              model: 'RE 4S Edición especial',
              color: 'Verde metálico',
              vehicleType: 'MOTOTAXI',
            ),
          ),
        ),
        onGetRideOffers: (_) async => const [],
        onGetStartCode: (_) async => _startCode(),
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));
      await _flushAsync(tester);

      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('driver-tracking-scroll')),
        const Offset(0, -600),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('DRIVER_ASSIGNED en 390x844 no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ASSIGNED',
          agreedFare: '7.00',
          driver: _assignedDriver(),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
    });

    testWidgets('DRIVER_ARRIVING en 412x915 no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVING',
          agreedFare: '7.00',
          driver: _assignedDriver(),
          driverLocation: _driverLocation(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
    });

    testWidgets('IN_PROGRESS en 360x640 con dirección larga no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          destinationAddress:
              'Jr. Los Alisos Manzana G Lote 15, Urbanización '
              'San Antonio de Padua, Tarapoto, San Martín',
          driver: _assignedDriver(
            firstName: 'Alexander',
            vehicle: const AssignedDriverVehicle(
              plate: '1234-AB',
              brand: 'Bajaj Boxer edición especial',
              model: 'RE 4S Compact',
              color: 'Verde metálico',
              vehicleType: 'MOTOTAXI',
            ),
          ),
          driverLocation: _driverLocation(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('in-progress-scroll')),
        const Offset(0, -400),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('IN_PROGRESS en 390x844 no produce overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'IN_PROGRESS',
          agreedFare: '7.50',
          driver: _assignedDriver(),
          driverLocation: _driverLocation(),
          originLatitude: -6.4877,
          originLongitude: -76.3599,
          destinationLatitude: -6.4812,
          destinationLongitude: -76.3651,
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'CANCELLED + DRIVER en 360x640 con direcciones y monto largos '
      'no produce overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = _FakeRideRepository(
          onGetActiveRide: () async => _ride(
            status: 'CANCELLED',
            agreedFare: '125.50',
            originAddress:
                'Jr. Los Álamos Sur 1234, Urbanización Las Palmeras '
                'del Este, Tarapoto',
            destinationAddress:
                'Avenida Circunvalación Norte 5678, Sector Industrial '
                'La Molina, Morales',
            cancelledBy: 'DRIVER',
          ),
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(tester.takeException(), isNull);

        await tester.drag(
          find.byKey(const ValueKey('cancelled-scroll')),
          const Offset(0, -400),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('CANCELLED + DRIVER en 390x844 no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'CANCELLED',
          agreedFare: '38.90',
          cancelledBy: 'DRIVER',
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
    });

    testWidgets('CANCELLED sin cancelledBy en 412x915 no produce overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeRideRepository(
        onGetActiveRide: () async =>
            _ride(status: 'CANCELLED', agreedFare: '7.00'),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(tester.takeException(), isNull);
    });
  });

  group('R4.4B: interpolación visual del marker del Driver', () {
    const pointA = LatLng(-6.4879, -76.3601);
    const pointB = LatLng(-6.4869, -76.3596); // ~124m de A, bajo el umbral de 300m
    const pointFar = LatLng(-6.4700, -76.3400); // muy por encima de 300m de A

    testWidgets('primera posición válida se muestra directa, sin animar', (
      tester,
    ) async {
      final repository = _FakeRideRepository(
        onGetActiveRide: () async => _ride(
          status: 'DRIVER_ARRIVING',
          driver: _assignedDriver(),
          driverLocation: DriverLocation(
            latitude: pointA.latitude,
            longitude: pointA.longitude,
          ),
        ),
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(_driverMarkerPosition(tester), pointA);
    });

    testWidgets('A→B anima suavemente: sigue en A justo tras el update, '
        'pasa por un punto intermedio y llega exactamente a B', (
      tester,
    ) async {
      var call = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async {
          call++;
          final point = call == 1 ? pointA : pointB;
          return _ride(
            status: 'DRIVER_ARRIVING',
            driver: _assignedDriver(),
            driverLocation: DriverLocation(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
          );
        },
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(_driverMarkerPosition(tester), pointA);

      // Dispara el poll #2 (Timer.periodic de 3s) -> nueva posición B.
      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      // Justo tras recibir B, la animación recién empieza: el marker
      // sigue prácticamente en A, no salta directo a B.
      final justAfterUpdate = _driverMarkerPosition(tester)!;
      expect(justAfterUpdate.latitude, closeTo(pointA.latitude, 0.0003));
      expect(justAfterUpdate.longitude, closeTo(pointA.longitude, 0.0003));

      // Punto intermedio: ni A ni B.
      await _pumpInSteps(tester, const Duration(milliseconds: 1400));
      final midpoint = _driverMarkerPosition(tester)!;
      expect(midpoint.latitude, greaterThan(pointA.latitude));
      expect(midpoint.latitude, lessThan(pointB.latitude));
      expect(midpoint.longitude, greaterThan(pointA.longitude));
      expect(midpoint.longitude, lessThan(pointB.longitude));

      // La animación llega exactamente a B.
      await _pumpInSteps(tester, const Duration(milliseconds: 1600));
      final finalPosition = _driverMarkerPosition(tester)!;
      expect(finalPosition.latitude, closeTo(pointB.latitude, 0.00001));
      expect(finalPosition.longitude, closeTo(pointB.longitude, 0.00001));
    });

    testWidgets(
      'nueva posición C mientras A→B sigue animando: no salta hacia atrás a '
      'B, continúa desde la posición visual actual y termina en C',
      (tester) async {
        const pointC = LatLng(-6.4859, -76.3591);

        var call = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            call++;

            if (call == 1) {
              return _ride(
                status: 'DRIVER_ARRIVING',
                driver: _assignedDriver(),
                driverLocation: DriverLocation(
                  latitude: pointA.latitude,
                  longitude: pointA.longitude,
                ),
              );
            }

            if (call == 2) {
              // Retraso de red deliberado: hace que la animación A→B
              // arranque tarde y siga activa cuando llegue el poll #3.
              await Future<void>.delayed(const Duration(milliseconds: 500));

              return _ride(
                status: 'DRIVER_ARRIVING',
                driver: _assignedDriver(),
                driverLocation: DriverLocation(
                  latitude: pointB.latitude,
                  longitude: pointB.longitude,
                ),
              );
            }

            return _ride(
              status: 'DRIVER_ARRIVING',
              driver: _assignedDriver(),
              driverLocation: DriverLocation(
                latitude: pointC.latitude,
                longitude: pointC.longitude,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(_driverMarkerPosition(tester), pointA);

        // Poll #2 (t=3000ms): arranca con retraso de red de 500ms.
        await tester.pump(const Duration(seconds: 3));
        await _pumpInSteps(tester, const Duration(milliseconds: 500));
        await _flushAsync(tester);

        // La animación A→B ya debería haber arrancado.
        await _pumpInSteps(tester, const Duration(milliseconds: 1500));
        final beforeInterruption = _driverMarkerPosition(tester)!;
        expect(beforeInterruption, isNot(pointA));
        expect(beforeInterruption, isNot(pointB));

        // Poll #3 (siguiente tick natural del Timer, t=6000ms): llega C
        // mientras la animación A→B sigue en curso (arrancó en t=3500,
        // dura 2800ms -> termina en t=6300).
        await _pumpInSteps(tester, const Duration(milliseconds: 1000));
        await _flushAsync(tester);

        // No debe haber saltado hacia atrás a B.
        final justAfterC = _driverMarkerPosition(tester)!;
        expect(justAfterC, isNot(pointB));

        // Termina en C, no en B.
        await _pumpInSteps(tester, const Duration(milliseconds: 2900));
        final finalPosition = _driverMarkerPosition(tester)!;
        expect(finalPosition.latitude, closeTo(pointC.latitude, 0.00001));
        expect(finalPosition.longitude, closeTo(pointC.longitude, 0.00001));
      },
    );

    testWidgets(
      'la misma coordenada en reposo no reinicia animación ni produce '
      'flicker',
      (tester) async {
        var call = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            call++;
            final point = call == 1 ? pointA : pointB;
            return _ride(
              status: 'DRIVER_ARRIVING',
              driver: _assignedDriver(),
              driverLocation: DriverLocation(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        // Deja completar la animación A→B.
        await tester.pump(const Duration(seconds: 3));
        await _pumpInSteps(tester, const Duration(milliseconds: 3000));
        final settled = _driverMarkerPosition(tester)!;
        expect(settled.latitude, closeTo(pointB.latitude, 0.00001));

        // Poll #3 (mismo B): no debe mover el marker ni lanzar excepciones.
        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        final afterSameCoordinate = _driverMarkerPosition(tester)!;
        expect(afterSameCoordinate.latitude, closeTo(pointB.latitude, 0.00001));
        expect(
          afterSameCoordinate.longitude,
          closeTo(pointB.longitude, 0.00001),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'driverLocation null transitorio conserva el último marker válido',
      (tester) async {
        var call = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            call++;

            return _ride(
              status: 'DRIVER_ARRIVING',
              driver: _assignedDriver(),
              originLatitude: -6.4877,
              originLongitude: -76.3599,
              destinationLatitude: -6.4812,
              destinationLongitude: -76.3651,
              driverLocation: call == 1
                  ? DriverLocation(
                      latitude: pointA.latitude,
                      longitude: pointA.longitude,
                    )
                  : null,
            );
          },
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(_driverMarkerPosition(tester), pointA);

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        expect(_driverMarkerPosition(tester), pointA);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('cambio de Driver resetea la animación: nueva posición directa', (
      tester,
    ) async {
      const otherDriverPoint = LatLng(-6.5000, -76.3700);

      var call = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async {
          call++;

          return _ride(
            status: 'DRIVER_ARRIVING',
            driver: _assignedDriver(
              profileId: call == 1 ? 'driver-1' : 'driver-2',
            ),
            driverLocation: DriverLocation(
              latitude: call == 1 ? pointA.latitude : otherDriverPoint.latitude,
              longitude: call == 1
                  ? pointA.longitude
                  : otherDriverPoint.longitude,
            ),
          );
        },
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(_driverMarkerPosition(tester), pointA);

      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      // Directo al nuevo Driver, sin interpolar desde el anterior.
      expect(_driverMarkerPosition(tester), otherDriverPoint);
    });

    testWidgets('cambio de ride resetea la animación: nueva posición directa', (
      tester,
    ) async {
      const otherRidePoint = LatLng(-6.4600, -76.3300);

      var call = 0;
      final repository = _FakeRideRepository(
        onGetActiveRide: () async {
          call++;

          return _ride(
            id: call == 1 ? 'ride-real' : 'ride-other',
            status: 'DRIVER_ARRIVING',
            driver: _assignedDriver(),
            driverLocation: DriverLocation(
              latitude: call == 1 ? pointA.latitude : otherRidePoint.latitude,
              longitude: call == 1
                  ? pointA.longitude
                  : otherRidePoint.longitude,
            ),
          );
        },
        onGetRideOffers: (_) async => const [],
      );

      await _pumpScreen(tester, repository);
      addTearDown(() => _disposeScreen(tester));

      expect(_driverMarkerPosition(tester), pointA);

      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      // Directo al nuevo ride, no conserva marker del ride anterior.
      expect(_driverMarkerPosition(tester), otherRidePoint);
    });

    testWidgets(
      'salto mayor a 300m hace snap directo en vez de animar lentamente',
      (tester) async {
        var call = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            call++;
            final point = call == 1 ? pointA : pointFar;
            return _ride(
              status: 'DRIVER_ARRIVING',
              driver: _assignedDriver(),
              driverLocation: DriverLocation(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);
        addTearDown(() => _disposeScreen(tester));

        expect(_driverMarkerPosition(tester), pointA);

        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);

        // Snap inmediato: no hace falta esperar la duración de la
        // animación para llegar al punto lejano.
        expect(_driverMarkerPosition(tester), pointFar);
      },
    );

    testWidgets(
      'dispose durante una animación en curso no deja Timer/Ticker pendiente',
      (tester) async {
        var call = 0;
        final repository = _FakeRideRepository(
          onGetActiveRide: () async {
            call++;
            final point = call == 1 ? pointA : pointB;
            return _ride(
              status: 'DRIVER_ARRIVING',
              driver: _assignedDriver(),
              driverLocation: DriverLocation(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            );
          },
          onGetRideOffers: (_) async => const [],
        );

        await _pumpScreen(tester, repository);

        await tester.pump(const Duration(seconds: 3));
        await _pumpInSteps(tester, const Duration(milliseconds: 800));

        // Dispose a mitad de la animación A→B: si el AnimationController
        // o el Timer de polling no se cancelan correctamente, el binding
        // de test detecta timers/tickers colgados al terminar el test.
        await _disposeScreen(tester);

        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({
    required this.onGetActiveRide,
    required this.onGetRideOffers,
    this.onSelectRideOffer,
    this.onCancelRide,
    this.onGetStartCode,
    this.onGetRide,
  }) : super(Dio());

  final Future<PassengerRide?> Function() onGetActiveRide;
  final Future<List<PassengerRideOffer>> Function(String rideId)
  onGetRideOffers;
  final Future<PassengerRide> Function({
    required String rideId,
    required String offerId,
  })?
  onSelectRideOffer;
  final Future<PassengerRide> Function(String rideId)? onCancelRide;
  final Future<PassengerRideStartCode> Function(String rideId)?
  onGetStartCode;

  /// Solo se invoca cuando `getActiveRide()` devuelve `null` (p.ej.
  /// 404 tras un estado terminal) — mismo fallback real que usa
  /// `_loadRide()`. Los tests que nunca necesitan este camino
  /// (la mayoría) no lo configuran.
  final Future<PassengerRide> Function(String rideId)? onGetRide;

  int activeRideRequests = 0;
  int getRideRequests = 0;
  int selectRequests = 0;
  int cancelRequests = 0;
  int startCodeRequests = 0;
  String? selectedRideId;
  String? selectedOfferId;
  String? cancelledRideId;

  @override
  Future<PassengerRide?> getActiveRide() {
    activeRideRequests++;
    return onGetActiveRide();
  }

  @override
  Future<PassengerRide> getRide(String rideId) {
    getRideRequests++;

    final handler = onGetRide;

    if (handler == null) {
      throw StateError('GetRide no configurado');
    }

    return handler(rideId);
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

  @override
  Future<PassengerRide> cancelRide({required String rideId}) {
    cancelRequests++;
    cancelledRideId = rideId;

    final handler = onCancelRide;

    if (handler == null) {
      throw StateError('Cancel no configurado');
    }

    return handler(rideId);
  }

  @override
  Future<PassengerRideStartCode> getStartCode(String rideId) {
    startCodeRequests++;

    final handler = onGetStartCode;

    if (handler == null) {
      throw StateError('GetStartCode no configurado');
    }

    return handler(rideId);
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

/// R4.4B: avanza el reloj virtual del test en pasos pequeños en vez de
/// un solo salto grande, para que el `AnimationController` del marker
/// del Driver progrese de forma realista (frame a frame) y para no
/// perder ticks del `Timer.periodic` de polling que caigan dentro del
/// rango.
Future<void> _pumpInSteps(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 50),
}) async {
  var remaining = total;

  while (remaining > Duration.zero) {
    final chunk = remaining > step ? step : remaining;
    await tester.pump(chunk);
    remaining -= chunk;
  }
}

/// R4.4B: posición actual del marker `ride-driver` en el
/// `GoogleMap` real del test, o `null` si no existe.
LatLng? _driverMarkerPosition(WidgetTester tester) {
  final map = tester.widget<GoogleMap>(
    find.byKey(const ValueKey('ride-search-google-map')),
  );

  for (final marker in map.markers) {
    if (marker.markerId == const MarkerId('ride-driver')) {
      return marker.position;
    }
  }

  return null;
}

Future<GoRouter> _pumpRoutedScreen(
  WidgetTester tester,
  RideRepository repository, {
  String routeRideId = 'ride-real',
}) async {
  final router = GoRouter(
    initialLocation: '/ride/$routeRideId',
    routes: [
      GoRoute(
        path: '/ride/:rideId',
        builder: (context, state) =>
            RideSearchingScreen(rideId: state.pathParameters['rideId']!),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Text('HOME_DESTINATION')),
      ),
      GoRoute(
        path: '/ride/:rideId/receipt',
        builder: (context, state) =>
            const Scaffold(body: Text('RECEIPT_DESTINATION')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [rideRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _flushAsync(tester);

  return router;
}

Future<void> _openCancelDialog(WidgetTester tester) async {
  final cancelButton = find.byKey(const ValueKey('cancel-search-button'));
  await tester.ensureVisible(cancelButton);
  await tester.tap(cancelButton);
  await tester.pump(const Duration(milliseconds: 250));
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

DioException _dioCancelError(int statusCode) {
  final requestOptions = RequestOptions(
    path: 'passenger/rides/ride-real/cancel',
  );

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(
      requestOptions: requestOptions,
      statusCode: statusCode,
    ),
  );
}

DioException _dioStartCodeError() {
  final requestOptions = RequestOptions(
    path: 'passenger/rides/ride-real/start-code',
  );

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(requestOptions: requestOptions, statusCode: 409),
  );
}

DioException _dioCancelNetworkError() {
  return DioException(
    requestOptions: RequestOptions(path: 'passenger/rides/ride-real/cancel'),
    type: DioExceptionType.connectionError,
    error: StateError('offline'),
  );
}

PassengerRide _ride({
  String id = 'ride-real',
  String status = 'SEARCHING_DRIVER',
  String? agreedFare,
  num distanceMeters = 1500,
  num estimatedDurationSeconds = 600,
  String passengerOfferFare = '7.00',
  String originAddress = 'Origen',
  String destinationAddress = 'Destino',
  double? originLatitude,
  double? originLongitude,
  double? destinationLatitude,
  double? destinationLongitude,
  AssignedDriver? driver,
  DriverLocation? driverLocation,
  DateTime? cancelledAt,
  String? cancelledBy,
  String? cancellationReason,
}) {
  return PassengerRide(
    id: id,
    fareQuoteId: 'quote-1',
    status: status,
    distanceMeters: distanceMeters,
    estimatedDurationSeconds: estimatedDurationSeconds,
    estimatedFare: '7.00',
    estimatedPassengerFare: '7.00',
    passengerOfferFare: passengerOfferFare,
    agreedFare: agreedFare,
    currency: 'PEN',
    paymentMethod: 'CASH',
    originLatitude: originLatitude,
    originLongitude: originLongitude,
    destinationLatitude: destinationLatitude,
    destinationLongitude: destinationLongitude,
    originAddress: originAddress,
    destinationAddress: destinationAddress,
    requestedAt: DateTime.utc(2026, 8, 9),
    searchExpiresAt: null,
    driver: driver,
    driverLocation: driverLocation,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancellationReason: cancellationReason,
  );
}

AssignedDriver _assignedDriver({
  String profileId = 'driver-1',
  String firstName = 'Carlos',
  String lastNameInitial = 'M.',
  String? photoUrl,
  String ratingAverage = '4.92',
  int ratingCount = 128,
  AssignedDriverVehicle? vehicle,
}) {
  return AssignedDriver(
    profileId: profileId,
    firstName: firstName,
    lastNameInitial: lastNameInitial,
    photoUrl: photoUrl,
    ratingAverage: ratingAverage,
    ratingCount: ratingCount,
    vehicle:
        vehicle ??
        const AssignedDriverVehicle(
          plate: '1234-AB',
          brand: 'Bajaj',
          model: 'RE 4S',
          color: 'Rojo',
          vehicleType: 'MOTOTAXI',
        ),
  );
}

DriverLocation _driverLocation({
  double latitude = -6.4879,
  double longitude = -76.3601,
}) {
  return DriverLocation(latitude: latitude, longitude: longitude);
}

PassengerRideStartCode _startCode({
  String code = '4821',
  num remainingAttempts = 5,
}) {
  return PassengerRideStartCode(
    rideId: 'ride-real',
    code: code,
    status: 'ACTIVE',
    expiresAt: DateTime.utc(2026, 8, 9, 12, 15),
    remainingSeconds: 900,
    remainingAttempts: remainingAttempts,
  );
}

PassengerRideOffer _offer({
  required String offerId,
  required String driverName,
  required String proposedFare,
  required bool isCounterOffer,
  String rideId = 'ride-real',
  DateTime? expiresAt,
  String driverLastNameInitial = '',
  double ratingAverage = 4.8,
  int ratingCount = 10,
  num distanceToOriginMeters = 300,
  String passengerOfferFare = '7.00',
}) {
  return PassengerRideOffer(
    offerId: offerId,
    rideId: rideId,
    driverProfileId: 'driver-$offerId',
    driverFirstName: driverName,
    driverLastNameInitial: driverLastNameInitial,
    photoUrl: null,
    ratingAverage: ratingAverage,
    ratingCount: ratingCount,
    distanceToOriginMeters: distanceToOriginMeters,
    passengerOfferFare: passengerOfferFare,
    proposedFare: proposedFare,
    isCounterOffer: isCounterOffer,
    currency: 'PEN',
    proposedAt: DateTime.utc(2026, 8, 9),
    expiresAt: expiresAt,
  );
}
