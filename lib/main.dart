import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/notifications/data/local_notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fallamos inmediatamente si la URL del backend no fue configurada.
  AppConfig.normalizedApiBaseUrl;

  // PASSENGER-PUSH-R1 (Etapa 1). Best-effort: si Firebase no puede
  // inicializar (sin conexión al arrancar, Play Services ausente,
  // etc.) la app debe seguir funcionando igual, sin push. No hay
  // firebase_options.dart: es Android-only y el plugin gradle
  // `com.google.gms.google-services` inyecta la configuración desde
  // android/app/google-services.json.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (error) {
    debugPrint('PASSENGER PUSH - Firebase.initializeApp() falló: $error');
  }

  // PASSENGER-PUSH-R1 (Etapa 2). Best-effort: inicializa
  // flutter_local_notifications y crea explícitamente el canal
  // `ride_updates`. Un fallo acá no impide que la app arranque —
  // simplemente no habrá aviso en foreground (el flujo de seguimiento
  // del viaje mantiene su polling como fuente de verdad). La instancia
  // ya inicializada se expone al árbol vía
  // `flutterLocalNotificationsPluginProvider`.
  //
  // IMPORTANTE: acá NO se pide el permiso de notificaciones
  // (`requestNotificationsPermission()`), ni se activan
  // `requestAlertPermission` / `requestSoundPermission` /
  // `requestBadgePermission` en `initialize()`. El permiso de
  // notificaciones es responsabilidad EXCLUSIVA de
  // `PushRegistrationCoordinator.syncDeviceRegistration()` (Etapa 1),
  // cuyo fix ya secuencia ese diálogo para que no compita con el de
  // ubicación. Agregar acá un segundo request reintroduciría esa
  // carrera (Android solo permite un diálogo de permiso a la vez).
  final localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  try {
    await localNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        // El manejo real del tap (navegar al viaje / recibo) es
        // Etapa 3; acá el tap solo trae la app al frente.
        debugPrint(
          'PASSENGER PUSH - notificación tocada (payload: ${response.payload})',
        );
      },
    );

    await localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kRideUpdatesChannelId,
            kRideUpdatesChannelName,
            description: kRideUpdatesChannelDescription,
            importance: Importance.high,
          ),
        );
  } catch (error) {
    debugPrint(
      'PASSENGER PUSH - init de flutter_local_notifications falló: $error',
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        flutterLocalNotificationsPluginProvider.overrideWithValue(
          localNotificationsPlugin,
        ),
      ],
      child: const TukiTukiApp(),
    ),
  );
}