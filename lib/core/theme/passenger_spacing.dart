/// Medidas de TukiTuki Pasajero.
///
/// Valores tomados literalmente de `sistema-de-diseno.md` sección 4.
///
/// Dos decisiones tomadas por JuanJo el 2026-08-20 para resolver
/// rangos que el documento no fijaba en un solo valor:
/// - "Separación entre campos" (18–20) se fijó en 20.
/// - "Radio del logo en el header" (20–28 "según tamaño") se expone
///   como dos límites ([radioLogoHeaderMin]/[radioLogoHeaderMax])
///   porque el propio documento lo describe como variable, no como un
///   valor único — la pantalla que lo use interpola entre ambos según
///   la altura de su header.
class PassengerSpacing {
  const PassengerSpacing._();

  static const double alturaCampoTexto = 56;
  static const double alturaBotonPrincipal = 58;
  static const double radioCampoBoton = 14;
  static const double radioLogoHeaderMin = 20;
  static const double radioLogoHeaderMax = 28;
  static const double radioHojaCrema = 26;
  static const double margenLateralPantalla = 20;
  static const double espacioEntreCampos = 20;
  static const double espacioAntesBotonPrincipal = 24;
  static const double alturaBarraProgreso = 5;
  static const double ladoCheckbox = 24;
  static const double radioCheckbox = 7;

  /// Ningún elemento tocable mide menos de esto de lado.
  static const double tamanoTocableMinimo = 44;
}
