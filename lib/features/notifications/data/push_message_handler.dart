import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_notifications_service.dart';

final pushMessageHandlerProvider = Provider<PushMessageHandler>((ref) {
  final handler = PushMessageHandler(
    _firebaseOnMessage(),
    ref.watch(localNotificationsProvider),
  );

  ref.onDispose(handler.dispose);

  return handler;
});

/// Acceso best-effort a `FirebaseMessaging.onMessage`. Si Firebase no
/// inicializó (sin conexión al arrancar, Play Services ausente, etc.),
/// tocar el stream no debe romper la app: se devuelve un stream vacío
/// y el pasajero sigue viendo el estado del viaje por el polling del
/// flujo de seguimiento.
Stream<RemoteMessage> _firebaseOnMessage() {
  try {
    return FirebaseMessaging.onMessage;
  } catch (error) {
    debugPrint(
      'PASSENGER PUSH - FirebaseMessaging.onMessage no disponible: $error',
    );
    return const Stream<RemoteMessage>.empty();
  }
}

/// Filtro compartido de eventos push del viaje: `data.eventType ==
/// 'DRIVER_ARRIVED'` O `data.screen == 'ride-receipt'` (RIDE_COMPLETED).
/// `screen` por sí solo NO sirve de filtro (es genérico, compartido por
/// varios eventos). Se chequea `eventType` primero por si un mensaje
/// trajera ambos campos.
///
/// El campo se llama `screen` (no `route`): el backend lo renombró para
/// eliminar la colisión con `EXTRA_INITIAL_ROUTE` del embedding de
/// Flutter en Android, que al abrir la app desde una notificación con
/// el proceso terminado inyectaba ese valor como `initialRoute` y
/// go_router no podía resolverlo ("no routes for location").
///
/// Lo usan `PushMessageHandler` (Etapa 2, aviso en foreground) y
/// `coldStartReceiptRouteFor` (Etapa 3, tap con la app terminada).
RideUpdateKind? resolveRideUpdateKind(RemoteMessage message) {
  final data = message.data;

  if (data['eventType'] == 'DRIVER_ARRIVED') {
    return RideUpdateKind.driverArrived;
  }

  if (data['screen'] == 'ride-receipt') {
    return RideUpdateKind.rideCompleted;
  }

  return null;
}

/// `PASSENGER-PUSH-R1` (Etapa 2). Hermana de
/// `PushRegistrationCoordinator` (no la extiende ni la modifica):
/// materializa en la barra de estado las `RemoteMessage` que llegan
/// con la app en foreground —el único caso donde FCM no dibuja nada
/// por su cuenta.
///
/// Solo reacciona a dos eventos: `DRIVER_ARRIVED` (por
/// `data.eventType`) y `RIDE_COMPLETED` (por `data.screen`). Cualquier
/// otro mensaje se recibe y se ignora con `debugPrint` — en particular
/// `DRIVER_ARRIVING` y `RATING_REQUEST`, decisión de producto de esta
/// etapa (un solo aviso por fin de viaje).
///
/// Todo es best-effort: un fallo nunca lanza ni interrumpe el flujo
/// normal; solo `debugPrint`. Sigue el patrón "best-effort" del repo
/// (registro push de Etapa 1, refresh de sesión).
///
/// Etapa 2 NO maneja el tap de la notificación (solo trae la app al
/// frente), ni `onMessageOpenedApp` / `onBackgroundMessage` /
/// `getInitialMessage`: eso es Etapa 3.
class PushMessageHandler {
  PushMessageHandler(this._messages, this._localNotifications);

  final Stream<RemoteMessage> _messages;
  final LocalNotifications _localNotifications;

  /// Guard de suscripción única (mismo patrón que `_tokenRefreshWired`
  /// en Etapa 1): aunque `start()` se llame en cada arranque, solo se
  /// suscribe una vez.
  bool _started = false;
  StreamSubscription<RemoteMessage>? _subscription;

  /// Suscripción síncrona al stream de mensajes en foreground.
  /// Idempotente. Best-effort: si suscribirse fallara, se traga el
  /// error.
  void start() {
    if (_started) {
      return;
    }

    _started = true;

    try {
      _subscription = _messages.listen(_handleMessage);
    } catch (error) {
      debugPrint(
        'PASSENGER PUSH - PushMessageHandler no pudo suscribirse a onMessage: '
        '$error',
      );
    }
  }

  void _handleMessage(RemoteMessage message) {
    try {
      final kind = resolveRideUpdateKind(message);

      if (kind == null) {
        final screen = message.data['screen'];
        final eventType = message.data['eventType'];
        debugPrint(
          'PASSENGER PUSH - mensaje ignorado (screen=$screen, '
          'eventType=$eventType)',
        );
        return;
      }

      final title = message.notification?.title ?? kind.fallbackTitle;
      final body = message.notification?.body ?? kind.fallbackBody;

      unawaited(
        _localNotifications.show(
          id: kind.notificationId,
          title: title,
          body: body,
        ),
      );
    } catch (error) {
      debugPrint('PASSENGER PUSH - error procesando mensaje push: $error');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// `PASSENGER-PUSH-R1` (Etapa 3). `main()` lo sobreescribe con el
/// `RemoteMessage` de cold start (o `null`) leído una sola vez con
/// `FirebaseMessaging.instance.getInitialMessage()`. El default `null`
/// es seguro y esperado: en tests y en un arranque normal (sin tap de
/// notificación con la app terminada) no hay desvío de navegación, y
/// `SplashScreen._checkSession` sigue su resolución de sesión habitual.
final initialPushMessageProvider = Provider<RemoteMessage?>((ref) => null);

/// `PASSENGER-PUSH-R1` (Etapa 3). Pura: sin `BuildContext`, sin
/// Firebase. Decide si un `getInitialMessage()` de cold start debe
/// desviar la navegación al recibo del viaje.
///
/// Devuelve la ruta del recibo SOLO si el mensaje inicial es
/// `RIDE_COMPLETED`, trae un `rideId` usable y no hay un viaje activo
/// más nuevo (`hasNewerActiveRide`, que siempre gana — se navega ahí).
/// `DRIVER_ARRIVED` → `null` (el resolver de sesión ya lleva a
/// `/ride/:rideId` en background y cold start). `RATING_REQUEST`
/// (`screen: 'ride-rating'`, no navegable) y cualquier otro evento →
/// `null` → cae al resolver normal, nunca un `context.go(data['screen'])`
/// genérico.
String? coldStartReceiptRouteFor({
  required RemoteMessage? initialMessage,
  required bool hasNewerActiveRide,
}) {
  if (initialMessage == null) return null;
  if (resolveRideUpdateKind(initialMessage) != RideUpdateKind.rideCompleted) {
    return null;
  }
  if (hasNewerActiveRide) return null;
  final rideId = initialMessage.data['rideId'];
  if (rideId is! String || rideId.trim().isEmpty) return null;
  return '/ride/${rideId.trim()}/receipt';
}
