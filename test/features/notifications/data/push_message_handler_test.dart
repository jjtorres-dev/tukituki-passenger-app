import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:passenger/features/notifications/data/local_notifications_service.dart';
import 'package:passenger/features/notifications/data/push_message_handler.dart';

class _ShowCall {
  _ShowCall(this.id, this.title, this.body);

  final int id;
  final String title;
  final String body;
}

class _FakeLocalNotifications implements LocalNotifications {
  final List<_ShowCall> calls = [];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    calls.add(_ShowCall(id, title, body));
  }
}

RemoteMessage _message({
  Map<String, dynamic> data = const {},
  String? title,
  String? body,
  bool withNotification = true,
}) {
  return RemoteMessage(
    data: data,
    notification: withNotification
        ? RemoteNotification(title: title, body: body)
        : null,
  );
}

void main() {
  late StreamController<RemoteMessage> messages;
  late _FakeLocalNotifications localNotifications;

  PushMessageHandler build() {
    final handler = PushMessageHandler(messages.stream, localNotifications);
    addTearDown(handler.dispose);
    return handler;
  }

  setUp(() {
    messages = StreamController<RemoteMessage>.broadcast();
    localNotifications = _FakeLocalNotifications();
    addTearDown(messages.close);
  });

  test(
    'DRIVER_ARRIVED con notification real → show() una vez con ese título '
    'y cuerpo, id 1',
    () async {
      build().start();

      messages.add(
        _message(
          data: {
            'route': 'ride-detail',
            'rideId': 'r1',
            'eventType': 'DRIVER_ARRIVED',
          },
          title: 'Tu conductor llegó',
          body: 'Revisa el PIN antes de abordar.',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 1);
      expect(localNotifications.calls.single.title, 'Tu conductor llegó');
      expect(
        localNotifications.calls.single.body,
        'Revisa el PIN antes de abordar.',
      );
    },
  );

  test(
    'DRIVER_ARRIVED sin notification → show() con los textos de fallback',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'},
          withNotification: false,
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 1);
      expect(localNotifications.calls.single.title, 'Tu conductor llegó');
      expect(
        localNotifications.calls.single.body,
        'El conductor está cerca del origen. Revisa el PIN antes de abordar.',
      );
    },
  );

  test(
    'DRIVER_ARRIVED con notification pero title/body nulos → fallback',
    () async {
      build().start();

      messages.add(
        _message(data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'}),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.title, 'Tu conductor llegó');
      expect(
        localNotifications.calls.single.body,
        'El conductor está cerca del origen. Revisa el PIN antes de abordar.',
      );
    },
  );

  test(
    'RIDE_COMPLETED con notification real → show() una vez con ese título '
    'y cuerpo, id 2',
    () async {
      build().start();

      messages.add(
        _message(
          data: {
            'route': 'ride-receipt',
            'rideId': 'r1',
            'status': 'COMPLETED',
          },
          title: 'Viaje completado',
          body: 'Tarifa: S/ 12.50',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 2);
      expect(localNotifications.calls.single.title, 'Viaje completado');
      expect(localNotifications.calls.single.body, 'Tarifa: S/ 12.50');
    },
  );

  test(
    'RIDE_COMPLETED sin notification → show() con los textos de fallback',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-receipt', 'status': 'COMPLETED'},
          withNotification: false,
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 2);
      expect(localNotifications.calls.single.title, 'Viaje completado');
      expect(
        localNotifications.calls.single.body,
        'Tu viaje terminó. Revisa el detalle de la tarifa.',
      );
    },
  );

  test('DRIVER_ARRIVING → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(
      _message(
        data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVING'},
        title: 'Tu conductor está en camino',
        body: 'x',
      ),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('RATING_REQUEST → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(
      _message(
        data: {'route': 'ride-rating', 'rideId': 'r1'},
        title: 'Califica tu viaje',
        body: 'x',
      ),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  for (final eventType in const [
    'RIDE_ASSIGNED',
    'RIDE_STARTED',
    'RIDE_CANCELLED',
    'RIDE_EXPIRED',
  ]) {
    test('$eventType (route ride-detail) → show() NO llamado', () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-detail', 'eventType': eventType},
          title: 'x',
          body: 'y',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, isEmpty);
    });
  }

  test('route y eventType ausentes → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(_message(data: {'rideId': 'r1'}, title: 'x', body: 'y'));
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('data vacío → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(_message(title: 'x', body: 'y'));
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test(
    'RIDE_COMPLETED seguido de RATING_REQUEST → un solo show() (el completed)',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-receipt', 'status': 'COMPLETED'},
          title: 'Viaje completado',
          body: 'Tarifa: S/ 9.00',
        ),
      );
      messages.add(
        _message(data: {'route': 'ride-rating', 'rideId': 'r1'}, title: 'x'),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 2);
      expect(localNotifications.calls.single.title, 'Viaje completado');
    },
  );

  test(
    'RATING_REQUEST seguido de RIDE_COMPLETED → un solo show() (el completed)',
    () async {
      build().start();

      messages.add(
        _message(data: {'route': 'ride-rating', 'rideId': 'r1'}, title: 'x'),
      );
      messages.add(
        _message(
          data: {'route': 'ride-receipt', 'status': 'COMPLETED'},
          title: 'Viaje completado',
          body: 'Tarifa: S/ 9.00',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 2);
      expect(localNotifications.calls.single.title, 'Viaje completado');
    },
  );

  test(
    'DRIVER_ARRIVED seguido de RIDE_COMPLETED → 2 show() con IDs distintos',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'},
          title: 'Tu conductor llegó',
          body: 'a',
        ),
      );
      messages.add(
        _message(
          data: {'route': 'ride-receipt', 'status': 'COMPLETED'},
          title: 'Viaje completado',
          body: 'b',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(2));
      expect(localNotifications.calls[0].id, 1);
      expect(localNotifications.calls[1].id, 2);
      expect(localNotifications.calls[0].id != localNotifications.calls[1].id,
          isTrue);
    },
  );

  test(
    'precedencia defensiva: eventType DRIVER_ARRIVED gana sobre '
    'route ride-receipt',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-receipt', 'eventType': 'DRIVER_ARRIVED'},
          title: 'T',
          body: 'B',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.id, 1);
    },
  );

  test('dos start() seguidos → una sola suscripción (show() una vez)', () async {
    final handler = build();

    handler.start();
    handler.start();

    messages.add(
      _message(
        data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'},
        title: 'A',
        body: 'B',
      ),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, hasLength(1));
  });

  test(
    'dispose() cancela la suscripción: un mensaje posterior no llama show()',
    () async {
      final handler = build();
      handler.start();

      handler.dispose();

      messages.add(
        _message(
          data: {'route': 'ride-detail', 'eventType': 'DRIVER_ARRIVED'},
          title: 'A',
          body: 'B',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, isEmpty);
    },
  );

  test('mensaje malformado no crashea el handler', () async {
    build().start();

    messages.add(_message(data: {'foo': 'bar'}, withNotification: false));
    messages.add(_message(withNotification: false));
    await pumpEventQueue();

    // Sigue vivo: un evento válido posterior se procesa igual.
    messages.add(
      _message(
        data: {'route': 'ride-receipt', 'status': 'COMPLETED'},
        title: 'ok',
        body: 'sigue vivo',
      ),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, hasLength(1));
    expect(localNotifications.calls.single.body, 'sigue vivo');
  });
}
