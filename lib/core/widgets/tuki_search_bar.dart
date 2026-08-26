import 'package:flutter/material.dart';

import '../theme/passenger_colors.dart';
import '../theme/passenger_spacing.dart';
import '../theme/passenger_typography.dart';

/// Barra de búsqueda propia de TukiTuki.
///
/// Variante distinta de "Campo de texto"/[TukiTextField] — documentada
/// como tal en `sistema-de-diseno.md` sección 5, "Barra de búsqueda"
/// (`DESIGN-SYSTEM-R2`). No comparte alto fijo ni etiqueta encima: es
/// una única entrada flotante con lupa fija a la izquierda, sin
/// etiqueta, cuyo alto lo determina su propio contenido.
///
/// Decisiones de contrato tomadas al construir este widget (`HOME-DESIGN-R1`,
/// 2026-08-26), no fijadas explícitamente por el documento:
/// - El estado de la derecha (spinner de carga / botón de limpiar) es
///   responsabilidad del propio widget, no un slot genérico como el
///   `suffix` de [TukiTextField] — el sistema describe ese
///   comportamiento como parte de la identidad de "barra de búsqueda",
///   no como una decoración opcional. Se expone con [isLoading] +
///   [onClear], mutuamente excluyentes: carga gana sobre limpiar: y
///   limpiar solo se muestra si hay texto.
/// - El ícono de lupa es fijo (`Icons.search`), no configurable — no
///   existe hoy un caso de uso de esta barra con otro ícono.
/// - Escucha su propio [controller] (para saber si mostrar el botón de
///   limpiar) y su propio [focusNode] (para el color del borde activo),
///   mismo patrón interno que ya usa [TukiTextField] con su
///   `FocusNode` — el padre no necesita un `setState` propio solo para
///   refrescar el ícono de la derecha.
/// - Sin `errorText`: una barra de búsqueda no tiene un concepto de
///   error de validación — se omite a propósito, no es un olvido.
/// - Alto: el sistema documenta explícitamente que NO es un número
///   fijo (a diferencia de [PassengerSpacing.alturaCampoTexto]). El
///   padding vertical interno queda como constante propia de este
///   widget ([_verticalPadding]), tomado del valor que ya se usaba
///   como literal en `home_screen.dart` — no se promueve a
///   `PassengerSpacing` porque no hay todavía un segundo consumidor.
/// - Borde deshabilitado: el documento no define uno para esta
///   variante (tampoco lo hace para "Campo de texto"). Se usa
///   [PassengerColors.bordeSuave], mismo criterio que el resto de la
///   migración de `home_screen.dart` para bordes secundarios — sujeto
///   a confirmación visual cuando se conecte a la pantalla real.
class TukiSearchBar extends StatefulWidget {
  const TukiSearchBar({
    super.key,
    required this.controller,
    this.hintText,
    this.focusNode,
    this.enabled = true,
    this.isLoading = false,
    this.onClear,
    this.onChanged,
    this.textInputAction,
    this.autocorrect = true,
  });

  final TextEditingController controller;
  final String? hintText;
  final FocusNode? focusNode;
  final bool enabled;

  /// Mientras es `true`, muestra un spinner de carga en vez del botón
  /// de limpiar, sin importar si hay texto.
  final bool isLoading;

  /// Si es `null`, nunca se muestra el botón de limpiar (ni con texto).
  /// Si no es `null`, se muestra solo cuando [controller] tiene texto
  /// y [isLoading] es `false`.
  final VoidCallback? onClear;

  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool autocorrect;

  @override
  State<TukiSearchBar> createState() => _TukiSearchBarState();
}

class _TukiSearchBarState extends State<TukiSearchBar> {
  static const double _verticalPadding = 14;

  FocusNode? _ownedFocusNode;
  bool _hasFocus = false;
  bool _hasText = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();

    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }

    _hasText = widget.controller.text.isNotEmpty;
    _focusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant TukiSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
      _hasText = widget.controller.text.isNotEmpty;
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _ownedFocusNode?.dispose();
      _ownedFocusNode = widget.focusNode == null ? FocusNode() : null;
      _focusNode.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    }
  }

  void _handleTextChange() {
    final hasText = widget.controller.text.isNotEmpty;

    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleTextChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor = _hasFocus
        ? PassengerColors.verdeMarca
        : (widget.enabled
              ? PassengerColors.bordeCampo
              : PassengerColors.bordeSuave);
    final double borderWidth = _hasFocus ? 1.5 : 1;

    final showClear =
        !widget.isLoading && widget.onClear != null && _hasText;

    return Container(
      decoration: BoxDecoration(
        color: PassengerColors.crema,
        borderRadius: BorderRadius.circular(PassengerSpacing.radioCampoBoton),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PassengerSpacing.espacioInternoCampo,
          vertical: _verticalPadding,
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: PassengerColors.verdeMarca),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                textInputAction: widget.textInputAction,
                autocorrect: widget.autocorrect,
                onChanged: widget.onChanged,
                style: PassengerTypography.cuerpo.copyWith(
                  color: PassengerColors.textoPrimario,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  filled: false,
                  hintText: widget.hintText,
                  hintStyle: PassengerTypography.cuerpo.copyWith(
                    color: PassengerColors.placeholder,
                  ),
                ),
              ),
            ),
            if (widget.isLoading) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ] else if (showClear) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Limpiar destino',
                onPressed: widget.onClear,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
