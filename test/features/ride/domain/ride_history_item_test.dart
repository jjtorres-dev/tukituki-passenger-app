import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/domain/ride_history_item.dart';

void main() {
  group('RideHistoryItem.fromJson', () {
    test('parsea un ítem completo con coordenadas válidas', () {
      final item = RideHistoryItem.fromJson({
        'rideId': 'ride-1',
        'destinationAddress': 'Universidad Peruana Unión, Tarapoto',
        'destinationLatitude': -6.4877,
        'destinationLongitude': -76.3599,
        'requestedAt': '2026-08-20T15:00:00.000Z',
      });

      expect(item.rideId, 'ride-1');
      expect(item.destinationAddress, 'Universidad Peruana Unión, Tarapoto');
      expect(item.destinationLatitude, -6.4877);
      expect(item.destinationLongitude, -76.3599);
      expect(item.requestedAt, DateTime.parse('2026-08-20T15:00:00.000Z'));
    });

    test('destinationLatitude/destinationLongitude null se conservan null', () {
      final item = RideHistoryItem.fromJson({
        'rideId': 'ride-1',
        'destinationAddress': 'Destino seleccionado en el mapa',
        'destinationLatitude': null,
        'destinationLongitude': null,
        'requestedAt': '2026-08-20T15:00:00.000Z',
      });

      expect(item.destinationLatitude, isNull);
      expect(item.destinationLongitude, isNull);
    });

    test('coordenadas fuera de rango se descartan (quedan null)', () {
      final item = RideHistoryItem.fromJson({
        'rideId': 'ride-1',
        'destinationAddress': 'Destino inválido',
        'destinationLatitude': 200,
        'destinationLongitude': -76.3599,
        'requestedAt': '2026-08-20T15:00:00.000Z',
      });

      expect(item.destinationLatitude, isNull);
      // longitude sí es válida y no depende de latitude.
      expect(item.destinationLongitude, -76.3599);
    });

    test('campos faltantes usan defaults seguros, sin lanzar', () {
      final item = RideHistoryItem.fromJson(const {});

      expect(item.rideId, '');
      expect(item.destinationAddress, '');
      expect(item.destinationLatitude, isNull);
      expect(item.destinationLongitude, isNull);
      expect(item.requestedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
