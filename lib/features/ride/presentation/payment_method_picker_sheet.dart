import 'package:flutter/material.dart';

import '../../../core/theme/passenger_colors.dart';
import '../../../core/theme/passenger_spacing.dart';
import '../../../core/theme/passenger_typography.dart';
import '../domain/payment_method.dart';

/// Hoja del selector de método de pago (`FARE-PANEL-R1`).
///
/// Devuelve el [PaymentMethod] elegido vía `Navigator.pop`, o `null` si
/// se cierra sin elegir. Solo Efectivo/Yape/Plin — `CARD` no se
/// ofrece (ver `PaymentMethod`).
///
/// Extraída de `home_screen.dart` en la Etapa 4 de `FARE-PANEL-R1`
/// para que la pantalla de confirmación ("Ofrece tu tarifa") pueda
/// reutilizarla sin duplicar código — Home y esa pantalla nunca la
/// muestran a la vez, así que no hace falta un store reactivo, solo
/// un widget compartido.
class PaymentMethodPickerSheet extends StatelessWidget {
  const PaymentMethodPickerSheet({super.key, required this.current});

  final PaymentMethod current;

  IconData _iconFor(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => Icons.payments,
    PaymentMethod.yape => Icons.smartphone,
    PaymentMethod.plin => Icons.qr_code_2,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: PassengerColors.bordeSuave,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PassengerSpacing.margenLateralPantalla,
              16,
              PassengerSpacing.margenLateralPantalla,
              4,
            ),
            child: Text(
              '¿Cómo vas a pagar?',
              style: PassengerTypography.tituloSeccion.copyWith(
                color: PassengerColors.textoPrimario,
              ),
            ),
          ),
          for (final method in PaymentMethod.values)
            InkWell(
              key: ValueKey('payment-option-${method.name}'),
              onTap: () => Navigator.pop(context, method),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PassengerSpacing.margenLateralPantalla,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(method),
                      size: 24,
                      color: PassengerColors.textoPrimario,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        method.label,
                        style: PassengerTypography.cuerpo.copyWith(
                          color: PassengerColors.textoPrimario,
                        ),
                      ),
                    ),
                    if (method == current)
                      const Icon(
                        Icons.check,
                        size: 22,
                        color: PassengerColors.acento,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
