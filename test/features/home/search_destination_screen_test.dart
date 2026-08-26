import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger/features/home/domain/search_destination_result.dart';
import 'package:passenger/features/home/search_destination_screen.dart';
import 'package:passenger/features/places/data/places_repository.dart';
import 'package:passenger/features/places/domain/place_details.dart';
import 'package:passenger/features/places/domain/place_prediction.dart';

void main() {
  const originAddress = 'Jr. Lima 123, Tarapoto';
  const originCoordinates = LatLng(-6.4877, -76.3599);

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

  final destinationFieldFinder = find.byKey(
    const ValueKey('search-destination-field'),
  );

  /// Mutado dentro del `onPressed` del botón host cuando
  /// `Navigator.push` termina (al hacer `pop`). Un simple `Future`
  /// devuelto por `pumpAndPush` no sirve acá porque ese `Future` recién
  /// se completa cuando la pantalla hace `pop` -- mucho después de que
  /// `pumpAndPush` ya volvió (que solo espera a que la navegación
  /// *empiece*). Los tests que necesitan el resultado lo leen de acá
  /// después de interactuar con la pantalla empujada.
  final resultHolder = <SearchDestinationResult?>[];

  Future<void> pumpAndPush(
    WidgetTester tester, {
    required PlacesRepository placesRepository,
  }) async {
    resultHolder.clear();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          placesRepositoryProvider.overrideWithValue(placesRepository),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push<SearchDestinationResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchDestinationScreen(
                        originAddress: originAddress,
                        originCoordinates: originCoordinates,
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
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> flushAsync(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  testWidgets(
    'muestra el origen de solo lectura y el campo de destino con foco',
    (tester) async {
      await pumpAndPush(
        tester,
        placesRepository: _FakePlacesRepository(
          predictions: const [],
          details: details,
        ),
      );

      expect(find.text(originAddress), findsOneWidget);
      expect(find.text('Buscar destino'), findsOneWidget);

      final focusNode = tester
          .widget<TextField>(
            find.descendant(
              of: destinationFieldFinder,
              matching: find.byType(TextField),
            ),
          )
          .focusNode;
      expect(focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('escribir menos de 2 caracteres no busca', (tester) async {
    final placesRepository = _FakePlacesRepository(
      predictions: const [prediction],
      details: details,
    );

    await pumpAndPush(tester, placesRepository: placesRepository);

    await tester.enterText(destinationFieldFinder, 'M');
    await tester.pump(const Duration(milliseconds: 500));
    await flushAsync(tester);

    expect(placesRepository.autocompleteCallCount, 0);
    expect(find.text('Municipalidad de Tarapoto'), findsNothing);
  });

  testWidgets(
    'escribir 2+ caracteres dispara autocomplete tras el debounce y '
    'muestra las predicciones',
    (tester) async {
      final placesRepository = _FakePlacesRepository(
        predictions: const [prediction],
        details: details,
      );

      await pumpAndPush(tester, placesRepository: placesRepository);

      await tester.enterText(destinationFieldFinder, 'Municipalidad');
      await tester.pump(const Duration(milliseconds: 500));
      await flushAsync(tester);

      expect(placesRepository.autocompleteCallCount, 1);
      expect(find.text('Municipalidad de Tarapoto'), findsOneWidget);
      expect(find.text('Jr. Jiménez Pimentel 210'), findsOneWidget);
    },
  );

  testWidgets('sin resultados muestra el mensaje de "no encontramos"', (
    tester,
  ) async {
    final placesRepository = _FakePlacesRepository(
      predictions: const [],
      details: details,
    );

    await pumpAndPush(tester, placesRepository: placesRepository);

    await tester.enterText(destinationFieldFinder, 'xyzxyz');
    await tester.pump(const Duration(milliseconds: 500));
    await flushAsync(tester);

    expect(
      find.text('No encontramos destinos con ese nombre.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tocar una predicción devuelve el resultado y hace pop',
    (tester) async {
      final placesRepository = _FakePlacesRepository(
        predictions: const [prediction],
        details: details,
      );

      await pumpAndPush(tester, placesRepository: placesRepository);

      await tester.enterText(destinationFieldFinder, 'Municipalidad');
      await tester.pump(const Duration(milliseconds: 500));
      await flushAsync(tester);

      await tester.tap(find.text('Municipalidad de Tarapoto'));
      await tester.pumpAndSettle();

      expect(placesRepository.getDetailsCallCount, 1);
      expect(find.byType(SearchDestinationScreen), findsNothing);

      final result = resultHolder.single;
      expect(result, isNotNull);
      expect(result!.destination, const LatLng(-6.4812, -76.3655));
      expect(result.name, 'Municipalidad de Tarapoto');
      expect(
        result.address,
        'Jr. Jiménez Pimentel 210, Tarapoto 22202, Perú',
      );
    },
  );

  testWidgets('el botón de volver hace pop sin resultado', (tester) async {
    await pumpAndPush(
      tester,
      placesRepository: _FakePlacesRepository(
        predictions: const [],
        details: details,
      ),
    );

    expect(find.byType(SearchDestinationScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchDestinationScreen), findsNothing);
    expect(resultHolder.single, isNull);
  });

  testWidgets('el botón de limpiar borra el texto y las predicciones', (
    tester,
  ) async {
    final placesRepository = _FakePlacesRepository(
      predictions: const [prediction],
      details: details,
    );

    await pumpAndPush(tester, placesRepository: placesRepository);

    await tester.enterText(destinationFieldFinder, 'Municipalidad');
    await tester.pump(const Duration(milliseconds: 500));
    await flushAsync(tester);

    expect(find.text('Municipalidad de Tarapoto'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Municipalidad de Tarapoto'), findsNothing);

    final controllerText = tester
        .widget<TextField>(
          find.descendant(
            of: destinationFieldFinder,
            matching: find.byType(TextField),
          ),
        )
        .controller
        ?.text;
    expect(controllerText, isEmpty);
  });
}

class _FakePlacesRepository extends PlacesRepository {
  _FakePlacesRepository({required this.predictions, required this.details})
    : super(Dio());

  final List<PlacePrediction> predictions;
  final PlaceDetails details;

  int autocompleteCallCount = 0;
  int getDetailsCallCount = 0;

  @override
  Future<List<PlacePrediction>> autocomplete({
    required String input,
    required double latitude,
    required double longitude,
    required String sessionToken,
  }) async {
    autocompleteCallCount++;
    return predictions;
  }

  @override
  Future<PlaceDetails> getDetails({
    required String placeId,
    required String sessionToken,
  }) async {
    getDetailsCallCount++;
    return details;
  }
}
