import 'package:flutter/material.dart';

/// Paleta de marca de TukiTuki Pasajero.
///
/// Nombres y valores tomados literalmente de `sistema-de-diseno.md`
/// sección 2. No se agregan colores que no estén en ese documento.
///
/// Dos valores agregados en `DESIGN-SYSTEM-R1` al migrar
/// `register_screen.dart` (2026-08-23): [bordeBotonInactivo] y
/// [textoBotonInactivo]. No están en la tabla de la sección 2, pero sí
/// están fijados como hex literal en la sección 5 ("Botón principal",
/// estado deshabilitado: "borde 1.5 px #D5CFBA, texto #A79F8A") sin
/// nombre propio — se les da nombre aquí en vez de escribir el hex a
/// mano en la pantalla.
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
  static const Color bordeBotonInactivo = Color(0xFFD5CFBA);
  static const Color textoBotonInactivo = Color(0xFFA79F8A);

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
