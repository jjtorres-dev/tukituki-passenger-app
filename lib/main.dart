import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

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

  runApp(
    const ProviderScope(
      child: TukiTukiApp(),
    ),
  );
}