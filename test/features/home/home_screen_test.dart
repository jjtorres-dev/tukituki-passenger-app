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

/// G4B-R5.2: escribe en el buscador, deja pasar el debounce real
/// (450ms), flushea `autocomplete()`, y toca la primera predicción —
/// mismo camino real que usaría el Passenger.
Future<void> _selectDestinationViaAutocomplete(
  WidgetTester tester, {
  required String query,
  required PlacePrediction prediction,
}) async {
  await tester.enterText(find.byType(TextField), query);
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
}) async {
  GeolocatorPlatform.instance = _FakeGeolocatorPlatform();

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

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return Position(
      latitude: -6.4877,
      longitude: -76.3599,
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
}

class _FakeFareRepository extends FareRepository {
  _FakeFareRepository({
    required this.estimatedFare,
    this.firstQuoteAlreadyExpired = false,
    this.firstQuoteTtl,
    this.failFirstCall = false,
    this.holdRequests = false,
    this.destinationAddressOverrides,
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
  final List<Completer<void>> _pendingCompleters = [];

  void resolveCall(int index) {
    _pendingCompleters[index].complete();
  }

  @override
  Future<FareEstimate> estimateRide({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required String destinationAddress,
    String originAddress = 'Ubicación actual del pasajero',
  }) async {
    callCount++;

    requestedDestinationAddresses.add(destinationAddress);

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
  _FakeRideRepository() : super(Dio());

  final List<String> createRideCalls = [];

  @override
  Future<PassengerRide> createRide({
    required String fareQuoteId,
    required String passengerOfferFare,
  }) async {
    createRideCalls.add(passengerOfferFare);

    return _ride(id: 'ride-created', passengerOfferFare: passengerOfferFare);
  }
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
