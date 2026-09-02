import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:passenger/features/notifications/data/local_notifications_service.dart';
import 'package:passenger/features/notifications/data/push_message_handler.dart';

RemoteMessage _message({
  Map<String, dynamic> data = const {},
  String? title,
  String? body,
  bool withNotification = false,
}) {
  return RemoteMessage(
    data: data,
    notification: withNotification
        ? RemoteNotification(title: title, body: body)
        : null,
  );
}

void main() {
  group('resolveRideUpdateKind (extraído a top-level en Etapa 3)', () {
    test('eventType DRIVER_ARRIVED → driverArrived', () {
      expect(
        resolveRideUpdateKind(
          _message(
            data: {'screen': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'},
          ),
        ),
        RideUpdateKind.driverArrived,
      );
    });

    test('screen ride-receipt → rideCompleted', () {
      expect(
        resolveRideUpdateKind(
          _message(data: {'screen': 'ride-receipt', 'rideId': 'r1'}),
        ),
        RideUpdateKind.rideCompleted,
      );
    });

    test('screen ride-rating → null', () {
      expect(
        resolveRideUpdateKind(
          _message(data: {'screen': 'ride-rating', 'rideId': 'r1'}),
        ),
        isNull,
      );
    });

    test('screen ride-detail con otro eventType → null', () {
      expect(
        resolveRideUpdateKind(
          _message(
            data: {'screen': 'ride-detail', 'eventType': 'RIDE_STARTED'},
          ),
        ),
        isNull,
      );
    });

    test('data vacío → null', () {
      expect(resolveRideUpdateKind(_message()), isNull);
    });

    test('eventType DRIVER_ARRIVED gana sobre screen ride-receipt', () {
      expect(
        resolveRideUpdateKind(
          _message(
            data: {'screen': 'ride-receipt', 'eventType': 'DRIVER_ARRIVED'},
          ),
        ),
        RideUpdateKind.driverArrived,
      );
    });
  });

  group('coldStartReceiptRouteFor', () {
    test('initialMessage null → null', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: null,
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });

    test(
      'RIDE_COMPLETED sin viaje activo más nuevo → ruta del recibo',
      () {
        expect(
          coldStartReceiptRouteFor(
            initialMessage: _message(
              data: {
                'screen': 'ride-receipt',
                'rideId': 'r9',
                'status': 'COMPLETED',
              },
            ),
            hasNewerActiveRide: false,
          ),
          '/ride/r9/receipt',
        );
      },
    );

    test('RIDE_COMPLETED con viaje activo más nuevo → null (precedencia)', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {'screen': 'ride-receipt', 'rideId': 'r9'},
          ),
          hasNewerActiveRide: true,
        ),
        isNull,
      );
    });

    test('RIDE_COMPLETED sin rideId → null', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(data: {'screen': 'ride-receipt'}),
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });

    test('RIDE_COMPLETED con rideId en blanco → null', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {'screen': 'ride-receipt', 'rideId': '   '},
          ),
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });

    test('RIDE_COMPLETED con rideId con espacios alrededor → ruta recortada', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {'screen': 'ride-receipt', 'rideId': '  r9  '},
          ),
          hasNewerActiveRide: false,
        ),
        '/ride/r9/receipt',
      );
    });

    test('DRIVER_ARRIVED → null (lo cubre el resolver de sesión)', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {
              'screen': 'ride-detail',
              'rideId': 'r9',
              'eventType': 'DRIVER_ARRIVED',
            },
          ),
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });

    test('RATING_REQUEST → null', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {'screen': 'ride-rating', 'rideId': 'r9'},
          ),
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });

    test('ride-detail con otro eventType → null', () {
      expect(
        coldStartReceiptRouteFor(
          initialMessage: _message(
            data: {
              'screen': 'ride-detail',
              'rideId': 'r9',
              'eventType': 'RIDE_STARTED',
            },
          ),
          hasNewerActiveRide: false,
        ),
        isNull,
      );
    });
  });
}
