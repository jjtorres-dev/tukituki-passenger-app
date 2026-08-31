import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/passenger_colors.dart';
import '../../core/theme/passenger_spacing.dart';
import '../../core/theme/passenger_typography.dart';
import '../ride/domain/fare_amount.dart';
import '../ride/domain/payment_method.dart';
import '../ride/presentation/payment_method_picker_sheet.dart';
import 'domain/offer_fare_result.dart';

/// Pantalla de confirmación "Ofrece tu tarifa" (`FARE-PANEL-R1`, etapa 4).
///
/// Construida como una pantalla de confirmación pura: nunca llama a
/// `createRide` — devuelve el monto y método de pago finales por
/// `Navigator.pop(context, OfferFareResult(...))` al tocar "Encontrar
/// ofertas", o `Navigator.pop(context)` (sin resultado) al volver sin
/// confirmar. `HomeScreen` decide qué hacer con eso (llama a
/// `_requestRide()` con los valores ya actualizados); esta pantalla no
/// conoce la cotización, el repositorio de rides ni el de preferencia
/// de pago — todo lo que necesita llega por constructor.
///
/// Origen y destino se muestran de solo lectura: son datos ya resueltos
/// por Home (mismo criterio que `SearchDestinationScreen` con el
/// origen), esta pantalla no los recalcula ni los permite editar.
class OfferFareScreen extends StatefulWidget {
  const OfferFareScreen({
    super.key,
    required this.offerCents,
    required this.paymentMethod,
    required this.originAddress,
    required this.destinationName,
    required this.destinationAddress,
  });

  /// Monto actual del stepper de Home, en centavos.
  final int offerCents;

  final PaymentMethod paymentMethod;

  final String originAddress;
  final String destinationName;
  final String? destinationAddress;

  @override
  State<OfferFareScreen> createState() => _OfferFareScreenState();
}

class _OfferFareScreenState extends State<OfferFareScreen> {
  /// Mismo rango que el stepper de Home (`_offerMinCents`/`_offerMaxCents`
  /// en `home_screen.dart`), deliberadamente duplicado en vez de
  /// importado: son campos privados de `_HomeScreenState`, inalcanzables
  /// desde aquí (la privacidad de Dart es por archivo, no por clase).
  /// Mismo criterio de duplicación que ya usó `ORIGIN-ADDRESS-R1` con la
  /// fórmula de Haversine entre `home_screen.dart` y
  /// `ride_searching_screen.dart`.
  static const int _offerMinCents = 300;
  static const int _offerMaxCents = 5000;

  late int _offerCents = widget.offerCents;
  late PaymentMethod _paymentMethod = widget.paymentMethod;
  late final TextEditingController _amountController = TextEditingController(
    text: _formatCentsAsSoles(_offerCents),
  );
  final FocusNode _amountFocusNode = FocusNode();

  /// `false` mientras el texto actual del campo no parsea a un monto
  /// dentro de [_offerMinCents]..[_offerMaxCents]. El CTA se deshabilita
  /// en tiempo real con esta bandera — no se espera a perder el foco.
  bool _amountValid = true;

