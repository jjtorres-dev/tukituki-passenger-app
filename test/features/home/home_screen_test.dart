import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger/features/fare/data/fare_repository.dart';
import 'package:passenger/features/fare/domain/fare_estimate.dart';
import 'package:passenger/features/home/home_screen.dart';
import 'package:passenger/features/places/data/places_repository.dart';
import 'package:passenger/features/places/domain/place_details.dart';
import 'package:passenger/features/places/domain/place_prediction.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';
import 'package:passenger/features/ride/domain/ride_history_item.dart';

void main() {
  late GeolocatorPlatform originalGeolocatorPlatform;

  setUp(() {
    originalGeolocatorPlatform = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalGeolocatorPlatform;
  });

  testWidgets('G4B-R5-1: sin destino, "Selecciona un destino" sigue '
      'funcionando como antes', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    // Aparece dos veces por diseño: la tarjeta de destino y el CTA.
    expect(find.text('Selecciona un destino'), findsNWidgets(2));

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Selecciona un destino'),
      ),
      findsOneWidget,
    );

    // Sin destino, jamás se dispara una cotización.
    expect(fareRepository.callCount, 0);
  });

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
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);

      // Reconstrucciones posteriores (p.ej. al escribir en el campo
      // de oferta) NUNCA disparan una segunda solicitud para la
      // misma selección.
      await tester.enterText(_offerFieldFinder, '8.00');
      await tester.pump();
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
      await tester.enterText(_offerFieldFinder, '8.00');
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

  testWidgets(
    'G4B-R5.1-8: si la cotización automática falla, el CTA dice '
    '"Reintentar" (nunca "Calcular tarifa"/"Calcular nueva tarifa") y '
    'el flujo continúa',
    (tester) async {
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
      expect(find.text('¿Cuánto quieres ofrecer?'), findsNothing);
      expect(find.text('Calcular tarifa'), findsNothing);
      expect(find.text('Calcular nueva tarifa'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);

      final retryButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(retryButton.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(fareRepository.callCount, 2);
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
    },
  );

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

  testWidgets('G4B-R3-3: "¿Cuánto quieres ofrecer?" sí aparece', (
    tester,
  ) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
    expect(
      find.text('Este es el monto que verán los conductores.'),
      findsOneWidget,
    );
  });

  testWidgets('G4B-R3-4: tras cotizar, el input NO se precarga con '
      'estimatedFare', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    expect(_offerController(tester).text, isEmpty);
  });

  testWidgets('G4B-R3-5: el Passenger ingresa S/ 8.00 y el controller '
      'refleja ese valor', (tester) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    await tester.enterText(_offerFieldFinder, '8.00');
    await tester.pump();

    expect(_offerController(tester).text, '8.00');
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
      // El copy de vigencia de la cotización sigue teniendo sentido:
      // ahora es lo único que anticipa que el CTA cambiará a
      // "Calcular nueva tarifa" cuando la cotización expire.
      expect(find.textContaining('Cotización válida hasta'), findsOneWidget);
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
      expect(find.text('Cotización vencida'), findsNothing);
      expect(find.text('Calcular tarifa'), findsNothing);
      expect(find.text('Calcular nueva tarifa'), findsNothing);
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);

      await tester.enterText(_offerFieldFinder, '8.00');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRideCalls, hasLength(1));
      expect(rideRepository.createRideCalls.single, '8.00');
    },
  );

  testWidgets(
    'G4B-R5.1-6/7: si la cotización vence mientras el Passenger ya '
    'escribió su oferta, se renueva sola y preserva ese monto',
    (tester) async {
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

      await tester.enterText(_offerFieldFinder, '8.00');
      await tester.pump();
      expect(_offerController(tester).text, '8.00');

      // Deja vencer la cotización: el Timer interno dispara la
      // renovación solo, sin ningún tap del Passenger.
      await tester.pump(const Duration(seconds: 3));
      await _flushAsync(tester);

      expect(fareRepository.callCount, 2);
      expect(find.text('Calcular tarifa'), findsNothing);
      expect(find.text('Calcular nueva tarifa'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      // La oferta escrita sobrevive intacta a la renovación interna.
      expect(_offerController(tester).text, '8.00');
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
    },
  );

  testWidgets(
    'G4B-R5.1-4/5: cambiar de destino con una request pendiente — la '
    'respuesta vieja NUNCA gana, solo el destino final queda como quote',
    (tester) async {
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
      expect(find.text('¿Cuánto quieres ofrecer?'), findsNothing);

      // Responde B.
      fareRepository.resolveCall(1);
      await _flushAsync(tester);

      // Solo B quedó como quote vigente (segunda solicitud = quote-2).
      expect(state.debugQuoteId, 'quote-2');
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
    },
  );

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

      expect(
        find.text('Calle Yurimaguas 302, Tarapoto 22202, Perú'),
        findsOneWidget,
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
      // se re-geocodifica) — sigue mostrándose intacta.
      expect(
        find.text('Jr. Jiménez Pimentel 210, Tarapoto 22202, Perú'),
        findsOneWidget,
      );
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
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

      // No hace falta limpiar el destino manual antes de este paso:
      // `_selectDestinationViaAutocomplete` ubica el buscador por su
      // Key propia (`destination-search-field`), así que sigue siendo
      // inequívoco aunque la cotización del paso anterior haya
      // agregado su propio campo de texto ("¿Cuánto quieres ofrecer?").
      await _selectDestinationViaAutocomplete(
        tester,
        query: 'Municipalidad',
        prediction: prediction,
      );

      expect(fareRepository.callCount, 2);
      expect(fareRepository.requestedIsManualSelection[1], isFalse);
    },
  );

  testWidgets(
    'G4B-R5.2-4: respuesta obsoleta de A no puede sobrescribir la '
    'dirección real de B',
    (tester) async {
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
    },
  );

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
      expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);

      await tester.enterText(_offerFieldFinder, '8.00');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'G4B-R3-7: input vacío deja deshabilitado el botón y no crea Ride',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(rideRepository.createRideCalls, isEmpty);
    },
  );

  testWidgets('G4B-R3-8: input 0 no habilita el botón de oferta', (
    tester,
  ) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    await tester.enterText(_offerFieldFinder, '0');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('G4B-R3-9: más de 2 decimales no habilita el botón de oferta', (
    tester,
  ) async {
    final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
    final rideRepository = _FakeRideRepository();

    await _pumpHomeScreen(
      tester,
      fareRepository: fareRepository,
      rideRepository: rideRepository,
    );

    await _selectDestinationOnMap(tester);

    await tester.enterText(_offerFieldFinder, '8.123');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'G4B-R3-10: oferta válida envía passengerOfferFare exacto a createRide',
    (tester) async {
      final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
      final rideRepository = _FakeRideRepository();

      await _pumpRoutedHomeScreen(
        tester,
        fareRepository: fareRepository,
        rideRepository: rideRepository,
      );

      await _selectDestinationOnMap(tester);

      await tester.enterText(_offerFieldFinder, '8.00');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await _flushAsync(tester);

      expect(rideRepository.createRideCalls, hasLength(1));
      expect(rideRepository.createRideCalls.single, '8.00');
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

        expect(
          find.text('Calle Rioja 495, Tarapoto'),
          findsOneWidget,
        );
        expect(find.text('Tu ubicación actual'), findsNothing);

        // Sin destino, jamás se dispara una cotización — la dirección
        // resuelta no depende de eso.
        expect(fareRepository.callCount, 0);
      },
    );

    testWidgets(
      'si falla la resolución, no rompe la pantalla y conserva el '
      'placeholder existente',
      (tester) async {
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
        expect(find.text('Tu ubicación actual'), findsOneWidget);

        // La pantalla sigue funcional: el CTA de destino sigue ahí.
        expect(find.text('Selecciona un destino'), findsNWidgets(2));
      },
    );

    testWidgets(
      'la dirección real de la cotización siempre gana sobre la '
      'resuelta preemptivamente',
      (tester) async {
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

        expect(
          find.text('Preemptiva: Jr. Lima 250'),
          findsOneWidget,
        );

        await _selectDestinationOnMap(tester);

        // La cotización real (fake fija su propio originAddress) pisa
        // la dirección preemptiva, sin ambigüedad de prioridad.
        expect(find.text('Preemptiva: Jr. Lima 250'), findsNothing);
        expect(fareRepository.callCount, 1);
      },
    );

    testWidgets(
      'dentro del umbral de cacheo por distancia, no vuelve a llamar '
      'al backend',
      (tester) async {
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
      },
    );

    testWidgets(
      'fuera del umbral de cacheo por distancia, resuelve una '
      'dirección nueva',
      (tester) async {
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
        expect(
          fareRepository.requestedOriginCoordinates[1],
          [-6.4977, -76.3599],
        );
      },
    );

    testWidgets(
      'varios taps rápidos sin moverse producen una sola llamada al '
      'repositorio, no una por tap',
      (tester) async {
        final fareRepository = _FakeFareRepository(
          estimatedFare: '7.00',
          originAddress: 'Calle Rioja 495, Tarapoto',
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

        // Al responder la única llamada real, se refleja con
        // normalidad.
        fareRepository.resolveOriginAddressCall(0);
        await _flushAsync(tester);

        expect(
          find.text('Calle Rioja 495, Tarapoto'),
          findsOneWidget,
        );

        // Un tap posterior, ya con la dirección resuelta y sin
        // movimiento, tampoco dispara una llamada nueva.
        await _tapCenterOnMyLocation(tester);

        expect(fareRepository.originAddressCallCount, 1);
      },
    );
  });

  group('SUGGESTED-DESTINATIONS-R1', () {
    testWidgets(
      'sin historial, no se muestra ninguna sugerencia',
      (tester) async {
        final fareRepository = _FakeFareRepository(estimatedFare: '7.00');
        final rideRepository = _FakeRideRepository();

        await _pumpHomeScreen(
          tester,
          fareRepository: fareRepository,
          rideRepository: rideRepository,
        );

        expect(rideRepository.getHistoryCallCount, 1);
        expect(find.byIcon(Icons.history), findsNothing);
      },
    );

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

    testWidgets(
      'toca una sugerencia: fija destino y dispara la cotización sin '
      'autocomplete ni details',
      (tester) async {
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
        expect(find.text('¿Cuánto quieres ofrecer?'), findsOneWidget);
      },
    );

    testWidgets(
      'la sugerencia queda deshabilitada mientras no hay GPS',
      (tester) async {
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
      },
    );

    testWidgets(
      'una vez elegido un destino, deja de mostrarse la sección de '
      'sugerencias',
      (tester) async {
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

        expect(find.byIcon(Icons.history), findsNothing);
      },
    );
  });
}

