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
///
/// Cuatro colores agregados en `DESIGN-SYSTEM-R2` (2026-08-26), a
/// partir de la auditoría de `home_screen.dart` — primera pantalla del
/// sistema con mapa y con texto sobre superficie oscura fuera del
/// header. Documentados también en `sistema-de-diseno.md` secciones 2
/// y 4.
///
/// - [aviso] / [fondoAviso]: color y fondo dedicados a estados
///   vencidos o erróneos que hoy piden atención sin ser un error de
///   validación de formulario. Antes de este checkpoint,
///   `home_screen.dart` reutilizaba [destino] (`#D8542C`) para el
///   aviso de "sin ubicación" — mezclaba "esto es el pin de destino"
///   con "esto necesita tu atención". [aviso] es un color nuevo
///   (`#B8641E`), deliberadamente distinto de [alerta] (`#E8951A`):
///   [alerta] es idéntico al acento de la app del Conductor, y
///   reutilizarlo en una pantalla tan prominente como Home (mapa a
///   pantalla completa, visible todo el viaje) arriesgaba la señal de
///   reconocimiento de marca que describe la sección 1 del sistema de
///   diseño ("el pasajero, al subirse de noche, reconoce de un vistazo
///   que la pantalla que le muestra el conductor es realmente la app
///   del conductor"). [aviso] comparte familia cálida con [destino] y
///   [alerta] pero es más oscuro/ocre que ambos — visualmente distinto
///   de los dos a simple vista, no solo en el valor hex.
///
///   **Validado por cálculo de contraste (`HOME-DESIGN-R1`, 2026-08-26),
///   solo para uso sobre fondos claros.** Contra [crema]/[fondoAviso]
///   da 4.10:1 (pasa el mínimo de 3:1 para íconos). Contra `verdeMarca`
///   daba 2.90:1 — no pasaba ni el mínimo de ícono (3:1) ni el de texto
///   (4.5:1). En vez de buscar un segundo valor para fondo oscuro, se
///   quitó el único uso de [aviso] que caía sobre `verdeMarca`
///   ("cotización vencida" en `home_screen.dart`, ver
///   `App-passenger/decisiones.md`): el ícono que lo acompañaba se
///   eliminó por decorativo y el texto pasó a
///   [textoSecundarioSobreOscuro]. [aviso] queda con un solo uso, sobre
///   [crema], y no necesita partirse en dos tokens.
/// - [textoTenueSobreOscuro] / [textoSecundarioSobreOscuro]: el
///   sistema se definió sobre login/registro/completar perfil, todas
///   pantallas claras — nunca cubrió texto sobre una superficie
///   oscura fuera del header degradado. Nombrados por rol (paralelos a
///   [textoTenue] y [textoSecundario]) con calificador de superficie,
///   no por su valor de color, para que el nombre siga siendo válido
///   si el tono exacto cambia. Valores tomados literalmente de
///   `home_screen.dart` (`#8FA891`, etiqueta micro del marcador de
///   origen; `#B9C8BC`, texto de ayuda de la tarjeta de oferta).
///
/// Un color agregado en `HOME-DESIGN-R1` (2026-08-26), categoría nueva
/// ("Superposición sobre el mapa", `sistema-de-diseno.md` sección 2):
/// [lineaRuta], la línea de la ruta que se dibuja sobre el `GoogleMap`
/// entre origen y destino. Decisión explícita de JuanJo: **no**
/// reutiliza [acento] — es un color que se valida contra el mapa real,
/// no contra el resto de la paleta de interfaz, y el valor ya en uso
/// (`#5C8A17`) funciona sobre el mapa; forzarlo a [acento] lo
/// oscurecería sin haber probado ese cambio en calle.
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

  // Aviso — estados vencidos/erróneos que no son error de formulario
  // ni el pin de destino. Ver nota de clase.
  static const Color aviso = Color(0xFFB8641E);
  static const Color fondoAviso = Color(0xFFFFF0E8);

  // Texto sobre fondo oscuro — ver nota de clase.
  static const Color textoTenueSobreOscuro = Color(0xFF8FA891);
  static const Color textoSecundarioSobreOscuro = Color(0xFFB9C8BC);

  // Superposición sobre el mapa — ver nota de clase.
  static const Color lineaRuta = Color(0xFF5C8A17);
}
