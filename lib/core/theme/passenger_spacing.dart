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
///
/// Dos valores agregados en `DESIGN-SYSTEM-R1` migración de
/// `login_screen.dart` (2026-08-20), tomados del mockup
/// (`docs/contexto/mockups/login.html.html`) porque el documento no
/// los fijaba en una constante propia:
/// - [superposicionHojaCrema]: la sección 5 solo dice "monta 18–20 px
///   sobre el header"; el mockup usa 20, mismo valor ya elegido para
///   [espacioEntreCampos] dentro del mismo rango documentado.
/// - [espacioEtiquetaCampo]: separación entre la etiqueta de un campo
///   (13/600) y el campo mismo; no está en la sección 4, pero el
///   mockup la usa igual (7px) en los dos campos de login.
///
/// Un valor agregado al construir `TukiTextField` (2026-08-20), el
/// campo de texto propio que reemplaza al `InputDecoration` de
/// Material: [espacioInternoCampo], el padding horizontal entre el
/// borde del campo y su contenido (texto/prefijo/sufijo). Antes lo
/// resolvía el `contentPadding` por defecto de Material; el mockup usa
/// 14px parejo en los dos campos de login (`padding: 0 14px`).
///
/// [espacioAntesEnlaceSecundario]: separación entre el campo de
/// contraseña y "¿Olvidaste tu contraseña?" (2026-08-20). Tomado
/// literalmente del mockup (`margin: 14px 0 0` sobre ese enlace).
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
  static const double superposicionHojaCrema = 20;
  static const double espacioEtiquetaCampo = 7;
  static const double espacioInternoCampo = 14;
  static const double espacioAntesEnlaceSecundario = 14;

  /// Ningún elemento tocable mide menos de esto de lado.
  static const double tamanoTocableMinimo = 44;
}
