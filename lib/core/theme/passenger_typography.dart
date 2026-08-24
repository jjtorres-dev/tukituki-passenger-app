import 'package:flutter/material.dart';

/// Escala tipográfica de TukiTuki Pasajero.
///
/// Tamaños, pesos, letter-spacing e interlineado tomados literalmente
/// de `sistema-de-diseno.md` sección 3. Los estilos no incluyen color:
/// el color depende del contexto de uso y se aplica al consumir el
/// token (`.copyWith(color: ...)`).
///
/// Dos decisiones tomadas por JuanJo el 2026-08-20 para resolver
/// rangos que el documento no fijaba en un solo valor:
/// - "Subtítulo y texto de enlace" (15, 400/700) ya estaba resuelto por
///   la sección 5 ("Enlace: color acento, peso 700"): dos estilos,
///   [subtitulo] y [enlace].
/// - "Pista y nota al pie" (12–13, 400/500) se dividió en dos estilos
///   distintos: [pista] (12/400) y [notaAlPie] (13/500).
class PassengerTypography {
  const PassengerTypography._();

  static const String fontFamily = 'Manrope';

  static const TextStyle tituloPantalla = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  static const TextStyle tituloSeccion = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle botonPrincipal = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle cuerpo = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle subtitulo = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle enlace = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// Enlace independiente y de menor jerarquía que [enlace] (que es
  /// para el texto de enlace dentro de una frase, sección 3: "15,
  /// 400/700"). No está en la tabla de la sección 3 — tamaño y peso
  /// tomados literalmente de `docs/contexto/mockups/login.html.html`
  /// (`¿Olvidaste tu contraseña?`, `font-size: 14px; font-weight:
  /// 600;`) por indicación directa de JuanJo (2026-08-20).
  static const TextStyle enlaceAuxiliar = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle etiquetaCampo = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle pista = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle notaAlPie = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
}
