import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/home/domain/suggested_destinations.dart';
import 'package:passenger/features/ride/domain/ride_history_item.dart';

RideHistoryItem _item({
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

void main() {
  final now = DateTime(2026, 8, 24, 12);

  group('resolveSuggestedDestinations', () {
    test('historial vacío no produce sugerencias', () {
      expect(resolveSuggestedDestinations(const []), isEmpty);
    });

    test('ordena por frecuencia, no por recencia', () {
      final history = [
        // Visitado una sola vez, pero es el más reciente.
        _item(rideId: 'r1', destinationAddress: 'Plaza', requestedAt: now),
        // Visitado 3 veces, pero más antiguo — debe ganar igual.
        _item(
          rideId: 'r2',
          destinationAddress: 'UPEU',
          requestedAt: now.subtract(const Duration(days: 5)),
        ),
        _item(
          rideId: 'r3',
          destinationAddress: 'UPEU',
          requestedAt: now.subtract(const Duration(days: 6)),
        ),
        _item(
          rideId: 'r4',
          destinationAddress: 'UPEU',
          requestedAt: now.subtract(const Duration(days: 7)),
        ),
      ];

      final result = resolveSuggestedDestinations(history);

      expect(result.first.destinationAddress, 'UPEU');
    });

    test('no funciona con el orden de entrada: reordena por requestedAt '
        'aunque el historial venga desordenado', () {
      final history = [
        _item(
          rideId: 'r1',
          destinationAddress: 'UPEU',
          requestedAt: now.subtract(const Duration(days: 3)),
        ),
        _item(rideId: 'r2', destinationAddress: 'UPEU', requestedAt: now),
        _item(
          rideId: 'r3',
          destinationAddress: 'UPEU',
          requestedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      final result = resolveSuggestedDestinations(history);

      expect(result, hasLength(1));
      // El representante elegido para "UPEU" es el más reciente (r2),
      // aunque haya llegado en medio de la lista.
      expect(result.first.rideId, 'r2');
    });

    test('deduplica por dirección normalizada (trim + minúsculas)', () {
      final history = [
        _item(rideId: 'r1', destinationAddress: 'UPEU', requestedAt: now),
        _item(
          rideId: 'r2',
          destinationAddress: '  upeu  ',
          requestedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      final result = resolveSuggestedDestinations(history);

      expect(result, hasLength(1));
    });

    test('excluye ítems sin coordenadas de destino', () {
      final history = [
        _item(
          rideId: 'r1',
          destinationAddress: 'Sin coordenadas',
          destinationLatitude: null,
          destinationLongitude: null,
          requestedAt: now,
        ),
        _item(
          rideId: 'r2',
          destinationAddress: 'Con coordenadas',
          requestedAt: now,
        ),
      ];

      final result = resolveSuggestedDestinations(history);

      expect(result, hasLength(1));
      expect(result.first.destinationAddress, 'Con coordenadas');
    });

    test(
      'excluye los placeholders de fallback del Backend '
      '(no son direcciones reales)',
      () {
        final history = [
          _item(
            rideId: 'r1',
            destinationAddress: 'Destino seleccionado',
            requestedAt: now,
          ),
          _item(
            rideId: 'r2',
            destinationAddress: 'Destino seleccionado en el mapa',
            requestedAt: now,
          ),
          _item(
            rideId: 'r3',
            destinationAddress: 'UPEU',
            requestedAt: now,
          ),
        ];

        final result = resolveSuggestedDestinations(history);

        expect(result, hasLength(1));
        expect(result.first.destinationAddress, 'UPEU');
      },
    );

    test('excluye direcciones vacías o solo espacios', () {
      final history = [
        _item(rideId: 'r1', destinationAddress: '   ', requestedAt: now),
        _item(rideId: 'r2', destinationAddress: 'UPEU', requestedAt: now),
      ];

      final result = resolveSuggestedDestinations(history);

      expect(result, hasLength(1));
    });

    test(
      'nunca devuelve más de suggestedDestinationsCount, aunque haya más '
      'destinos distintos con la misma frecuencia',
      () {
        final history = [
          _item(rideId: 'r1', destinationAddress: 'A', requestedAt: now),
          _item(rideId: 'r2', destinationAddress: 'B', requestedAt: now),
          _item(rideId: 'r3', destinationAddress: 'C', requestedAt: now),
        ];

        final result = resolveSuggestedDestinations(history);

        expect(result.length, suggestedDestinationsCount);
      },
    );
  });
}