final _offerFieldFinder = find.byKey(const ValueKey('passenger-offer-field'));

TextEditingController _offerController(WidgetTester tester) {
  return tester.widget<TextField>(_offerFieldFinder).controller!;
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

/// G4B-R5.2: escribe en el buscador, deja pasar el debounce real
/// (450ms), flushea `autocomplete()`, y toca la primera predicción —
/// mismo camino real que usaría el Passenger.
final _destinationSearchFieldFinder = find.byKey(
  const ValueKey('destination-search-field'),
);

Future<void> _selectDestinationViaAutocomplete(
  WidgetTester tester, {
  required String query,
  required PlacePrediction prediction,
}) async {
  await tester.enterText(_destinationSearchFieldFinder, query);
  await tester.pump(const Duration(milliseconds: 500));
  await _flushAsync(tester);

  await tester.tap(find.text(prediction.primaryText));
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
  List<Position>? locationSequence,
  _FakeGeolocatorPlatform? geolocatorPlatform,
}) async {
  GeolocatorPlatform.instance =
      geolocatorPlatform ??
      _FakeGeolocatorPlatform(
        positions: locationSequence,
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fareRepositoryProvider.overrideWithValue(fareRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
        if (placesRepository != null)
          placesRepositoryProvider.overrideWithValue(placesRepository),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );

  await _flushAsync(tester);
}

Future<void> _pumpRoutedHomeScreen(
  WidgetTester tester, {
  required FareRepository fareRepository,
  required RideRepository rideRepository,
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
  _FakeGeolocatorPlatform({this.positions, this.hold = false});

  final List<Position>? positions;
  int _callIndex = 0;

  /// SUGGESTED-DESTINATIONS-R1: si es `true`, `getCurrentPosition`
  /// queda pendiente hasta [releaseHold] — permite reproducir "el
  /// pasajero todavía no tiene GPS" sin depender de timing real.
  final bool hold;
  final Completer<void> _holdCompleter = Completer<void>();

  void releaseHold() {
    if (!_holdCompleter.isCompleted) {
      _holdCompleter.complete();
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
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

class _FakeFareRepository extends FareRepository {
  _FakeFareRepository({
    required this.estimatedFare,
    this.firstQuoteAlreadyExpired = false,
    this.firstQuoteTtl,
    this.failFirstCall = false,
    this.holdRequests = false,
    this.destinationAddressOverrides,
    this.originAddress = 'Calle Rioja 495, Tarapoto',
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
      originAddress: 'Tu ubicación actual',
      destinationAddress: resolvedDestinationAddress,
      routePolyline: null,
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

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({this.history = const []}) : super(Dio());

  final List<String> createRideCalls = [];

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
  }) async {
    createRideCalls.add(passengerOfferFare);

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
