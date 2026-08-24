import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/passenger_colors.dart';
import '../../../core/theme/passenger_spacing.dart';
import '../../../core/theme/passenger_typography.dart';
import '../../../core/widgets/gradient_header_sheet.dart';
import '../../../core/widgets/tuki_text_field.dart';
import '../data/passenger_profile_repository.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  bool _loading = false;
  String? _firstNameError;
  String? _lastNameError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  // Mismos límites que `CreatePassengerProfileDto` en el Backend
  // (`create-passenger-profile.dto.ts`): 2-80 caracteres.
  String? _validateFirstName(String value) {
    final text = value.trim();

    if (text.length < 2) {
      return 'Ingresa tus nombres';
    }

    if (text.length > 80) {
      return 'Máximo 80 caracteres';
    }

    return null;
  }

  String? _validateLastName(String value) {
    final text = value.trim();

    if (text.length < 2) {
      return 'Ingresa tus apellidos';
    }

    if (text.length > 80) {
      return 'Máximo 80 caracteres';
    }

    return null;
  }

  Future<void> _save() async {
    final firstNameError = _validateFirstName(_firstNameController.text);
    final lastNameError = _validateLastName(_lastNameController.text);

    setState(() {
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
    });

    if (firstNameError != null || lastNameError != null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    try {
      await ref
          .read(passengerProfileRepositoryProvider)
          .createMyProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
          );

      if (!mounted) {
        return;
      }

      // No asumimos "listo" localmente: volvemos al resolver de
      // sesión (Splash) para que reconsulte Backend y derive la ruta
      // real a partir del perfil recién creado — mismo mecanismo que
      // login/registro/reapertura de la app.
      context.go('/splash');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.response?.statusCode == 409) {
        // El perfil ya existe (p.ej. doble envío) — igual pasa por el
        // resolver en vez de asumir a dónde ir.
        context.go('/splash');
        return;
      }

      String message = 'No se pudo crear tu perfil.';

      if (error.response?.statusCode == 400) {
        message = 'Revisa los datos ingresados.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: PassengerColors.crema,
        body: GradientHeaderSheet(
          logoAsset: 'assets/images/tukituki_logo.png',
          // Paso obligatorio — el usuario no puede saltárselo, así que
          // sin `leadingAction` no hay flecha de volver (ver
          // sistema-de-diseno.md sección 6: "Nada de flechas que no
          // llevan a ningún lado"). Logo al tamaño por defecto (el
          // mismo que Login): a diferencia de Register, esta pantalla
          // no compite por espacio con un tercer campo, así que no
          // hace falta achicarlo. `headerGrowthBudget` sí se ajusta:
          // con solo dos campos el contenido de la hoja es corto, así
          // que un valor menor deja que el header absorba el sobrante
          // vertical sin dominar la pantalla (medido en dispositivo:
          // ~34% de alto, residuo de la hoja cerca de cero).
          headerGrowthBudget: 180,
          sheetTopPadding: 24,
          sheetChildren: [
            const _StepIndicator(
              currentStep: 2,
              completedSteps: 1,
              totalSteps: 2,
            ),
            const SizedBox(
              height: PassengerSpacing.espacioDespuesIndicadorPasos,
            ),
            Text(
              'Cuéntanos quién eres',
              style: PassengerTypography.tituloPantalla.copyWith(
                color: PassengerColors.textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tu conductor verá tu nombre cuando acepte el viaje.',
              style: PassengerTypography.subtitulo.copyWith(
                color: PassengerColors.textoSecundario,
                height: 1.5,
              ),
            ),
            SizedBox(height: keyboardVisible ? 16 : 26),
            _FieldLabel('Nombres'),
            const SizedBox(height: PassengerSpacing.espacioEtiquetaCampo),
            TukiTextField(
              controller: _firstNameController,
              hintText: 'Juan José',
              textInputAction: TextInputAction.next,
              errorText: _firstNameError,
              autofillHints: const [AutofillHints.givenName],
              onChanged: (_) {
                if (_firstNameError != null) {
                  setState(() {
                    _firstNameError = null;
                  });
                }
              },
            ),
            const SizedBox(height: PassengerSpacing.espacioEntreCampos),
            _FieldLabel('Apellidos'),
            const SizedBox(height: PassengerSpacing.espacioEtiquetaCampo),
            TukiTextField(
              controller: _lastNameController,
              hintText: 'Torres Solano',
              textInputAction: TextInputAction.done,
              errorText: _lastNameError,
              autofillHints: const [AutofillHints.familyName],
              onChanged: (_) {
                if (_lastNameError != null) {
                  setState(() {
                    _lastNameError = null;
                  });
                }
              },
            ),
            const SizedBox(height: PassengerSpacing.espacioAntesBotonPrincipal),
            SizedBox(
              height: PassengerSpacing.alturaBotonPrincipal,
              child: FilledButton(
                onPressed: _loading ? null : _save,
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
                child: _loading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PassengerColors.textoPrimario,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('Guardando...'),
                        ],
                      )
                    : const Text('Continuar'),
              ),
            ),
            const SizedBox(height: PassengerSpacing.espacioAntesNotaPie),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: PassengerSpacing.tamanoIconoNotaPie,
                  color: PassengerColors.textoTenue,
                ),
                const SizedBox(width: PassengerSpacing.espacioIconoNotaPie),
                Expanded(
                  child: Text(
                    'Tu número de celular no se comparte con el conductor.',
                    style: PassengerTypography.notaPrivacidad.copyWith(
                      color: PassengerColors.textoTenue,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta encima de un campo (13/600 `verdeMarca`), ver
/// `sistema-de-diseno.md` sección 5 "Campo de texto". Mismo widget que
/// `login_screen.dart`/`register_screen.dart`.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PassengerTypography.etiquetaCampo.copyWith(
        color: PassengerColors.verdeMarca,
      ),
    );
  }
}

/// Indicador de pasos (`sistema-de-diseno.md` sección 5), con soporte
/// para pasos ya completados además del actual y los pendientes —a
/// diferencia del de `register_screen.dart`, que no lo necesitaba
/// porque Register siempre es el primer paso. Aquí el paso 1
/// (Register) ya se completó, así que va en `acento`; el paso 2
/// (este) es el actual, en `amarilloCTA`.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.completedSteps,
    required this.totalSteps,
  });

  final int currentStep;
  final int completedSteps;
  final int totalSteps;

  Color _colorForStep(int step) {
    if (step <= completedSteps) {
      return PassengerColors.acento;
    }

    if (step == currentStep) {
      return PassengerColors.amarilloCTA;
    }

    return PassengerColors.inactivo;
  }

  @override
  Widget build(BuildContext context) {
    final barRadius = BorderRadius.circular(
      PassengerSpacing.alturaBarraProgreso / 2,
    );

    return Row(
      children: [
        for (var step = 1; step <= totalSteps; step++) ...[
          if (step > 1)
            const SizedBox(width: PassengerSpacing.espacioIndicadorPasos),
          Expanded(
            child: SizedBox(
              height: PassengerSpacing.alturaBarraProgreso,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _colorForStep(step),
                  borderRadius: barRadius,
                  // Mismo motivo que en `register_screen.dart`:
                  // `inactivo` es casi idéntico al fondo `crema`, así
                  // que sin borde propio se percibe más corto que las
                  // barras `acento`/`amarilloCTA`, que sí contrastan.
                  border: _colorForStep(step) == PassengerColors.inactivo
                      ? Border.all(color: PassengerColors.bordeSuave)
                      : null,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: PassengerSpacing.espacioIndicadorPasos),
        Text(
          '$currentStep de $totalSteps',
          style: PassengerTypography.indicadorPasos.copyWith(
            color: PassengerColors.textoSecundario,
          ),
        ),
      ],
    );
  }
}
