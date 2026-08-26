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
///
/// Dos valores agregados al migrar `register_screen.dart`
/// (2026-08-23), tomados literalmente de
/// `docs/contexto/mockups/registro.html.html` para el indicador de
/// pasos nuevo (sección 5, "Indicador de pasos"), que no fijaba estos
/// dos números:
/// - [espacioIndicadorPasos]: separación entre las barras y el texto
///   "1 de 2" (`gap: 8px` en el contenedor flex del indicador).
/// - [espacioDespuesIndicadorPasos]: separación entre el indicador de
///   pasos y el título de la hoja (`margin-bottom: 18px`).
///
/// Tres valores agregados al migrar `complete_profile_screen.dart`
/// (2026-08-24), tomados literalmente de
/// `docs/contexto/mockups/completa-perfil.html.html` para la nota de
/// privacidad del número de celular (candado + texto bajo el botón
/// principal), que no tenían equivalente ya definido:
/// - [espacioAntesNotaPie]: separación entre el botón principal y la
///   nota (`margin: 20px ...` del contenedor de la nota en el
///   mockup).
/// - [espacioIconoNotaPie]: separación entre el ícono de candado y su
///   texto (`gap: 9px`).
/// - [tamanoIconoNotaPie]: tamaño del ícono de candado (`font-size:
///   17px` del ícono en el mockup).
///
/// Dos radios agregados en `DESIGN-SYSTEM-R2` (2026-08-26), a partir
/// de la auditoría de `home_screen.dart`: el sistema solo definía
/// [radioCampoBoton] (14) y [radioHojaCrema] (26) porque se diseñó
/// sobre pantallas sin mapa ni chips. Documentados también en
/// `sistema-de-diseno.md` sección 4.
/// - [radioPildora]: radio de los chips/píldoras tocables (chip de
///   métricas sobre el mapa, chip de destino sugerido). Forma
///   completamente redondeada, no la comparten campos ni botones.
/// - [radioEtiquetaMarcador]: radio de la etiqueta que acompaña al
///   marcador de origen en el mapa — más chica y menos redondeada que
///   una píldora, propia de ese único elemento.
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
  static const double espacioIndicadorPasos = 8;
  static const double espacioDespuesIndicadorPasos = 18;
  static const double espacioAntesNotaPie = 20;
  static const double espacioIconoNotaPie = 9;
  static const double tamanoIconoNotaPie = 17;
  static const double radioPildora = 30;
  static const double radioEtiquetaMarcador = 11;

  /// Ningún elemento tocable mide menos de esto de lado.
  static const double tamanoTocableMinimo = 44;
}
