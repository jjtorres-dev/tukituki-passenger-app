import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger/core/theme/passenger_colors.dart';
import 'package:passenger/core/widgets/tuki_search_bar.dart';
import 'package:passenger/features/auth/data/auth_repository.dart';
import 'package:passenger/features/fare/data/fare_repository.dart';
import 'package:passenger/features/fare/domain/fare_estimate.dart';
import 'package:passenger/features/home/home_screen.dart';
import 'package:passenger/features/home/offer_fare_screen.dart';
import 'package:passenger/features/home/profile_menu_drawer.dart';
import 'package:passenger/features/notifications/data/device_id_store.dart';
import 'package:passenger/features/notifications/data/push_messaging_service.dart';
import 'package:passenger/features/notifications/data/push_registration_coordinator.dart';
import 'package:passenger/features/notifications/data/push_registration_repository.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';
import 'package:passenger/features/passenger/domain/passenger_profile.dart';
import 'package:passenger/features/passenger/presentation/edit_profile_screen.dart';
import 'package:passenger/features/places/data/places_repository.dart';
import 'package:passenger/features/places/domain/place_details.dart';
import 'package:passenger/features/places/domain/place_prediction.dart';
import 'package:passenger/features/ride/data/payment_preference_repository.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';
import 'package:passenger/features/ride/domain/payment_method.dart';
import 'package:passenger/features/ride/domain/ride_history_item.dart';

