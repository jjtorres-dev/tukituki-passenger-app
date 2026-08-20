import 'package:flutter/material.dart';

/// Paleta de marca de TukiTuki Pasajero.
///
/// Nombres y valores tomados literalmente de `sistema-de-diseno.md`
/// sección 2. No se agregan colores que no estén en ese documento.
class PassengerColors {
  const PassengerColors._();

  // Base — compartidos con la app del conductor.
  static const Color verdeMarca = Color(0xFF123B26);
  static const Color verdeProfundo = Color(0xFF0B2517);
  static const Color verdeClaro = Color(0xFF1D5433);
  static const Color crema = Color(0xFFFFF9EC);
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color textoPrimario = Color(0xFF16241C);
  static const Color textoSecundario = Color(0xFF5A6B5C);
  static const Color textoTenue = Color(0xFF7C8A79);
  static const Color placeholder = Color(0xFF8A9487);
  static const Color bordeCampo = Color(0xFFC3CDBE);
  static const Color bordeSuave = Color(0xFFE7E0CB);
  static const Color inactivo = Color(0xFFE2DCC9);

  // Acento — distinto por app; este es el valor Passenger (verde).
  static const Color acento = Color(0xFF1F7A3E);

  // Acción — compartido. Exclusivo del botón principal, uno por pantalla.
  static const Color amarilloCTA = Color(0xFFFFC72C);

  // Estados.
  static const Color exito = Color(0xFF1F7A3E);
  static const Color alerta = Color(0xFFE8951A);
  static const Color error = Color(0xFFE05B4F);
  static const Color destino = Color(0xFFD8542C);
}