  /// Refleja el foco del campo de monto para pintar la línea divisoria
  /// (reposo/foco/error, mismos 3 estados que la tabla "Campo de
  /// texto" de `sistema-de-diseno.md` §5, aplicados a esta línea en
  /// vez de a los 4 lados de una caja).
  bool _amountHasFocus = false;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(_handleAmountFocusChange);
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_handleAmountFocusChange);
    _amountFocusNode.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _handleAmountFocusChange() {
    if (_amountFocusNode.hasFocus) {
      setState(() {
        _amountHasFocus = true;
      });
      return;
    }

    _amountHasFocus = false;
    _finalizeAmount();
  }

  void _handleAmountChanged(String value) {
    final cents = fareAmountInCents(value);
    final valid =
        cents != null && cents >= _offerMinCents && cents <= _offerMaxCents;

    setState(() {
      _amountValid = valid;

      if (valid) {
        _offerCents = cents;
      }
    });
  }

  /// Corrige el campo al perder el foco: un monto parseable pero fuera
  /// de rango (p. ej. 0.50 o 100) se ajusta al límite más cercano; uno
  /// no parseable (vacío, o un "." suelto mientras se escribe) vuelve
  /// al último monto válido conocido. Nunca fuerza múltiplos de S/0.50
  /// — a diferencia del stepper de Home, este campo acepta cualquier
  /// monto exacto dentro del rango.
  void _finalizeAmount() {
    final cents = fareAmountInCents(_amountController.text);

    final resolvedCents = cents == null
        ? _offerCents
        : cents.clamp(_offerMinCents, _offerMaxCents);

    setState(() {
      _offerCents = resolvedCents;
      _amountValid = true;
      _amountController.text = _formatCentsAsSoles(resolvedCents);
      _amountController.selection = TextSelection.collapsed(
        offset: _amountController.text.length,
      );
    });
  }

  Future<void> _openPaymentMethodPicker() async {
    final selected = await showModalBottomSheet<PaymentMethod>(
      context: context,
      backgroundColor: PassengerColors.crema,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PassengerSpacing.radioHojaCrema),
        ),
      ),
      builder: (_) => PaymentMethodPickerSheet(current: _paymentMethod),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _paymentMethod = selected;
    });
  }

  IconData _paymentMethodIcon(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => Icons.payments,
    PaymentMethod.yape => Icons.smartphone,
    PaymentMethod.plin => Icons.qr_code_2,
  };

  void _confirm() {
    Navigator.pop(
      context,
      OfferFareResult(offerCents: _offerCents, paymentMethod: _paymentMethod),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PassengerColors.crema,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                  Text(
                    'Ofrece tu tarifa',
                    style: PassengerTypography.tituloSeccion.copyWith(
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: PassengerSpacing.margenLateralPantalla,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAmountSection(),
                    const SizedBox(height: PassengerSpacing.espacioEntreCampos),
                    _buildPaymentMethodRow(),
                    const SizedBox(height: PassengerSpacing.espacioEntreCampos),
                    _buildOriginDestinationCard(),
                    const SizedBox(height: PassengerSpacing.espacioEntreCampos),
                  ],
                ),
              ),
            ),
            _buildCtaFooter(),
          ],
        ),
      ),
    );
  }

  /// Mismo lenguaje visual que `_buildOriginDestinationCard` de
  /// `home_screen.dart` (tarjeta `crema`/`bordeSuave`/`radioTarjeta`,
  /// punto verde "Origen", pin "Destino", conector punteado), pero de
  /// solo lectura: sin botón "Quitar destino" y con strings ya
  /// resueltas por constructor en vez de `Position`/`LatLng`/
  /// `FareEstimate` en vivo. No se extrae un widget compartido porque
  /// las dos versiones difieren en si el dato es vivo o estático —
  /// mismo criterio que `ORIGIN-ADDRESS-R1` usó para no forzar un util
  /// compartido entre contextos que no lo necesitan.
  Widget _buildOriginDestinationCard() {
    return Container(
      key: const ValueKey('offer-fare-origin-destination-card'),
      padding: const EdgeInsets.all(PassengerSpacing.paddingTarjeta),
      decoration: BoxDecoration(
        color: PassengerColors.crema,
        borderRadius: BorderRadius.circular(PassengerSpacing.radioTarjeta),
        border: Border.all(color: PassengerColors.bordeSuave),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: PassengerColors.acento,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.my_location,
                  color: PassengerColors.blanco,
                  size: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Origen',
                      style: TextStyle(
                        color: PassengerColors.textoSecundario,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.originAddress,
                      style: const TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 2,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: PassengerColors.bordeSuave,
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                color: PassengerColors.destino,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Destino',
                      style: TextStyle(
                        color: PassengerColors.textoSecundario,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.destinationAddress != null &&
                        widget.destinationAddress!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.destinationAddress!,
                        style: const TextStyle(
                          color: PassengerColors.textoSecundario,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Monto grande y editable, alineado a la izquierda, con una línea
  /// divisoria debajo en vez de la caja completa de `TukiTextField`
  /// (fondo blanco + borde en las 4 esquinas): esa caja se diseñó para
  /// "Campo de texto" de `sistema-de-diseno.md` §5, no para una cifra
  /// grande de una sola línea. Mismo criterio de divergencia
  /// estructural que ya resolvió el propio documento con "Barra de
  /// búsqueda" (§5) — un widget a mano en vez de ramificar
  /// `TukiTextField` con un flag nuevo.
  ///
  /// Reutiliza los mismos dos tokens de tipografía que el stepper de
  /// precio de Home (`PassengerTypography.montoOferta`/`prefijoMoneda`,
  /// alineados por línea de base) y la misma tabla de 3 estados de
  /// "Campo de texto" (reposo/foco/error) que usaba `TukiTextField`,
  /// aplicada acá a la línea inferior en vez de a los 4 lados.
  Widget _buildAmountSection() {
    final Color dividerColor = !_amountValid
        ? PassengerColors.error
        : (_amountHasFocus ? PassengerColors.verdeMarca : PassengerColors.bordeSuave);
    final double dividerWidth = !_amountValid || _amountHasFocus ? 1.5 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Puedes modificar la tarifa',
          style: PassengerTypography.pista.copyWith(
            color: PassengerColors.textoSecundario,
          ),
        ),
        const SizedBox(height: PassengerSpacing.espacioInternoTarjeta),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'S/ ',
              style: PassengerTypography.prefijoMoneda.copyWith(
                color: PassengerColors.textoSecundario,
              ),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('offer-fare-amount-field'),
                controller: _amountController,
                focusNode: _amountFocusNode,
                style: PassengerTypography.montoOferta.copyWith(
                  color: PassengerColors.textoPrimario,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  _MaxTwoDecimalsFormatter(),
                ],
                onChanged: _handleAmountChanged,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: PassengerSpacing.espacioInternoTarjeta),
        Container(height: dividerWidth, color: dividerColor),
      ],
    );
  }

  Widget _buildPaymentMethodRow() {
    return InkWell(
      key: const ValueKey('offer-fare-payment-method-row'),
      onTap: _openPaymentMethodPicker,
      borderRadius: BorderRadius.circular(PassengerSpacing.radioTarjeta),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PassengerSpacing.paddingTarjeta,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: PassengerColors.blanco,
          borderRadius: BorderRadius.circular(PassengerSpacing.radioTarjeta),
          border: Border.all(color: PassengerColors.bordeCampo),
        ),
        child: Row(
          children: [
            Icon(
              _paymentMethodIcon(_paymentMethod),
              color: PassengerColors.verdeMarca,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _paymentMethod.label,
                style: const TextStyle(
                  color: PassengerColors.textoPrimario,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: PassengerColors.textoSecundario,
            ),
          ],
        ),
      ),
    );
  }

  /// Botón principal siguiendo `sistema-de-diseno.md` §5 al pie de la
  /// letra: fondo `amarilloCTA`/radio `radioCampoBoton` habilitado;
  /// deshabilitado sin relleno, borde 1.5px `bordeBotonInactivo`, texto
  /// `textoBotonInactivo`, con la línea explicativa de
  /// `notaBotonInactivo` (12/500) debajo — mismo patrón de
  /// `WidgetStateProperty.resolveWith` que ya usa el botón "Crear
  /// cuenta" de `register_screen.dart`.
  Widget _buildCtaFooter() {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      decoration: const BoxDecoration(
        color: PassengerColors.crema,
        border: Border(top: BorderSide(color: PassengerColors.bordeSuave)),
      ),
      child: SafeArea(
        top: false,
        bottom: !keyboardVisible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: PassengerSpacing.alturaBotonPrincipal,
                child: FilledButton(
                  key: const ValueKey('offer-fare-confirm-button'),
                  onPressed: _amountValid ? _confirm : null,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? PassengerColors.crema
                          : PassengerColors.amarilloCTA,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? PassengerColors.textoBotonInactivo
                          : PassengerColors.textoPrimario,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? const BorderSide(
                              color: PassengerColors.bordeBotonInactivo,
                              width: 1.5,
                            )
                          : BorderSide.none,
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          PassengerSpacing.radioCampoBoton,
                        ),
                      ),
                    ),
                    textStyle: WidgetStatePropertyAll(
                      PassengerTypography.botonPrincipal,
                    ),
                    elevation: const WidgetStatePropertyAll(0),
                  ),
                  child: const Text('Encontrar ofertas'),
                ),
              ),
              if (!_amountValid) ...[
                const SizedBox(height: 8),
                Text(
                  'Ingresa un monto entre S/3.00 y S/50.00 para continuar.',
                  style: PassengerTypography.notaBotonInactivo.copyWith(
                    color: PassengerColors.textoSecundario,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtra el texto del campo de monto a como mucho un separador decimal
/// y dos decimales — mismo criterio de forma que ya exige
/// `fareAmountInCents`/`normalizePassengerOfferFare`
/// (`ride/domain/fare_amount.dart`), aplicado acá en el formatter para
/// que el usuario no pueda ni escribir un segundo punto o un tercer
/// decimal, en vez de dejarlo escribir y rechazar después.
class _MaxTwoDecimalsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    final dotCount = '.'.allMatches(text).length;

    if (dotCount > 1) {
      return oldValue;
    }

    final dotIndex = text.indexOf('.');

    if (dotIndex != -1 && text.length - dotIndex - 1 > 2) {
      return oldValue;
    }

    return newValue;
  }
}

/// Centavos → cadena decimal "X.XX", mismo formato que
/// `_formatCentsAsSoles` de `home_screen.dart` (duplicado por la misma
/// razón que los límites de arriba — campo privado, inalcanzable desde
/// este archivo).
String _formatCentsAsSoles(int cents) {
  final whole = cents ~/ 100;
  final fraction = (cents % 100).toString().padLeft(2, '0');
  return '$whole.$fraction';
}
