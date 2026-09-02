import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `PASSENGER-PUSH-R1` (Etapa 2). Datos del canal Android para los
/// avisos sobre el estado del viaje en curso. Se declaran acá para que
/// `main()` (que crea el canal al arrancar) y `FlnLocalNotifications`
/// (que lo referencia al mostrar) usen exactamente los mismos valores.
///
/// Un solo canal para ambos eventos (`DRIVER_ARRIVED` y
/// `RIDE_COMPLETED`) — decisión de producto de esta etapa.
const String kRideUpdatesChannelId = 'ride_updates';
const String kRideUpdatesChannelName = 'Estado del viaje';
const String kRideUpdatesChannelDescription =
    'Avisos sobre el estado de tu viaje en curso';

/// `PASSENGER-PUSH-R1` (Etapa 2). Eventos del viaje a los que la app
/// reacciona con un aviso visible cuando llegan con la app en
/// foreground. Cualquier otro evento se recibe pero no se materializa.
enum RideUpdateKind {
  /// El conductor llegó al origen (`data.eventType == 'DRIVER_ARRIVED'`).
  driverArrived,

  /// El viaje terminó (`data.route == 'ride-receipt'`).
  rideCompleted;

  /// ID de notificación **por evento** (no fijo, a diferencia del
  /// conductor): así un `DRIVER_ARRIVED` no borra un `RIDE_COMPLETED`
  /// si llegaran cerca en el tiempo. El ID sí es fijo dentro de cada
  /// evento — un reintento de FCM del mismo evento reemplaza, no apila.
  int get notificationId {
    switch (this) {
      case RideUpdateKind.driverArrived:
        return 1;
      case RideUpdateKind.rideCompleted:
        return 2;
    }
  }

  /// Título de reserva, solo si el backend mandara `notification.title`
  /// nulo (hoy siempre lo manda).
  String get fallbackTitle {
    switch (this) {
      case RideUpdateKind.driverArrived:
        return 'Tu conductor llegó';
      case RideUpdateKind.rideCompleted:
        return 'Viaje completado';
    }
  }

  /// Cuerpo de reserva, solo si el backend mandara `notification.body`
  /// nulo (hoy siempre lo manda).
  String get fallbackBody {
    switch (this) {
      case RideUpdateKind.driverArrived:
        return 'El conductor está cerca del origen. Revisa el PIN antes de abordar.';
      case RideUpdateKind.rideCompleted:
        return 'Tu viaje terminó. Revisa el detalle de la tarifa.';
    }
  }
}

/// Instancia de `FlutterLocalNotificationsPlugin` ya inicializada en
/// `main()` (con el canal `ride_updates` creado). `main()` sobreescribe
/// este provider vía `ProviderScope(overrides: ...)`; sin ese override
/// lanza a propósito, porque nada debería consumirlo fuera del árbol
/// real de la app.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      throw UnimplementedError(
        'flutterLocalNotificationsPluginProvider debe sobreescribirse con la '
        'instancia inicializada en main()',
      );
    });

/// Seam fino sobre `flutter_local_notifications`: permite que
/// `PushMessageHandler` se pruebe con un doble a mano (el plugin real
/// no funciona dentro de `flutter_test`).
abstract class LocalNotifications {
  /// Muestra —o reemplaza— un aviso sobre el estado del viaje. El [id]
  /// es parámetro (a diferencia del conductor): cada evento usa el
  /// suyo, ver [RideUpdateKind.notificationId].
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

/// Implementación real: delega en el `FlutterLocalNotificationsPlugin`
/// ya inicializado, con el canal `ride_updates`.
class FlnLocalNotifications implements LocalNotifications {
  FlnLocalNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kRideUpdatesChannelId,
          kRideUpdatesChannelName,
          channelDescription: kRideUpdatesChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

final localNotificationsProvider = Provider<LocalNotifications>((ref) {
  return FlnLocalNotifications(
    ref.watch(flutterLocalNotificationsPluginProvider),
  );
});
