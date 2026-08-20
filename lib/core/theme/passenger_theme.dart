import 'package:flutter/material.dart';

import 'passenger_colors.dart';

/// `ThemeData` de TukiTuki Pasajero, construido a partir de
/// [PassengerColors] en vez de una semilla genérica de Material.
///
/// Nota de alcance (2026-08-20): esto es solo infraestructura de tema.
/// No fija `fontFamily` a nivel global — eso aplicaría Manrope a todo
/// texto de pantalla que hoy no especifica una fuente propia,
/// cambiando visualmente pantallas que esta tarea no debe tocar. Las
/// pantallas seguirán usando `PassengerTypography` explícitamente
/// cuando se migren en la tarea siguiente.
class PassengerTheme {
  const PassengerTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PassengerColors.acento,
        brightness: Brightness.light,
        error: PassengerColors.error,
      ),
      scaffoldBackgroundColor: PassengerColors.crema,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
      ),
    );
  }
}
