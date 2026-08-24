import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/passenger_colors.dart';
import '../theme/passenger_spacing.dart';
import '../theme/passenger_typography.dart';

/// Campo de texto propio de TukiTuki.
///
/// Todo lo visual (fondo blanco, borde, radio, alto fijo) lo dibuja un
/// [Container] que este widget controla por completo — no un
/// `InputDecoration` de Material. El `InputDecorationTheme` global de
/// `passenger_theme.dart` y el hueco que Material reserva por defecto
/// para el texto de error no tienen forma de alterar la altura del
/// campo ni el espacio entre campos, porque el [TextFormField] interno
/// solo aporta cursor, teclado, formatters y edición de texto: su
/// propia decoración va sin borde y sin padding
/// (`InputBorder.none` + `contentPadding: EdgeInsets.zero`).
///
/// El mensaje de error no es responsabilidad de Material: se pasa por
/// [errorText] y se dibuja como un `Text` aparte, debajo del campo, que
/// solo ocupa espacio cuando hay algo que mostrar. Por eso este widget
/// no expone `validator` — la validación es responsabilidad de quien
/// lo usa (ver `sistema-de-diseno.md` sección 5 "Campo de texto").
class TukiTextField extends StatefulWidget {
  const TukiTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.errorText,
    this.onChanged,
    this.focusNode,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// Slot opcional antes del texto (p. ej. "+51" con su divisor).
  final Widget? prefix;

  /// Slot opcional después del texto (p. ej. el ojo de mostrar/ocultar
  /// contraseña).
  final Widget? suffix;

  /// Mensaje de error a mostrar debajo del campo. `null` = sin error:
  /// no se reserva ningún espacio.
  final String? errorText;

  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final EdgeInsets scrollPadding;

  @override
  State<TukiTextField> createState() => _TukiTextFieldState();
}

class _TukiTextFieldState extends State<TukiTextField> {
  FocusNode? _ownedFocusNode;
  bool _hasFocus = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();

    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }

    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    final Color borderColor = hasError
        ? PassengerColors.error
        : (_hasFocus ? PassengerColors.verdeMarca : PassengerColors.bordeCampo);
    final double borderWidth = hasError || _hasFocus ? 1.5 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: PassengerSpacing.alturaCampoTexto,
          decoration: BoxDecoration(
            color: PassengerColors.blanco,
            borderRadius: BorderRadius.circular(
              PassengerSpacing.radioCampoBoton,
            ),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PassengerSpacing.espacioInternoCampo,
            ),
            child: Row(
              children: [
                if (widget.prefix != null) ...[
                  widget.prefix!,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextFormField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    obscureText: widget.obscureText,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    autofillHints: widget.autofillHints,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    scrollPadding: widget.scrollPadding,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: PassengerColors.acento,
                    style: PassengerTypography.cuerpo.copyWith(
                      color: PassengerColors.textoPrimario,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      // El `InputDecorationTheme` global
                      // (`passenger_theme.dart`) trae `filled: true`;
                      // sin este override explícito, `applyDefaults`
                      // hereda ese `true` (nunca se fijó aquí) y
                      // Material pinta su propio relleno gris encima
                      // del blanco del `Container`. El único relleno
                      // de este campo es el del `Container`.
                      filled: false,
                      hintText: widget.hintText,
                      hintStyle: PassengerTypography.cuerpo.copyWith(
                        color: PassengerColors.placeholder,
                      ),
                    ),
                  ),
                ),
                if (widget.suffix != null) widget.suffix!,
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.errorText!,
              style: PassengerTypography.pista.copyWith(
                color: PassengerColors.error,
              ),
            ),
          ),
      ],
    );
  }
}