void main() {
  late GeolocatorPlatform originalGeolocatorPlatform;

  setUp(() {
    originalGeolocatorPlatform = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalGeolocatorPlatform;
  });

  testWidgets(
    'HOME-FLOW-R1: sin destino, hoja mínima sin CTA — "Selecciona un '
    'destino" ya no existe, el disparador de búsqueda lo reemplaza',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        mediaQueryData: const MediaQueryData(
          viewPadding: EdgeInsets.only(top: 24),
        ),
      );

      final statusBarBackground = tester.widget<SizedBox>(
        find.byKey(const ValueKey('home-status-bar-background')),
      );
      expect(statusBarBackground.height, 24);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('home-status-bar-background')))
            .width,
        tester.getSize(find.byType(Scaffold)).width,
      );
      expect(
        (statusBarBackground.child! as ColoredBox).color,
        PassengerColors.verdeMarca,
      );
      expect(tester.getTopLeft(find.byType(GoogleMap)).dy, 24);
      expect(tester.getTopLeft(find.byTooltip('Abrir menú')).dy, 38);

      final systemUiRegion = tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          );
      expect(systemUiRegion.value.statusBarIconBrightness, Brightness.light);

      // HOME-FLOW-R1: ni la tarjeta origen/destino ni el CTA existen
      // en Home vacío -- el texto "Selecciona un destino" no aparece
      // en ningún lado.
      expect(find.text('Selecciona un destino'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      expect(find.text('¿A dónde vamos?'), findsOneWidget);

      // El disparador de búsqueda está presente y habilitado (ya hay
      // GPS en este fake).
      final trigger = tester.widget<TukiSearchBar>(
        find.byKey(const ValueKey('home-search-trigger')),
      );
      expect(trigger.enabled, isTrue);

      // Sin destino, jamás se dispara una cotización.
      expect(fareRepository.callCount, 0);
    },
  );

  testWidgets(
    'G4B-R5-2: tras seleccionar destino, "Calcular tarifa" ya NO aparece',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      expect(find.text('Calcular tarifa'), findsNothing);
    },
  );

  testWidgets(
    'G4B-R5-3: seleccionar destino dispara el FareQuote automáticamente, '
    'sin duplicar la solicitud',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      expect(fareRepository.callCount, 0);

      await _selectDestinationOnMap(tester);

      expect(fareRepository.callCount, 1);
      expect(_offerAmountFinder, findsOneWidget);

      // Reconstrucciones posteriores (p.ej. al ajustar el stepper de
      // oferta) NUNCA disparan una segunda solicitud para la misma
      // selección.
      await _tapOfferIncrement(tester);
      await tester.pump();

      expect(fareRepository.callCount, 1);
    },
  );

  testWidgets(
    'G4B-R5-7/8: el CTA dice exactamente "Ofrecer y buscar conductor" '
    'y ya no lleva el icono de moto',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);
      await tester.pump();

      expect(find.text('Ofrecer y buscar conductor'), findsOneWidget);

      final ctaFinder = find.ancestor(
        of: find.text('Ofrecer y buscar conductor'),
        matching: find.byType(FilledButton),
      );

      expect(ctaFinder, findsOneWidget);
      expect(
        find.descendant(
          of: ctaFinder,
          matching: find.byIcon(Icons.two_wheeler),
        ),
        findsNothing,
      );
      // Ícono removido, no sustituido por otro.
      expect(
        find.descendant(of: ctaFinder, matching: find.byType(Icon)),
        findsNothing,
      );
    },
  );

  testWidgets('G4B-R5.1-8: si la cotización automática falla, el CTA dice '
      '"Reintentar" (nunca "Calcular tarifa"/"Calcular nueva tarifa") y '
      'el flujo continúa', (tester) async {
    final fareRepository = _FakeFareRepository(
      estimatedFare: '7.00',
      failFirstCall: true,
    );
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    // La solicitud automática falló: sin quote, pero con un CTA
    // accionable y neutral para reintentar.
    expect(fareRepository.callCount, 1);
    expect(_offerAmountFinder, findsNothing);
    expect(find.text('Calcular tarifa'), findsNothing);
    expect(find.text('Calcular nueva tarifa'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);

    final retryButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(retryButton.onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    await _flushAsync(tester);

    expect(fareRepository.callCount, 2);
    expect(_offerAmountFinder, findsOneWidget);
  });

  testWidgets('G4B-R3-1/2: "Precio recomendado TukiTuki" y el monto grande '
      'no aparecen tras cotizar', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    expect(find.text('Precio recomendado TukiTuki'), findsNothing);
    expect(find.textContaining('Recomendado'), findsNothing);
    expect(find.text('S/ 7.00'), findsNothing);
  });

  testWidgets(
    'FARE-PANEL-R1: el panel de oferta muestra stepper y línea de métricas, '
    'sin título ni texto de ayuda',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      expect(_offerAmountFinder, findsOneWidget);
      expect(find.text('2.5 km · 8 min'), findsOneWidget);
      expect(find.text('¿Cuánto quieres ofrecer?'), findsNothing);
      expect(
        find.text('Este es el monto que verán los conductores.'),
        findsNothing,
      );
    },
  );

  testWidgets('G4B-R3-4: tras cotizar, el stepper arranca en el mínimo '
      'S/ 3.00 — NO se precarga con estimatedFare', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    expect(_shownOfferAmount(tester), 'S/ 3.00');
    expect(find.text('7.00'), findsNothing);
  });

  testWidgets('G4B-R3-5 (FARE-PANEL-R1): tocar + sube el monto mostrado en '
      'pasos de S/ 0.50', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    expect(_shownOfferAmount(tester), 'S/ 3.00');

    await _tapOfferIncrement(tester);
    expect(_shownOfferAmount(tester), 'S/ 3.50');

    await _tapOfferIncrement(tester);
    expect(_shownOfferAmount(tester), 'S/ 4.00');
  });

  testWidgets(
    'G4B-R4-1: el botón "Recalcular tarifa" ya no aparece en la card de oferta',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      expect(find.text('Recalcular tarifa'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.textContaining('Cotización'), findsNothing);
    },
  );

  testWidgets(
    'G4B-R5.1-1: destino con cotización ya vencida al llegar: se renueva '
    'sola sin ningún botón manual',
    (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        firstQuoteAlreadyExpired: true,
      );
      final rideRepository = _FakeRideRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      // La primera cotización ya llega vencida (simula que el
      // Passenger dejó la pantalla abierta). Ya no hay ningún botón
      // "Calcular [nueva] tarifa" que tocar — se renueva sola.
      expect(fareRepository.callCount, 2);
      expect(find.text('Calcular tarifa'), findsNothing);
      expect(find.text('Calcular nueva tarifa'), findsNothing);
      expect(_offerAmountFinder, findsOneWidget);

      // Sin tocar el stepper: la oferta mínima (S/ 3.00) ya es válida.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRideCalls, hasLength(1));
      expect(rideRepository.createRideCalls.single, '3.00');
    },
  );

  testWidgets('G4B-R5.1-6/7: si la cotización vence mientras el Passenger ya '
      'escribió su oferta, se renueva sola y preserva ese monto', (
    tester,
  ) async {
    final fareRepository = _FakeFareRepository(
      estimatedFare: '7.00',
      firstQuoteTtl: const Duration(seconds: 2),
    );
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);
    expect(fareRepository.callCount, 1);

    // El Passenger ajusta la oferta con el stepper: 3.00 → 4.00.
    await _tapOfferIncrement(tester);
    await _tapOfferIncrement(tester);
    expect(_shownOfferAmount(tester), 'S/ 4.00');

    // Deja vencer la cotización: el Timer interno dispara la
    // renovación solo, sin ningún tap del Passenger.
    await tester.pump(const Duration(seconds: 3));
    await _flushAsync(tester);

    expect(fareRepository.callCount, 2);
    expect(find.text('Calcular tarifa'), findsNothing);
    expect(find.text('Calcular nueva tarifa'), findsNothing);
    expect(find.text('Reintentar'), findsNothing);
    // El monto ajustado sobrevive intacto a la renovación interna.
    expect(_shownOfferAmount(tester), 'S/ 4.00');
    expect(_offerAmountFinder, findsOneWidget);
  });

  testWidgets('G4B-R5.1-4/5: cambiar de destino con una request pendiente — la '
      'respuesta vieja NUNCA gana, solo el destino final queda como quote', (
    tester,
  ) async {
    final fareRepository = _FakeFareRepository(
      estimatedFare: '7.00',
      holdRequests: true,
    );
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    final dynamic state = tester.state(find.byType(HomeScreen));

    // Destino A: dispara estimate(A), queda pendiente (holdRequests).
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    map.onTap!(const LatLng(-6.4880, -76.3600));
    await tester.pump();

    expect(fareRepository.callCount, 1);
    expect(state.debugQuoteId, isNull);

    // Cambia a B ANTES de que A responda: debe disparar una NUEVA
    // solicitud de inmediato, no esperar a que A termine.
    map.onTap!(const LatLng(-6.5000, -76.4000));
    await tester.pump();

    expect(fareRepository.callCount, 2);

    // Responde A (la vieja) DESPUÉS de que B ya está en vuelo.
    fareRepository.resolveCall(0);
    await _flushAsync(tester);

    // La respuesta de A quedó descartada por completo: sigue sin
    // quote (B todavía no respondió) y sin oferta visible.
    expect(state.debugQuoteId, isNull);
    expect(_offerAmountFinder, findsNothing);

    // Responde B.
    fareRepository.resolveCall(1);
    await _flushAsync(tester);

    // Solo B quedó como quote vigente (segunda solicitud = quote-2).
    expect(state.debugQuoteId, 'quote-2');
    expect(_offerAmountFinder, findsOneWidget);
  });

  testWidgets(
    'G4B-R5.2-1: destino manual muestra la dirección real resuelta por '
    'Backend, ya no el placeholder local',
    (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        destinationAddressOverrides: const [
          'Calle Yurimaguas 302, Tarapoto 22202, Perú',
        ],
      );
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      // FARE-PANEL-R1 (Etapa 5): la tarjeta muestra el nombre corto
      // (`shortAddressLabel`), no la dirección completa que Backend
      // resolvió.
      expect(find.text('Calle Yurimaguas 302'), findsOneWidget);
      expect(
        find.text('Calle Yurimaguas 302, Tarapoto 22202, Perú'),
        findsNothing,
      );
      expect(find.text('Destino seleccionado en el mapa'), findsNothing);
      expect(find.text('Destino en el mapa'), findsNothing);
    },
  );

  testWidgets(
    'G4B-R5.2-2: actualizar la dirección visual NO dispara una segunda '
    'cotización',
    (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        destinationAddressOverrides: const [
          'Calle Yurimaguas 302, Tarapoto 22202, Perú',
        ],
      );
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      expect(fareRepository.callCount, 1);

      // Pumps extra: reconstruir el árbol tras el cambio de address
      // no puede disparar de más.
      await tester.pump();
      await tester.pump();

      expect(fareRepository.callCount, 1);
    },
  );

  testWidgets(
    'G4B-R5.2-3: destino por autocomplete conserva su dirección real y '
    'el flujo automático sigue funcionando',
    (tester) async {
      const prediction = PlacePrediction(
        placeId: 'place-1',
        primaryText: 'Municipalidad de Tarapoto',
        secondaryText: 'Jr. Jiménez Pimentel 210',
        fullText: 'Municipalidad de Tarapoto, Jr. Jiménez Pimentel 210',
        distanceMeters: 500,
      );
      const details = PlaceDetails(
        placeId: 'place-1',
        formattedAddress: 'Jr. Jiménez Pimentel 210, Tarapoto 22202, Perú',
        latitude: -6.4812,
        longitude: -76.3655,
      );

      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();
      final placesRepository = _FakePlacesRepository(
        predictions: const [prediction],
        details: details,
      );

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        placesRepository: placesRepository,
      );

      await _selectDestinationViaAutocomplete(
        tester,
        query: 'Municipalidad',
        prediction: prediction,
      );

      expect(fareRepository.callCount, 1);
      // Backend hace eco de la dirección real que ya mandó el cliente
      // (autocomplete nunca deja el placeholder puesto, así que nunca
      // se re-geocodifica). FARE-PANEL-R1 (Etapa 5): la tarjeta ya no
      // muestra esa dirección completa como subtítulo — el nombre
      // corto real de la búsqueda (`primaryText`) sigue intacto como
      // único texto.
      expect(find.text('Municipalidad de Tarapoto'), findsOneWidget);
      expect(
        find.text('Jr. Jiménez Pimentel 210, Tarapoto 22202, Perú'),
        findsNothing,
      );
      expect(_offerAmountFinder, findsOneWidget);
    },
  );

  testWidgets(
    'G4B-CONTRACT-R1: manda destination.isManualSelection=true al tocar el '
    'mapa y false al elegir por autocomplete — sin depender del texto de '
    'destinationAddress (lo que este contrato reemplaza)',
    (tester) async {
      const prediction = PlacePrediction(
        placeId: 'place-1',
        primaryText: 'Municipalidad de Tarapoto',
        secondaryText: 'Jr. Jiménez Pimentel 210',
        fullText: 'Municipalidad de Tarapoto, Jr. Jiménez Pimentel 210',
        distanceMeters: 500,
      );
      const details = PlaceDetails(
        placeId: 'place-1',
        formattedAddress: 'Jr. Jiménez Pimentel 210, Tarapoto 22202, Perú',
        latitude: -6.4812,
        longitude: -76.3655,
      );

      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();
      final placesRepository = _FakePlacesRepository(
        predictions: const [prediction],
        details: details,
      );

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        placesRepository: placesRepository,
      );

      // Llamada 1: destino elegido tocando el mapa.
      await _selectDestinationOnMap(tester);

      expect(fareRepository.callCount, 1);
      expect(fareRepository.requestedIsManualSelection[0], isTrue);

      // HOME-FLOW-R1 etapa 4: con destino, back no vuelve a la pantalla de
      // búsqueda ni sale de Home; consume el pop y llama al mismo
      // `_clearDestination` que usa "Quitar destino" en la tarjeta.
      await tester.binding.handlePopRoute();
      await _flushAsync(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-destination-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('origin-destination-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home-search-trigger')),
        findsOneWidget,
      );

      await _selectDestinationViaAutocomplete(
        tester,
        query: 'Municipalidad',
        prediction: prediction,
      );

      expect(fareRepository.callCount, 2);
      expect(fareRepository.requestedIsManualSelection[1], isFalse);
    },
  );

  testWidgets('G4B-R5.2-4: respuesta obsoleta de A no puede sobrescribir la '
      'dirección real de B', (tester) async {
    final fareRepository = _FakeFareRepository(
      estimatedFare: '7.00',
      holdRequests: true,
      destinationAddressOverrides: const ['Dirección A', 'Dirección B'],
    );
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));

    map.onTap!(const LatLng(-6.4880, -76.3600)); // A
    await tester.pump();

    map.onTap!(const LatLng(-6.5000, -76.4000)); // B
    await tester.pump();

    expect(fareRepository.callCount, 2);

    // Responde A (la vieja) primero.
    fareRepository.resolveCall(0);
    await _flushAsync(tester);

    expect(find.text('Dirección A'), findsNothing);

    // Responde B.
    fareRepository.resolveCall(1);
    await _flushAsync(tester);

    expect(find.text('Dirección B'), findsOneWidget);
    expect(find.text('Dirección A'), findsNothing);
  });

  testWidgets(
    'G4B-R5.2-5: si Backend no resuelve una dirección real, se conserva '
    'su fallback honesto sin bloquear la oferta',
    (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        destinationAddressOverrides: const ['Destino seleccionado'],
      );
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      // El fallback de Backend reemplaza al placeholder local, pero
      // sigue siendo honesto: nadie inventó una calle.
      expect(find.text('Destino seleccionado'), findsOneWidget);
      expect(find.text('Destino seleccionado en el mapa'), findsNothing);
      expect(_offerAmountFinder, findsOneWidget);

      // El stepper arranca en la oferta mínima válida; el CTA no
      // depende de que el Passenger ajuste nada.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    },
  );

  // FARE-PANEL-R1 (Etapa 2): G4B-R3-7/8/9 validaban el campo de texto
  // libre de la oferta (vacío / 0 / >2 decimales dejaban el CTA
  // deshabilitado). El stepper reemplazó ese campo: la oferta siempre
  // está clampeada en [S/ 3.00, S/ 50.00] y ya no puede ser inválida,
  // así que esos tres casos dejaron de existir. La cobertura de los
  // límites del stepper vive en el grupo
  // 'FARE-PANEL-R1 — stepper de precio y Mototaxi'.

  testWidgets(
    'G4B-R3-10 (FARE-PANEL-R1): createRide recibe el monto formado desde '
    'el stepper (_offerCents)',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      // 3.00 → 3.50 → 4.00
      await _tapOfferIncrement(tester);
      await _tapOfferIncrement(tester);
      expect(_shownOfferAmount(tester), 'S/ 4.00');

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRideCalls, hasLength(1));
      expect(rideRepository.createRideCalls.single, '4.00');
    },
  );

  testWidgets(
    'HOME-LAYOUT-R1: el CTA es alcanzable con teclado abierto y la hoja '
    'en su estado más alto (destino + cotización + oferta), sin scroll '
    'manual — mismo patrón que el test equivalente de login/registro, '
    'pero sin `ensureVisible`: el CTA vive fuera de la región '
    'scrolleable de la hoja',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      for (final size in [const Size(360, 640), const Size(390, 844)]) {
        final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
        final rideRepository = _FakeRideRepository();

        tester.view.physicalSize = size;
        tester.view.viewInsets = const FakeViewPadding();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        await _selectDestinationOnMap(tester);
        await tester.pump();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();

        final cta = find.text('Ofrecer y buscar conductor');
        final ctaRect = tester.getRect(cta);
        final keyboardTop = size.height - 300;

        expect(cta, findsOneWidget);
        expect(ctaRect.top, greaterThanOrEqualTo(0));
        expect(ctaRect.bottom, lessThanOrEqualTo(keyboardTop));
        expect(tester.takeException(), isNull);
      }

      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('ORIGIN-ADDRESS-R1', () {
    testWidgets(
      'resuelve y muestra la dirección real de origen apenas hay GPS, '
      'sin esperar a que se elija destino',
      (tester) async {
        final fareRepository = _FakeFareRepository(
          estimatedFare: '7.00',
          originAddress: 'Calle Rioja 495, Tarapoto',
        );
        final rideRepository = _FakeRideRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        expect(fareRepository.originAddressCallCount, 1);
        expect(fareRepository.requestedOriginCoordinates.single, [
          -6.4877,
          -76.3599,
        ]);

        // HOME-FLOW-R1: sin destino, la tarjeta origen/destino ya no
        // vive en la hoja (se muda arriba recién en la etapa 4) — solo
        // queda la etiqueta del marcador flotante, en su versión corta
        // (`_shortAddressLabel`, recorte por coma).
        expect(find.text('Calle Rioja 495'), findsOneWidget);
        expect(find.text('Calle Rioja 495, Tarapoto'), findsNothing);
        expect(find.text('Tu ubicación actual'), findsNothing);

        // Sin destino, jamás se dispara una cotización — la dirección
        // resuelta no depende de eso.
        expect(fareRepository.callCount, 0);
      },
    );

    testWidgets('si falla la resolución, no rompe la pantalla y conserva el '
        'placeholder existente', (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        failOriginAddress: true,
      );
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      expect(fareRepository.originAddressCallCount, 1);
      // HOME-FLOW-R1: sin la tarjeta de la hoja, solo queda la
      // etiqueta del marcador flotante.
      expect(find.text('Tu ubicación actual'), findsOneWidget);

      // La pantalla sigue funcional: el disparador de búsqueda sigue
      // ahí, habilitado (el fallo fue en la dirección, no en el GPS).
      expect(
        find.byKey(const ValueKey('home-search-trigger')),
        findsOneWidget,
      );
    });

    testWidgets('la dirección real de la cotización siempre gana sobre la '
        'resuelta preemptivamente', (tester) async {
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        originAddress: 'Preemptiva: Jr. Lima 250',
      );
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      // HOME-FLOW-R1: sin destino, solo la etiqueta del marcador
      // flotante muestra la dirección ('Preemptiva: Jr. Lima 250' no
      // tiene coma, así que no hay nada que recortar).
      expect(find.text('Preemptiva: Jr. Lima 250'), findsOneWidget);

      await _selectDestinationOnMap(tester);

      // La cotización real (fake fija su propio originAddress) pisa
      // la dirección preemptiva, sin ambigüedad de prioridad.
      expect(find.text('Preemptiva: Jr. Lima 250'), findsNothing);
      expect(fareRepository.callCount, 1);
    });

    testWidgets('dentro del umbral de cacheo por distancia, no vuelve a llamar '
        'al backend', (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      // Segundo punto a ~5m del primero — muy por debajo de los 50m
      // del umbral (~0.00005° de latitud ya son unos 5.5m en esta
      // latitud).
      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        locationSequence: [
          _buildPosition(-6.4877, -76.3599),
          _buildPosition(-6.48775, -76.3599),
        ],
      );

      expect(fareRepository.originAddressCallCount, 1);

      await _tapCenterOnMyLocation(tester);

      expect(fareRepository.originAddressCallCount, 1);
    });

    testWidgets('fuera del umbral de cacheo por distancia, resuelve una '
        'dirección nueva', (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      // Segundo punto a ~1.1km del primero (0.01° de latitud) — muy
      // por encima de los 50m del umbral.
      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        locationSequence: [
          _buildPosition(-6.4877, -76.3599),
          _buildPosition(-6.4977, -76.3599),
        ],
      );

      expect(fareRepository.originAddressCallCount, 1);

      await _tapCenterOnMyLocation(tester);

      expect(fareRepository.originAddressCallCount, 2);
      expect(fareRepository.requestedOriginCoordinates[1], [-6.4977, -76.3599]);
    });

    testWidgets('varios taps rápidos sin moverse producen una sola llamada y '
        'la respuesta tardía vuelve a medir el overlay superior', (
      tester,
    ) async {
      // FARE-PANEL-R1 (Etapa 5): sin coma a propósito -- `shortAddressLabel`
      // es no-op sobre una dirección sin coma, así que este fixture
      // sigue provocando el mismo crecimiento de alto que antes de esa
      // etapa (con coma, quedaría recortado a un nombre corto de una
      // sola línea y ya no ejercitaría el remedido tardío que prueba
      // este test).
      const longOriginAddress =
          'Avenida Circunvalación 1845 referencia frente al mercado de '
          'productores del barrio Partido Alto Tarapoto San Martín Perú';
      final fareRepository = _FakeFareRepository(
        estimatedFare: '7.00',
        originAddress: longOriginAddress,
        quoteOriginAddress: '',
        routePolyline: '??AA',
        holdOriginAddressRequests: true,
      );
      final rideRepository = _FakeRideRepository();

      // Sin `locationSequence`: siempre el mismo punto fijo — el
      // Passenger no se movió entre taps.
      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      // La primera llamada real ya se disparó y quedó "en vuelo"
      // a propósito (holdOriginAddressRequests) — el Passenger
      // todavía no ve la dirección resuelta.
      expect(fareRepository.originAddressCallCount, 1);

      // Varios taps rápidos de "centrar en mi ubicación" mientras
      // esa primera llamada sigue sin responder. Cada tap completa
      // su propio ciclo de GPS/cámara (no depende de
      // origin-address), pero ninguno debe disparar una segunda
      // llamada al backend para prácticamente el mismo punto — este
      // es el bug reportado (taps repetidos acumulando llamadas).
      await _tapCenterOnMyLocation(tester);
      await _tapCenterOnMyLocation(tester);
      await _tapCenterOnMyLocation(tester);

      expect(fareRepository.originAddressCallCount, 1);

      // La tarjeta ya está visible y la ruta activa antes de que llegue
      // `_resolveOriginAddress`: reproduce el cambio de alto tardío que
      // rompía el encuadre cuando la geometría se estimaba a mano.
      await _selectDestinationOnMap(tester);
      final card = find.byKey(const ValueKey('origin-destination-card'));
      final initialCardHeight = tester.getSize(card).height;
      final initialTopPadding = tester
          .widget<GoogleMap>(find.byType(GoogleMap))
          .padding
          .top;
      final dynamic state = tester.state(find.byType(HomeScreen));
      final int initialScheduleGeneration =
          state.debugRouteFitScheduleGeneration as int;

      // Al responder la única llamada real, se refleja con
      // normalidad y el mismo programador de reencuadre vuelve a correr.
      fareRepository.resolveOriginAddressCall(0);
      await _flushAsync(tester);

      expect(find.text(longOriginAddress), findsOneWidget);
      expect(tester.getSize(card).height, greaterThan(initialCardHeight));
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.top,
        greaterThan(initialTopPadding),
      );
      expect(
        state.debugRouteFitScheduleGeneration as int,
        greaterThan(initialScheduleGeneration),
      );

      // Un tap posterior, ya con la dirección resuelta y sin
      // movimiento, tampoco dispara una llamada nueva.
      await _tapCenterOnMyLocation(tester);

      expect(fareRepository.originAddressCallCount, 1);
    });
  });

  group('HOME-LAYOUT-R1 — etiqueta corta del marcador propio', () {
    testWidgets(
      'con coma en la dirección, el marcador muestra solo la parte antes '
      'de la primera coma; sin destino no hay tarjeta que muestre la '
      'dirección completa',
      (tester) async {
        final fareRepository = _FakeFareRepository(
          estimatedFare: '7.00',
          originAddress: 'Calle Rioja 495, Tarapoto 22202, Perú',
        );
        final rideRepository = _FakeRideRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        expect(find.text('Calle Rioja 495'), findsOneWidget);
        // HOME-FLOW-R1: la tarjeta que mostraba la dirección completa
        // ya no vive en Home vacío.
        expect(
          find.text('Calle Rioja 495, Tarapoto 22202, Perú'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'sin coma en la dirección, el marcador muestra el texto completo tal '
      'cual — nada que recortar',
      (tester) async {
        final fareRepository = _FakeFareRepository(
          estimatedFare: '7.00',
          originAddress: 'Terminal Terrestre',
        );
        final rideRepository = _FakeRideRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        // HOME-FLOW-R1: un solo lugar (el marcador) muestra la
        // dirección en Home vacío -- no hay coma que recortar, así que
        // la etiqueta corta coincide con la completa de todas formas.
        expect(find.text('Terminal Terrestre'), findsOneWidget);
      },
    );

    testWidgets(
      'al elegir destino oculta la etiqueta del origen y muestra el origen '
      'en la tarjeta flotante superior',
      (tester) async {
        final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
        final rideRepository = _FakeRideRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        expect(find.text('Calle Rioja 495'), findsOneWidget);
        // HOME-FLOW-R1: sin destino, la tarjeta flotante con la dirección
        // completa todavía no existe.
        expect(find.text('Calle Rioja 495, Tarapoto'), findsNothing);

        await _selectDestinationOnMap(tester);

        expect(find.text('Calle Rioja 495'), findsNothing);
        expect(find.text('Tu ubicación actual'), findsOneWidget);
        expect(find.text('Destino seleccionado en el mapa'), findsWidgets);

        final card = find.byKey(const ValueKey('origin-destination-card'));
        final sheet = find.byKey(const ValueKey('home-bottom-sheet'));
        final cardRect = tester.getRect(card);
        final mapRect = tester.getRect(find.byType(GoogleMap));
        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));

        expect(cardRect.left, mapRect.left + 20);
        expect(cardRect.right, mapRect.right - 20);
        expect(
          cardRect.top,
          greaterThan(tester.getBottomLeft(find.byTooltip('Abrir menú')).dy),
        );
        expect(map.padding.top, closeTo(cardRect.bottom - mapRect.top, 0.01));
        expect(map.padding.bottom, greaterThan(0));
        expect(find.descendant(of: sheet, matching: card), findsNothing);
        expect(
          find.descendant(of: sheet, matching: _offerAmountFinder),
          findsOneWidget,
        );
        expect(find.text('¿A dónde vamos?'), findsNothing);
      },
    );
  });

  group('SUGGESTED-DESTINATIONS-R1', () {
    testWidgets('sin historial, no se muestra ninguna sugerencia', (
      tester,
    ) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      expect(rideRepository.getHistoryCallCount, 1);
      // HOME-FLOW-R1: lista vertical con clave propia, ya no chips
      // identificadas por el ícono de historial.
      expect(
        find.byKey(const ValueKey('suggested-destinations-list')),
        findsNothing,
      );
    });

    testWidgets(
      'con historial, muestra hasta suggestedDestinationsCount sugerencias, '
      'la más frecuente primero',
      (tester) async {
        final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
        final now = DateTime(2026, 8, 24, 12);
        final rideRepository = _FakeRideRepository(
          history: [
            // UPEU: 3 viajes → la más frecuente.
            _historyItem(
              rideId: 'r1',
              destinationAddress: 'UPEU',
              requestedAt: now,
            ),
            _historyItem(
              rideId: 'r2',
              destinationAddress: 'UPEU',
              requestedAt: now.subtract(const Duration(days: 1)),
            ),
            _historyItem(
              rideId: 'r3',
              destinationAddress: 'UPEU',
              requestedAt: now.subtract(const Duration(days: 2)),
            ),
            // Terminal: 2 viajes → segunda más frecuente.
            _historyItem(
              rideId: 'r4',
              destinationAddress: 'Terminal Terrestre',
              requestedAt: now.subtract(const Duration(hours: 3)),
            ),
            _historyItem(
              rideId: 'r5',
              destinationAddress: 'Terminal Terrestre',
              requestedAt: now.subtract(const Duration(days: 3)),
            ),
            // Plaza: 1 solo viaje → no entra (solo caben 2).
            _historyItem(
              rideId: 'r6',
              destinationAddress: 'Plaza de Armas',
              requestedAt: now.subtract(const Duration(hours: 1)),
            ),
          ],
        );

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        expect(find.text('UPEU'), findsOneWidget);
        expect(find.text('Terminal Terrestre'), findsOneWidget);
        expect(find.text('Plaza de Armas'), findsNothing);
      },
    );

    testWidgets('toca una sugerencia: fija destino y dispara la cotización sin '
        'autocomplete ni details', (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository(
        history: [
          _historyItem(
            rideId: 'r1',
            destinationAddress: 'UPEU',
            destinationLatitude: -6.5123,
            destinationLongitude: -76.3712,
            requestedAt: DateTime(2026, 8, 24),
          ),
        ],
      );

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      expect(fareRepository.callCount, 0);

      await tester.tap(find.text('UPEU'));
      await _flushAsync(tester);

      expect(fareRepository.callCount, 1);
      expect(_offerAmountFinder, findsOneWidget);
    });

    testWidgets('la sugerencia queda deshabilitada mientras no hay GPS', (
      tester,
    ) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository(
        history: [
          _historyItem(
            rideId: 'r1',
            destinationAddress: 'UPEU',
            requestedAt: DateTime(2026, 8, 24),
          ),
        ],
      );
      final geolocator = _FakeGeolocatorPlatform(hold: true);

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
        geolocatorPlatform: geolocator,
      );

      // Sin GPS todavía: la sugerencia ya cargó (no depende del
      // GPS), pero tocarla no debe hacer nada.
      expect(find.text('UPEU'), findsOneWidget);

      await tester.tap(find.text('UPEU'));
      await _flushAsync(tester);

      expect(fareRepository.callCount, 0);

      geolocator.releaseHold();
      await _flushAsync(tester);

      await tester.tap(find.text('UPEU'));
      await _flushAsync(tester);

      expect(fareRepository.callCount, 1);
    });

    testWidgets('una vez elegido un destino, deja de mostrarse la sección de '
        'sugerencias', (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository(
        history: [
          _historyItem(
            rideId: 'r1',
            destinationAddress: 'UPEU',
            requestedAt: DateTime(2026, 8, 24),
          ),
        ],
      );

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      expect(find.text('UPEU'), findsOneWidget);

      await _selectDestinationOnMap(tester);

      // HOME-FLOW-R1: la lista de sugeridos es exclusiva de Home
      // vacío -- ya no existe ninguna hoja vacía que la muestre.
      expect(
        find.byKey(const ValueKey('suggested-destinations-list')),
        findsNothing,
      );
    });

    testWidgets(
      'FARE-PANEL-R1 (Etapa 5): tocar una sugerencia con coma en la '
      'dirección muestra el nombre corto en la tarjeta una sola vez, sin '
      'duplicado',
      (tester) async {
        const fullAddress =
            'Universidad Peruana Unión, Km. 19 Carretera Fernando '
            'Belaunde Terry';
        const shortName = 'Universidad Peruana Unión';

        final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
        final rideRepository = _FakeRideRepository(
          history: [
            _historyItem(
              rideId: 'r1',
              destinationAddress: fullAddress,
              requestedAt: DateTime(2026, 8, 24),
            ),
          ],
        );

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        // La fila de sugerencia muestra la dirección completa tal cual
        // llega del historial -- el recorte es propio de la tarjeta,
        // no de la lista de sugerencias.
        expect(find.text(fullAddress), findsOneWidget);

        await tester.tap(find.text(fullAddress));
        await _flushAsync(tester);

        // Antes del bug fix, `_selectedDestinationName` y
        // `_selectedDestinationAddress` quedaban con la misma cadena
        // completa -- la tarjeta la mostraba dos veces (título y
        // subtítulo). Ahora la tarjeta muestra solo el nombre corto,
        // una única vez.
        expect(find.text(shortName), findsOneWidget);
        expect(find.text(fullAddress), findsNothing);
      },
    );
  });

  group('FARE-PANEL-R1 — método de pago', () {
    final buttonFinder = find.byKey(const ValueKey('payment-method-button'));

    testWidgets(
      'con destino, el botón de método de pago aparece y muestra Efectivo por '
      'defecto; sin destino no existe',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );

        expect(buttonFinder, findsNothing);

        await _selectDestinationOnMap(tester);

        expect(buttonFinder, findsOneWidget);
        expect(
          find.descendant(of: buttonFinder, matching: find.byIcon(Icons.payments)),
          findsOneWidget,
        );
        expect(
          tester.widget<IconButton>(buttonFinder).tooltip,
          'Método de pago: Efectivo',
        );
      },
    );

    testWidgets(
      'el selector ofrece exactamente Efectivo, Yape y Plin — nunca Tarjeta',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );
        await _selectDestinationOnMap(tester);

        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(find.text('¿Cómo vas a pagar?'), findsOneWidget);
        expect(find.byKey(const ValueKey('payment-option-cash')), findsOneWidget);
        expect(find.byKey(const ValueKey('payment-option-yape')), findsOneWidget);
        expect(find.byKey(const ValueKey('payment-option-plin')), findsOneWidget);
        expect(find.text('Efectivo'), findsOneWidget);
        expect(find.text('Yape'), findsOneWidget);
        expect(find.text('Plin'), findsOneWidget);
        expect(find.textContaining('Tarjeta'), findsNothing);
        expect(find.textContaining('CARD'), findsNothing);

        // La opción activa (cash) lleva el check.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('payment-option-cash')),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('elegir Yape cambia el ícono del botón y lo persiste', (
      tester,
    ) async {
      final paymentRepo = _FakePaymentPreferenceRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
        paymentPreferenceRepository: paymentRepo,
      );
      await _selectDestinationOnMap(tester);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-option-yape')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: buttonFinder, matching: find.byIcon(Icons.smartphone)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: buttonFinder, matching: find.byIcon(Icons.payments)),
        findsNothing,
      );
      expect(paymentRepo.writes, [PaymentMethod.yape]);
    });

    testWidgets(
      'el método persistido del viaje anterior se restaura al abrir Home',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          paymentPreferenceRepository: _FakePaymentPreferenceRepository(
            PaymentMethod.plin,
          ),
        );
        await _selectDestinationOnMap(tester);

        expect(
          find.descendant(
            of: buttonFinder,
            matching: find.byIcon(Icons.qr_code_2),
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<IconButton>(buttonFinder).tooltip,
          'Método de pago: Plin',
        );
      },
    );

    testWidgets('createRide recibe el wireValue del método elegido', (
      tester,
    ) async {
      final rideRepository = _FakeRideRepository();
      final paymentRepo = _FakePaymentPreferenceRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: rideRepository,
        paymentPreferenceRepository: paymentRepo,
      );

      await _selectDestinationOnMap(tester);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-option-yape')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRidePaymentMethods, ['YAPE']);
      expect(paymentRepo.writes, [PaymentMethod.yape]);
    });

    testWidgets('sin tocar el selector, createRide manda CASH (default)', (
      tester,
    ) async {
      final rideRepository = _FakeRideRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRidePaymentMethods, ['CASH']);
    });
  });

  group('FARE-PANEL-R1 — stepper de precio y Mototaxi', () {
    testWidgets(
      'sin destino/cotización, el stepper y la fila Mototaxi no se dibujan',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );

        expect(_offerAmountFinder, findsNothing);
        expect(find.byKey(const ValueKey('mototaxi-info-button')), findsNothing);

        await _selectDestinationOnMap(tester);

        expect(_offerAmountFinder, findsOneWidget);
        expect(
          find.byKey(const ValueKey('mototaxi-info-button')),
          findsOneWidget,
        );
        expect(_shownOfferAmount(tester), 'S/ 3.00');
      },
    );

    testWidgets('+ y − mueven el monto en pasos de S/ 0.50', (tester) async {
      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
      );
      await _selectDestinationOnMap(tester);

      expect(_shownOfferAmount(tester), 'S/ 3.00');

      await _tapOfferIncrement(tester);
      expect(_shownOfferAmount(tester), 'S/ 3.50');

      await _tapOfferIncrement(tester);
      expect(_shownOfferAmount(tester), 'S/ 4.00');

      await tester.tap(_offerDecrementFinder);
      await tester.pump();
      expect(_shownOfferAmount(tester), 'S/ 3.50');
    });

    testWidgets('el botón − está deshabilitado en el mínimo S/ 3.00', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
      );
      await _selectDestinationOnMap(tester);

      expect(_shownOfferAmount(tester), 'S/ 3.00');
      expect(
        tester.widget<IconButton>(_offerDecrementFinder).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_offerIncrementFinder).onPressed,
        isNotNull,
      );
    });

    testWidgets('el botón + está deshabilitado en el máximo S/ 50.00', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
      );
      await _selectDestinationOnMap(tester);

      // (5000 - 300) / 50 = 94 pasos hasta el tope.
      for (var i = 0; i < 94; i++) {
        await _tapOfferIncrement(tester);
      }

      expect(_shownOfferAmount(tester), 'S/ 50.00');
      expect(
        tester.widget<IconButton>(_offerIncrementFinder).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_offerDecrementFinder).onPressed,
        isNotNull,
      );

      // Un tap extra sobre el botón deshabilitado no cambia nada.
      await tester.tap(_offerIncrementFinder);
      await tester.pump();
      expect(_shownOfferAmount(tester), 'S/ 50.00');
    });

    testWidgets(
      'tocar la cifra y el lápiz de Mototaxi abren "Ofrece tu tarifa" con '
      'el monto y método de pago actuales de Home',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );
        await _selectDestinationOnMap(tester);
        await _tapOfferIncrement(tester);
        expect(_shownOfferAmount(tester), 'S/ 3.50');

        await tester.tap(_offerAmountFinder);
        await tester.pumpAndSettle();

        expect(find.byType(OfferFareScreen), findsOneWidget);
        expect(
          tester.widget<TextField>(_offerFareAmountField()).controller!.text,
          '3.50',
        );
        expect(find.text('Efectivo'), findsOneWidget);

        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pumpAndSettle();

        expect(find.byType(OfferFareScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('mototaxi-edit-button')));
        await tester.pumpAndSettle();

        expect(find.byType(OfferFareScreen), findsOneWidget);
      },
    );

    testWidgets(
      'back en "Ofrece tu tarifa" sin confirmar no cambia nada en Home',
      (tester) async {
        final rideRepository = _FakeRideRepository();
        final paymentPreferenceRepository = _FakePaymentPreferenceRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: rideRepository,
          paymentPreferenceRepository: paymentPreferenceRepository,
        );
        await _selectDestinationOnMap(tester);

        await tester.tap(_offerAmountFinder);
        await tester.pumpAndSettle();

        await tester.enterText(_offerFareAmountField(), '9.00');
        await tester.pump();

        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pumpAndSettle();

        expect(_shownOfferAmount(tester), 'S/ 3.00');
        expect(rideRepository.createRideCalls, isEmpty);
        expect(paymentPreferenceRepository.writes, isEmpty);
      },
    );

    testWidgets(
      'confirmar en "Ofrece tu tarifa" actualiza el monto/método de pago '
      'en Home y pide el viaje con esos valores',
      (tester) async {
        final rideRepository = _FakeRideRepository();
        final paymentPreferenceRepository = _FakePaymentPreferenceRepository();

        await _pumpRoutedHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: rideRepository,
          paymentPreferenceRepository: paymentPreferenceRepository,
        );
        await _selectDestinationOnMap(tester);

        await tester.tap(_offerAmountFinder);
        await tester.pumpAndSettle();

        await tester.enterText(_offerFareAmountField(), '12.00');
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('offer-fare-payment-method-row')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('payment-option-yape')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('offer-fare-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(OfferFareScreen), findsNothing);
        expect(rideRepository.createRideCalls, ['12.00']);
        expect(rideRepository.createRidePaymentMethods, ['YAPE']);
        expect(paymentPreferenceRepository.writes, [PaymentMethod.yape]);
      },
    );

    testWidgets(
      'si la cotización se renueva sola mientras el pasajero está en '
      '"Ofrece tu tarifa", confirmar pide el viaje con la cotización ya '
      'renovada',
      (tester) async {
        final fareRepository = _FakeFareRepository(
          estimatedFare: '7.00',
          firstQuoteTtl: const Duration(seconds: 2),
        );
        final rideRepository = _FakeRideRepository();

        await _pumpRoutedHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );
        await _selectDestinationOnMap(tester);
        expect(fareRepository.callCount, 1);

        await tester.tap(_offerAmountFinder);
        await tester.pumpAndSettle();

        // La cotización vence y se renueva sola mientras la pantalla de
        // confirmación sigue abierta encima de Home — mismo Timer que
        // ya cubre `G4B-R5.1-6/7`, sin código nuevo en esta pantalla.
        await tester.pump(const Duration(seconds: 3));
        await _flushAsync(tester);
        expect(fareRepository.callCount, 2);

        await tester.tap(
          find.byKey(const ValueKey('offer-fare-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(rideRepository.createRideCalls, hasLength(1));
      },
    );

    testWidgets('el ⓘ abre la hoja informativa y "Entendido" la cierra', (
      tester,
    ) async {
      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
      );
      await _selectDestinationOnMap(tester);

      expect(find.byKey(const ValueKey('mototaxi-info-sheet')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mototaxi-info-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mototaxi-info-sheet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mototaxi-info-sheet')),
          matching: find.text('Mototaxi'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Viaja en mototaxi por Tarapoto. Propón tu precio y el '
          'conductor decide si lo acepta.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('mototaxi-info-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mototaxi-info-sheet')), findsNothing);
    });

    testWidgets('mientras se pide el viaje, −/+, cifra, ⓘ y lápiz quedan '
        'deshabilitados', (tester) async {
      final rideRepository = _FakeRideRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      // Deja la request de createRide en vuelo para observar el estado
      // `_requestingRide == true`.
      rideRepository.holdCreateRide = true;
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(
        tester.widget<IconButton>(_offerIncrementFinder).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_offerDecrementFinder).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(
          find.byKey(const ValueKey('mototaxi-info-button')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(
          find.byKey(const ValueKey('mototaxi-edit-button')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<InkWell>(_offerAmountFinder).onTap,
        isNull,
      );

      rideRepository.releaseCreateRide();
      await _flushAsync(tester);
    });
  });

  group('PROFILE-MENU-R1', () {
    testWidgets(
      'el botón de 3 rayas abre el menú de perfil (ya no desloguea directo)',
      (tester) async {
        final authRepository = _FakeAuthRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          authRepository: authRepository,
        );

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();

        expect(find.byType(ProfileMenuDrawer), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(authRepository.logoutCalls, 0);
        // Cabecera con el perfil que cargó `initState`.
        expect(find.text('Ana Ruiz'), findsOneWidget);
      },
    );

    testWidgets(
      '"Cerrar sesión" abre el diálogo de confirmación; "Cancelar" no '
      'desloguea y deja al pasajero en Home',
      (tester) async {
        final authRepository = _FakeAuthRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          authRepository: authRepository,
        );

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-menu-logout')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('¿Cerrar sesión?'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(authRepository.logoutCalls, 0);
      },
    );

    testWidgets(
      'confirmar el logout llama a authRepository.logout() y navega a /login',
      (tester) async {
        final authRepository = _FakeAuthRepository();

        await _pumpHomeScreenWithLoginRoute(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          authRepository: authRepository,
        );

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('profile-menu-logout')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cerrar sesión'));
        await tester.pumpAndSettle();

        expect(authRepository.logoutCalls, 1);
        expect(find.text('LOGIN_DESTINATION'), findsOneWidget);
      },
    );

    testWidgets('tocar la cabecera navega a "Editar perfil"', (tester) async {
      await _pumpHomeScreen(
        tester,
        fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
        rideRepository: _FakeRideRepository(),
      );

      await tester.tap(find.byTooltip('Abrir menú'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-menu-header')));
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.byType(ProfileMenuDrawer), findsNothing);
    });

    testWidgets(
      'volver de "Editar perfil" con un perfil nuevo refresca la cabecera del '
      'menú',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();
        expect(find.text('Ana Ruiz'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('profile-menu-header')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, 'Carlos');
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('edit-profile-save-button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();
        expect(find.text('Carlos Ruiz'), findsOneWidget);
        expect(find.text('Ana Ruiz'), findsNothing);
      },
    );

    testWidgets(
      'si falla la carga del perfil, Home no se rompe y el menú ofrece '
      '"Reintentar"',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          passengerProfileRepository: _FakePassengerProfileRepository(
            getError: Exception('sin conexión'),
          ),
        );

        expect(find.byType(HomeScreen), findsOneWidget);
        final dynamic state = tester.state(find.byType(HomeScreen));
        expect(state.debugProfileLoadFailed, isTrue);

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();

        expect(find.byType(ProfileMenuDrawer), findsOneWidget);
        expect(find.text('No pudimos cargar tu perfil'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('profile-menu-retry')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'con el drawer abierto, el botón de retroceso de Android lo cierra sin '
      'salir de Home',
      (tester) async {
        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
        );

        await tester.tap(find.byTooltip('Abrir menú'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileMenuDrawer), findsOneWidget);

        // Botón de retroceso del sistema — mismo mecanismo que el test
        // de "back con destino elegido" de HOME-FLOW-R1.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // El drawer cerrado se desmonta (drawerEnableOpenDragGesture:
        // false), y Home sigue montado: el back no navegó a ningún lado.
        expect(find.byType(ProfileMenuDrawer), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });

  group('PASSENGER-PUSH-R1 (fix): registro de push tras el permiso de '
      'ubicación', () {
    testWidgets(
      'permiso de ubicación denegado en el check y concedido en el '
      'request → el registro de push se dispara una vez, después de '
      'resolver el permiso',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          geolocatorPlatform: _FakeGeolocatorPlatform(
            permissionOnCheck: LocationPermission.denied,
            permissionOnRequest: LocationPermission.whileInUse,
          ),
          pushCoordinator: coordinator,
        );

        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'permiso de ubicación denegado en el check Y en el request → el '
      'registro de push se dispara igual (el finally corre en el camino '
      'de permiso denegado)',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          geolocatorPlatform: _FakeGeolocatorPlatform(
            permissionOnCheck: LocationPermission.denied,
            permissionOnRequest: LocationPermission.denied,
          ),
          pushCoordinator: coordinator,
        );

        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'el registro de push NO se dispara ANTES de que el permiso de '
      'ubicación resuelva: con requestPermission() colgado, syncCalls '
      'sigue en 0; al liberarlo, pasa a 1',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();
        final geolocator = _FakeGeolocatorPlatform(
          permissionOnCheck: LocationPermission.denied,
          permissionOnRequest: LocationPermission.denied,
          holdRequestPermission: true,
        );

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          geolocatorPlatform: geolocator,
          pushCoordinator: coordinator,
        );

        // _loadCurrentLocation() está esperando en requestPermission():
        // el permiso de ubicación todavía no se resolvió, así que el
        // registro de push todavía no debe haberse disparado.
        expect(coordinator.syncCalls, 0);

        geolocator.releaseRequestPermissionHold();
        await _flushAsync(tester);

        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'servicio de ubicación apagado → el registro de push se dispara '
      'igual (early return dentro del try, el finally corre)',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          geolocatorPlatform: _FakeGeolocatorPlatform(serviceEnabled: false),
          pushCoordinator: coordinator,
        );

        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'getCurrentPosition lanza una excepción → el registro de push se '
      'dispara igual (catch + finally)',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          geolocatorPlatform: _FakeGeolocatorPlatform(throwOnGetPosition: true),
          pushCoordinator: coordinator,
        );

        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'volver a tocar el botón de recentrar NO vuelve a registrar el '
      'dispositivo (guard _pushRegistrationRequested, una vez por vida '
      'del State)',
      (tester) async {
        final coordinator = _FakePushRegistrationCoordinator();

        await _pumpHomeScreen(
          tester,
          fareRepository: _FakeFareRepository(estimatedFare: '7.00'),
          rideRepository: _FakeRideRepository(),
          pushCoordinator: coordinator,
        );

        expect(coordinator.syncCalls, 1);

        await _tapCenterOnMyLocation(tester);

        expect(coordinator.syncCalls, 1);
      },
    );
  });
}

// FARE-PANEL-R1 (Etapa 2): la oferta se ajusta con el stepper −/+, ya
// no con un `TextField` de texto libre.
final _offerAmountFinder = find.byKey(const ValueKey('offer-stepper-amount'));
final _offerIncrementFinder = find.byKey(
  const ValueKey('offer-stepper-increment'),
);
final _offerDecrementFinder = find.byKey(
  const ValueKey('offer-stepper-decrement'),
);

/// FARE-PANEL-R1 (Etapa 4, reestructuración visual): el campo de monto
/// de `OfferFareScreen` es un `TextField` propio con la key puesta
/// directamente (ya no envuelto en `TukiTextField`).
Finder _offerFareAmountField() =>
    find.byKey(const ValueKey('offer-fare-amount-field'));

/// Concatena los dos `Text` del stepper ("S/ " + "3.00") → "S/ 3.00".
String _shownOfferAmount(WidgetTester tester) {
  return tester
      .widgetList<Text>(
        find.descendant(of: _offerAmountFinder, matching: find.byType(Text)),
      )
      .map((t) => t.data ?? '')
      .join();
}

Future<void> _tapOfferIncrement(WidgetTester tester) async {
  await tester.tap(_offerIncrementFinder);
  await tester.pump();
}

/// G4B-R5: seleccionar destino ya dispara la cotización sola — no
/// hay un "Calcular tarifa" que tocar. Se flushea el async acá
/// mismo porque, en la práctica, seleccionar destino y obtener el
/// FareQuote son un solo paso desde la perspectiva del Passenger.
Future<void> _selectDestinationOnMap(WidgetTester tester) async {
  final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
  map.onTap!(const LatLng(-6.4880, -76.3600));
  await _flushAsync(tester);
}

/// ORIGIN-ADDRESS-R1: mismo botón que ya existía para recentrar el
/// mapa — dispara `_loadCurrentLocation()` de nuevo, con el siguiente
/// punto de `locationSequence` si el test lo configuró.
Future<void> _tapCenterOnMyLocation(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Centrar en mi ubicación'));
  await _flushAsync(tester);
}

/// G4B-R5.2, adaptado en `HOME-FLOW-R1` (etapa 3): la búsqueda ya no
/// es un campo inline de Home -- toca el disparador para abrir
/// `SearchDestinationScreen` (empuje real de `Navigator`, `_pumpHomeScreen`
/// ya envuelve `HomeScreen` en un `MaterialApp` que provee su propio
/// `Navigator`), escribe ahí, deja pasar el debounce real (450ms),
/// flushea `autocomplete()`, y toca la primera predicción -- mismo
/// camino real que usaría el Passenger, solo que ahora cruza una
/// pantalla completa en vez de un campo inline.
Future<void> _selectDestinationViaAutocomplete(
  WidgetTester tester, {
  required String query,
  required PlacePrediction prediction,
}) async {
  await tester.tap(find.byKey(const ValueKey('home-search-trigger')));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('search-destination-field')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await _flushAsync(tester);

  await tester.tap(find.text(prediction.primaryText));
  await tester.pumpAndSettle();
  await _flushAsync(tester);
}

Future<void> _flushAsync(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _pumpHomeScreen(
  WidgetTester tester, {
  required FareRepository fareRepository,
  required RideRepository rideRepository,
  PlacesRepository? placesRepository,
  PaymentPreferenceRepository? paymentPreferenceRepository,
  PassengerProfileRepository? passengerProfileRepository,
  AuthRepository? authRepository,
  List<Position>? locationSequence,
  _FakeGeolocatorPlatform? geolocatorPlatform,
  PushRegistrationCoordinator? pushCoordinator,
  MediaQueryData? mediaQueryData,
}) async {
  GeolocatorPlatform.instance =
      geolocatorPlatform ??
      _FakeGeolocatorPlatform(positions: locationSequence);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fareRepositoryProvider.overrideWithValue(fareRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
        paymentPreferenceRepositoryProvider.overrideWithValue(
          paymentPreferenceRepository ?? _FakePaymentPreferenceRepository(),
        ),
        passengerProfileRepositoryProvider.overrideWithValue(
          passengerProfileRepository ?? _FakePassengerProfileRepository(),
        ),
        // PASSENGER-PUSH-R1 (fix): HomeScreen dispara el registro de
        // push tras resolver el permiso de ubicación. El coordinador
        // real toca FirebaseMessaging.instance (ausente en flutter_test);
        // se reemplaza por un doble no-op salvo que el test pase otro.
        pushRegistrationCoordinatorProvider.overrideWithValue(
          pushCoordinator ?? _FakePushRegistrationCoordinator(),
        ),
        if (authRepository != null)
          authRepositoryProvider.overrideWithValue(authRepository),
        if (placesRepository != null)
          placesRepositoryProvider.overrideWithValue(placesRepository),
      ],
      child: MaterialApp(
        home: mediaQueryData == null
            ? const HomeScreen()
            : MediaQuery(data: mediaQueryData, child: const HomeScreen()),
      ),
    ),
  );

  await _flushAsync(tester);
}

/// Igual que `_pumpHomeScreen` pero dentro de un `GoRouter` real con
/// `/home` y `/login`, para los tests del menú de perfil que verifican
/// la navegación del logout (`context.go('/login')`).
Future<void> _pumpHomeScreenWithLoginRoute(
  WidgetTester tester, {
  required FareRepository fareRepository,
  required RideRepository rideRepository,
  required AuthRepository authRepository,
  PassengerProfileRepository? passengerProfileRepository,
  PushRegistrationCoordinator? pushCoordinator,
}) async {
  GeolocatorPlatform.instance = _FakeGeolocatorPlatform();

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('LOGIN_DESTINATION')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fareRepositoryProvider.overrideWithValue(fareRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
        paymentPreferenceRepositoryProvider.overrideWithValue(
          _FakePaymentPreferenceRepository(),
        ),
        passengerProfileRepositoryProvider.overrideWithValue(
          passengerProfileRepository ?? _FakePassengerProfileRepository(),
        ),
        pushRegistrationCoordinatorProvider.overrideWithValue(
          pushCoordinator ?? _FakePushRegistrationCoordinator(),
        ),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await _flushAsync(tester);
}

Future<void> _pumpRoutedHomeScreen(
  WidgetTester tester, {
  required FareRepository fareRepository,
  required RideRepository rideRepository,
  PaymentPreferenceRepository? paymentPreferenceRepository,
  PushRegistrationCoordinator? pushCoordinator,
}) async {
  GeolocatorPlatform.instance = _FakeGeolocatorPlatform();

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/ride/:rideId',
        builder: (context, state) =>
            const Scaffold(body: Text('RIDE_DESTINATION')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fareRepositoryProvider.overrideWithValue(fareRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
        paymentPreferenceRepositoryProvider.overrideWithValue(
          paymentPreferenceRepository ?? _FakePaymentPreferenceRepository(),
        ),
        passengerProfileRepositoryProvider.overrideWithValue(
          _FakePassengerProfileRepository(),
        ),
        pushRegistrationCoordinatorProvider.overrideWithValue(
          pushCoordinator ?? _FakePushRegistrationCoordinator(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await _flushAsync(tester);
}

class _FakePlacesRepository extends PlacesRepository {
  _FakePlacesRepository({required this.predictions, required this.details})
    : super(Dio());

  final List<PlacePrediction> predictions;
  final PlaceDetails details;

  @override
  Future<List<PlacePrediction>> autocomplete({
    required String input,
    required double latitude,
    required double longitude,
    required String sessionToken,
  }) async {
    return predictions;
  }

  @override
  Future<PlaceDetails> getDetails({
    required String placeId,
    required String sessionToken,
  }) async {
    return details;
  }
}

Position _buildPosition(double latitude, double longitude) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  /// ORIGIN-ADDRESS-R1: por defecto (`positions == null`) siempre
  /// devuelve el mismo punto fijo, igual que antes de este campo —
  /// ningún test existente cambia de comportamiento. Cuando se pasa
  /// una secuencia, cada llamada devuelve el siguiente punto (se
  /// queda en el último una vez agotada), para simular al Passenger
  /// moviéndose entre aperturas/taps de "centrar en mi ubicación".
  _FakeGeolocatorPlatform({
    this.positions,
    this.hold = false,
    this.serviceEnabled = true,
    this.permissionOnCheck = LocationPermission.whileInUse,
    this.permissionOnRequest = LocationPermission.whileInUse,
    this.holdRequestPermission = false,
    this.throwOnGetPosition = false,
  });

  final List<Position>? positions;
  int _callIndex = 0;

  /// SUGGESTED-DESTINATIONS-R1: si es `true`, `getCurrentPosition`
  /// queda pendiente hasta [releaseHold] — permite reproducir "el
  /// pasajero todavía no tiene GPS" sin depender de timing real.
  final bool hold;
  final Completer<void> _holdCompleter = Completer<void>();

  /// PASSENGER-PUSH-R1 (fix): controles del paso de permiso de
  /// ubicación de `_loadCurrentLocation()`. Por defecto replican el
  /// comportamiento previo (servicio activo, permiso `whileInUse` en el
  /// check, sin pasar por `requestPermission()`), así que ningún test
  /// existente cambia.
  final bool serviceEnabled;
  final LocationPermission permissionOnCheck;
  final LocationPermission permissionOnRequest;

  /// Si es `true`, `requestPermission()` queda pendiente hasta
  /// [releaseRequestPermissionHold] — para probar que el registro de
  /// push NO se dispara antes de que el permiso de ubicación resuelva.
  final bool holdRequestPermission;
  final Completer<void> _requestPermissionHoldCompleter = Completer<void>();

  /// Si es `true`, `getCurrentPosition()` lanza — para probar que el
  /// `finally` (y con él el registro de push) corre igual ante un
  /// error de GPS.
  final bool throwOnGetPosition;

  void releaseHold() {
    if (!_holdCompleter.isCompleted) {
      _holdCompleter.complete();
    }
  }

  void releaseRequestPermissionHold() {
    if (!_requestPermissionHoldCompleter.isCompleted) {
      _requestPermissionHoldCompleter.complete();
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permissionOnCheck;

  @override
  Future<LocationPermission> requestPermission() async {
    if (holdRequestPermission) {
      await _requestPermissionHoldCompleter.future;
    }
    return permissionOnRequest;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (throwOnGetPosition) {
      throw Exception('GPS falló en el test');
    }

    if (hold) {
      await _holdCompleter.future;
    }

    final queue = positions;

    if (queue == null || queue.isEmpty) {
      return _buildPosition(-6.4877, -76.3599);
    }

    final position = queue[_callIndex.clamp(0, queue.length - 1)];

    _callIndex++;

    return position;
  }
}

class _NoopPushMessagingService implements PushMessagingService {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
}

/// PASSENGER-PUSH-R1 (fix): doble del coordinador de push para los
/// tests de Home. Cuenta las invocaciones de `syncDeviceRegistration()`
/// para verificar CUÁNDO dispara `HomeScreen` el registro (después de
/// resolver el permiso de ubicación) y que el guard local lo limita a
/// una vez.
class _FakePushRegistrationCoordinator extends PushRegistrationCoordinator {
  _FakePushRegistrationCoordinator()
    : super(
        _NoopPushMessagingService(),
        DeviceIdStore(const FlutterSecureStorage()),
        PushRegistrationRepository(Dio()),
      );

  int syncCalls = 0;

  @override
  Future<void> syncDeviceRegistration() async {
    syncCalls += 1;
  }
}

class _FakeFareRepository extends FareRepository {
  _FakeFareRepository({
    required this.estimatedFare,
    this.firstQuoteAlreadyExpired = false,
    this.firstQuoteTtl,
    this.failFirstCall = false,
    this.holdRequests = false,
    this.destinationAddressOverrides,
    this.originAddress = 'Calle Rioja 495, Tarapoto',
    this.quoteOriginAddress = 'Tu ubicación actual',
    this.routePolyline,
    this.failOriginAddress = false,
    this.holdOriginAddressRequests = false,
  }) : super(Dio());

  String estimatedFare;
  bool firstQuoteAlreadyExpired;

  /// Vigencia de la PRIMERA cotización devuelta. Permite simular un
  /// vencimiento real (vía Timer) en vez de uno ya vencido al llegar.
  Duration? firstQuoteTtl;
  bool failFirstCall;

  /// G4B-R5.1: si es `true`, cada llamada queda pendiente (su
  /// Future no se resuelve) hasta que el test la libere explícitamente
  /// con [resolveCall] — permite reproducir el escenario exacto de
  /// "A pendiente, cambia a B, responde A, responde B".
  bool holdRequests;

  /// G4B-R5.2: dirección que Backend "resolvió" para la llamada N
  /// (índice `N - 1`). Simula reverse geocoding real: si no hay
  /// override para esa llamada, se hace eco del `destinationAddress`
  /// recibido — mismo comportamiento que Backend con autocomplete
  /// (no reemplaza una dirección real ya enviada por el cliente).
  List<String>? destinationAddressOverrides;

  int callCount = 0;

  final List<String> requestedDestinationAddresses = [];

  /// G4B-CONTRACT-R1: qué mandó `home_screen.dart` como
  /// `destination.isManualSelection` en cada llamada (índice `N - 1`,
  /// igual que [destinationAddressOverrides]). Permite verificar que
  /// la pantalla manda la bandera correcta SIN depender de comparar
  /// texto contra ningún placeholder — justo lo que este contrato
  /// reemplaza.
  final List<bool> requestedIsManualSelection = [];
  final List<Completer<void>> _pendingCompleters = [];

  void resolveCall(int index) {
    _pendingCompleters[index].complete();
  }

  /// ORIGIN-ADDRESS-R1: dirección que "resuelve" cada llamada a
  /// `getOriginAddress`. Fija por defecto para no obligar a cada test
  /// existente a conocer este flujo nuevo.
  String originAddress;

  /// Dirección de origen incluida en el FareQuote. Puede dejarse vacía
  /// para comprobar que una resolución preemptiva tardía cambia el alto
  /// de la tarjeta aunque la ruta ya esté activa.
  String quoteOriginAddress;

  /// Polyline opcional para activar el mecanismo real de encuadre de ruta.
  String? routePolyline;

  /// Si es `true`, `getOriginAddress` lanza — simula un fallo de red
  /// hacia el endpoint nuevo (nunca un fallo de Google, que el
  /// backend ya absorbe con su propio fallback).
  bool failOriginAddress;

  /// Si es `true`, cada llamada a `getOriginAddress` queda pendiente
  /// (su Future no se resuelve) hasta que el test la libere
  /// explícitamente con [resolveOriginAddressCall] — permite
  /// reproducir taps repetidos mientras la primera llamada real
  /// sigue "en vuelo", sin depender de timing real.
  bool holdOriginAddressRequests;

  int originAddressCallCount = 0;
  final List<List<double>> requestedOriginCoordinates = [];
  final List<Completer<void>> _pendingOriginAddressCompleters = [];

  void resolveOriginAddressCall(int index) {
    _pendingOriginAddressCompleters[index].complete();
  }

  @override
  Future<String> getOriginAddress({
    required double latitude,
    required double longitude,
  }) async {
    originAddressCallCount++;
    requestedOriginCoordinates.add([latitude, longitude]);

    if (holdOriginAddressRequests) {
      final completer = Completer<void>();
      _pendingOriginAddressCompleters.add(completer);
      await completer.future;
    }

    if (failOriginAddress) {
      throw Exception('Fallo simulado de red');
    }

    return originAddress;
  }

  @override
  Future<FareEstimate> estimateRide({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required String destinationAddress,
    String originAddress = 'Ubicación actual del pasajero',
    bool destinationIsManualSelection = false,
  }) async {
    callCount++;

    requestedDestinationAddresses.add(destinationAddress);
    requestedIsManualSelection.add(destinationIsManualSelection);

    if (failFirstCall && callCount == 1) {
      throw Exception('Fallo simulado de red');
    }

    final expired = firstQuoteAlreadyExpired && callCount == 1;

    final ttl = callCount == 1
        ? (firstQuoteTtl ?? const Duration(minutes: 5))
        : const Duration(minutes: 5);

    final overrides = destinationAddressOverrides;
    final resolvedDestinationAddress =
        (overrides != null && overrides.length >= callCount)
        ? overrides[callCount - 1]
        : destinationAddress;

    final estimate = FareEstimate(
      quoteId: 'quote-$callCount',
      quoteStatus: 'ACTIVE',
      distanceMeters: 2500,
      durationSeconds: 480,
      estimatedFare: estimatedFare,
      currency: 'PEN',
      expiresAt: expired
          ? DateTime.now().subtract(const Duration(seconds: 1))
          : DateTime.now().add(ttl),
      originAddress: quoteOriginAddress,
      destinationAddress: resolvedDestinationAddress,
      routePolyline: routePolyline,
    );

    if (!holdRequests) {
      return estimate;
    }

    final completer = Completer<void>();
    _pendingCompleters.add(completer);
    await completer.future;
    return estimate;
  }
}

class _FakePaymentPreferenceRepository extends PaymentPreferenceRepository {
  _FakePaymentPreferenceRepository([this._method = PaymentMethod.cash])
    : super(const FlutterSecureStorage());

  PaymentMethod _method;
  final List<PaymentMethod> writes = [];

  @override
  Future<PaymentMethod> read() async => _method;

  @override
  Future<void> write(PaymentMethod method) async {
    _method = method;
    writes.add(method);
  }
}

class _FakePassengerProfileRepository extends PassengerProfileRepository {
  _FakePassengerProfileRepository({
    Map<String, dynamic>? profileJson,
    this.getError,
  }) : profileJson =
           profileJson ??
           {
             'firstName': 'Ana',
             'lastName': 'Ruiz',
             'photoUrl': null,
             'ratingAverage': '4.80',
             'ratingCount': 12,
           },
       super(Dio());

  /// Centinela: distingue "no se pasó `email`" de "`email: null`".
  static const Object _emailNotPassed = Object();

  Map<String, dynamic>? profileJson;
  Object? getError;

  int getCalls = 0;
  int updateCalls = 0;

  @override
  Future<Map<String, dynamic>?> getMyProfile() async {
    getCalls++;
    final error = getError;
    if (error != null) {
      throw error;
    }
    return profileJson;
  }

  @override
  Future<PassengerProfile> updateMyProfile({
    String? firstName,
    String? lastName,
    Object? email = _emailNotPassed,
  }) async {
    updateCalls++;
    // El backend persiste el cambio: `getMyProfile` posterior (el
    // refresh del menú al reabrir) devuelve el nombre nuevo.
    final json = Map<String, dynamic>.from(profileJson ?? const {});
    if (firstName != null) {
      json['firstName'] = firstName;
    }
    if (lastName != null) {
      json['lastName'] = lastName;
    }
    if (!identical(email, _emailNotPassed)) {
      json['email'] = email;
    }
    profileJson = json;
    return PassengerProfile.fromJson(json);
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio(), const FlutterSecureStorage());

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({this.history = const []}) : super(Dio());

  final List<String> createRideCalls = [];
  final List<String> createRidePaymentMethods = [];

  /// FARE-PANEL-R1 (Etapa 2): si se activa, `createRide` queda en vuelo
  /// hasta `releaseCreateRide()` — para observar `_requestingRide`.
  bool holdCreateRide = false;
  Completer<void>? _createRideGate;

  void releaseCreateRide() {
    _createRideGate?.complete();
    _createRideGate = null;
  }

  /// SUGGESTED-DESTINATIONS-R1: vacío por defecto — ningún test
  /// existente ve sugerencias a menos que las pida explícitamente.
  List<RideHistoryItem> history;
  int getHistoryCallCount = 0;

  @override
  Future<List<RideHistoryItem>> getHistory({
    String status = 'COMPLETED',
    int limit = 50,
  }) async {
    getHistoryCallCount++;
    return history;
  }

  @override
  Future<PassengerRide> createRide({
    required String fareQuoteId,
    required String passengerOfferFare,
    required String paymentMethod,
  }) async {
    createRideCalls.add(passengerOfferFare);
    createRidePaymentMethods.add(paymentMethod);

    if (holdCreateRide) {
      _createRideGate = Completer<void>();
      await _createRideGate!.future;
    }

    return _ride(id: 'ride-created', passengerOfferFare: passengerOfferFare);
  }
}

RideHistoryItem _historyItem({
  required String rideId,
  required String destinationAddress,
  double? destinationLatitude = -6.4877,
  double? destinationLongitude = -76.3599,
  required DateTime requestedAt,
}) {
  return RideHistoryItem(
    rideId: rideId,
    destinationAddress: destinationAddress,
    destinationLatitude: destinationLatitude,
    destinationLongitude: destinationLongitude,
    requestedAt: requestedAt,
  );
}

PassengerRide _ride({required String id, required String passengerOfferFare}) {
  return PassengerRide(
    id: id,
    fareQuoteId: 'quote-1',
    status: 'SEARCHING_DRIVER',
    distanceMeters: 2500,
    estimatedDurationSeconds: 480,
    estimatedFare: '7.00',
    estimatedPassengerFare: '7.00',
    passengerOfferFare: passengerOfferFare,
    agreedFare: null,
    currency: 'PEN',
    paymentMethod: 'CASH',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    requestedAt: DateTime.now(),
    searchExpiresAt: DateTime.now().add(const Duration(minutes: 3)),
  );
}
