import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fallamos inmediatamente si la URL del backend no fue configurada.
  AppConfig.normalizedApiBaseUrl;

  runApp(
    const ProviderScope(
      child: TukiTukiApp(),
    ),
  );
}