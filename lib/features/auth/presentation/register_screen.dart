import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/passenger_colors.dart';
import '../../../core/theme/passenger_spacing.dart';
import '../../../core/theme/passenger_typography.dart';
import '../../../core/widgets/gradient_header_sheet.dart';
import '../../../core/widgets/tuki_text_field.dart';
import '../data/auth_repository.dart';
import 'splash_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _phoneError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePhone(String value) {
    final phone = value.replaceAll(' ', '').trim();

    if (phone.isEmpty) {
      return 'Ingresa tu número de celular';
    }

    if (!RegExp(r'^[0-9]{9}$').hasMatch(phone)) {
      return 'Ingresa un número válido de 9 dígitos';
    }

    return null;
  }

  // Mismas reglas que `RegisterPassengerDto` en el Backend
  // (`register-passenger.dto.ts`): 8-64 caracteres, con minúscula,
  // mayúscula y número. El mockup solo pedía "al menos un número"; se
  // usa el requisito real en vez de ese texto literal.
  String? _validatePassword(String value) {
    if (value.isEmpty) {
      return 'Ingresa una contraseña';
    }

    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }

    if (value.length > 64) {
      return 'La contraseña no puede superar los 64 caracteres';
    }

    final hasLowercase = RegExp(r'[a-z]').hasMatch(value);
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
    final hasNumber = RegExp(r'[0-9]').hasMatch(value);

    if (!hasLowercase || !hasUppercase || !hasNumber) {
      return 'La contraseña debe incluir mayúscula, minúscula y número';
    }

    return null;
  }

  String? _validateConfirmPassword(String value) {
    if (value != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }

    return null;
  }

  Future<void> _register() async {
    final phoneError = _validatePhone(_phoneController.text);
    final passwordError = _validatePassword(_passwordController.text);
    final confirmError = _validateConfirmPassword(
      _confirmPasswordController.text,
    );

    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });

    if (phoneError != null || passwordError != null || confirmError != null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').trim();

    final phoneE164 = '+51$phone';
    final password = _passwordController.text;
    var accountCreated = false;

    try {
      final repository = ref.read(authRepositoryProvider);

      await repository.registerPassenger(
        phoneE164: phoneE164,
        password: password,
      );
      accountCreated = true;

      await repository.login(phoneE164: phoneE164, password: password);

      if (!mounted) {
        return;
      }

      // El usuario recién pulsó "Crear cuenta": el delay de arranque
      // en frío de Splash no aplica acá, se sentiría como una falla.
      context.go(
        '/splash',
        extra: const SplashArguments(skipInitialDelay: true),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo crear la cuenta.';

      if (accountCreated) {
        message =
            'La cuenta fue creada, pero no se pudo iniciar sesión. '
            'Intenta iniciar sesión desde Login.';
      } else if (error.response?.statusCode == 409) {
        message = 'Este número ya está registrado. Intenta iniciar sesión.';
      } else if (error.response?.statusCode == 400) {
        message = 'Revisa los datos ingresados.';
      } else if (error.response?.statusCode == 429) {
        message = 'Espera un momento antes de intentar nuevamente.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accountCreated
                ? 'La cuenta fue creada, pero no se pudo iniciar sesión. '
                      'Intenta iniciar sesión desde Login.'
                : 'Ocurrió un error inesperado.',
          ),
        ),
      );
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
          // Header compacto: sin subtítulo y con un logo más chico que
          // el de Login (que usa los valores por defecto), para que la
          // mayor parte de la altura quede para la hoja (formulario de
          // tres campos). El budget de crecimiento se mantiene corto
          // para que el header no crezca más allá de lo que el logo
          // necesita; el sobrante pasa a la hoja como padding.
          headerMinLogoWidth: 80,
          headerMaxLogoWidth: 112,
          headerGrowthBudget: 24,
          sheetTopPadding: 24,
          leadingAction: IconButton(
            tooltip: 'Volver',
            onPressed: _loading ? null : () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: PassengerColors.blanco,
          ),
          sheetChildren: [
            const _StepIndicator(currentStep: 1, totalSteps: 2),
            const SizedBox(
              height: PassengerSpacing.espacioDespuesIndicadorPasos,
            ),
            Text(
              'Crea tu cuenta',
              style: PassengerTypography.tituloPantalla.copyWith(
                color: PassengerColors.textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Completa tus datos para comenzar.',
              style: PassengerTypography.subtitulo.copyWith(
                color: PassengerColors.textoSecundario,
                height: 1.5,
              ),
            ),
            SizedBox(height: keyboardVisible ? 16 : 26),
            _FieldLabel('Número de celular'),
            const SizedBox(height: PassengerSpacing.espacioEtiquetaCampo),
            TukiTextField(
              controller: _phoneController,
              hintText: '987 654 321',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              errorText: _phoneError,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              onChanged: (_) {
                if (_phoneError != null) {
                  setState(() {
                    _phoneError = null;
                  });
                }
              },
              prefix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+51',
                    style: PassengerTypography.cuerpo.copyWith(
                      color: PassengerColors.verdeMarca,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: PassengerSpacing.alturaCampoTexto * 0.4,
                    child: const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: PassengerColors.bordeSuave,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PassengerSpacing.espacioEntreCampos),
            _FieldLabel('Contraseña'),
            const SizedBox(height: PassengerSpacing.espacioEtiquetaCampo),
            TukiTextField(
              controller: _passwordController,
              hintText: 'Tu contraseña',
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              errorText: _passwordError,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() {
                    _passwordError = null;
                  });
                }
              },
              suffix: IconButton(
                tooltip: _obscurePassword
                    ? 'Mostrar contraseña'
                    : 'Ocultar contraseña',
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: PassengerColors.textoSecundario,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: PassengerColors.textoTenue,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Mínimo 8 caracteres, con mayúscula, minúscula y un '
                    'número.',
                    style: PassengerTypography.pista.copyWith(
                      color: PassengerColors.textoTenue,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PassengerSpacing.espacioEntreCampos),
            _FieldLabel('Confirmar contraseña'),
            const SizedBox(height: PassengerSpacing.espacioEtiquetaCampo),
            TukiTextField(
              controller: _confirmPasswordController,
              hintText: 'Repite tu contraseña',
              obscureText: _obscureConfirmation,
              textInputAction: TextInputAction.done,
              errorText: _confirmError,
              autofillHints: const [AutofillHints.newPassword],
              scrollPadding: EdgeInsets.only(
                bottom: keyboardVisible ? 190 : 20,
              ),
              onChanged: (_) {
                if (_confirmError != null) {
                  setState(() {
                    _confirmError = null;
                  });
                }
              },
              suffix: IconButton(
                tooltip: _obscureConfirmation
                    ? 'Mostrar confirmación'
                    : 'Ocultar confirmación',
                onPressed: () {
                  setState(() {
                    _obscureConfirmation = !_obscureConfirmation;
                  });
                },
                icon: Icon(
                  _obscureConfirmation
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: PassengerColors.textoSecundario,
                ),
              ),
            ),
            const SizedBox(height: PassengerSpacing.espacioAntesBotonPrincipal),
            SizedBox(
              height: PassengerSpacing.alturaBotonPrincipal,
              child: FilledButton(
                onPressed: _loading ? null : _register,
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
                          const Text('Creando cuenta...'),
                        ],
                      )
                    : const Text('Crear cuenta'),
              ),
            ),
            const SizedBox(height: 8),
            const _TermsFootnote(),
            const SizedBox(height: 24),
            Center(
              child: InkWell(
                onTap: _loading
                    ? null
                    : () {
                        context.pop();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '¿Ya tienes cuenta? ',
                          style: PassengerTypography.subtitulo.copyWith(
                            color: PassengerColors.textoSecundario,
                          ),
                        ),
                        TextSpan(
                          text: 'Inicia sesión',
                          style: PassengerTypography.enlace.copyWith(
                            color: PassengerColors.acento,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta encima de un campo (13/600 `verdeMarca`), ver
/// `sistema-de-diseno.md` sección 5 "Campo de texto". Mismo widget que
/// `login_screen.dart`.
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

/// Indicador de pasos (`sistema-de-diseno.md` sección 5): barras de
/// [PassengerSpacing.alturaBarraProgreso] con el paso actual en
/// `amarilloCTA` y los pendientes en `inactivo`, más el texto "N de
/// total". Sin pasos completados todavía en este flujo (solo 2 pasos:
/// registro y completar perfil), así que no hace falta el color
/// `acento` de "paso completado".
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

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
                  color: step == currentStep
                      ? PassengerColors.amarilloCTA
                      : PassengerColors.inactivo,
                  borderRadius: barRadius,
                  // `inactivo` es un beige casi idéntico al fondo
                  // `crema` de la hoja: sin un borde propio, sus
                  // bordes se difuminan contra el fondo y la barra se
                  // percibe más corta que la amarilla (que sí contrasta
                  // fuerte). El borde le da el mismo largo perceptible.
                  border: step == currentStep
                      ? null
                      : Border.all(color: PassengerColors.bordeSuave),
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

/// Reemplaza el checkbox de términos: el estándar de la industria (p.
/// ej. InDriver) es que el acto de continuar constituye la aceptación,
/// así que "Crear cuenta" ya no depende de una casilla — esta nota
/// simplemente lo aclara debajo del botón. "Términos" y "Política de
/// privacidad" muestran un SnackBar temporal (mismo patrón que
/// "¿Olvidaste tu contraseña?" en `login_screen.dart`): ninguno de los
/// dos existe todavía como documento/ruta/URL real (ver
/// `errores-conocidos.md`).
class _TermsFootnote extends StatefulWidget {
  const _TermsFootnote();

  @override
  State<_TermsFootnote> createState() => _TermsFootnoteState();
}

class _TermsFootnoteState extends State<_TermsFootnote> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()..onTap = _showTermsComingSoon;
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = _showPrivacyComingSoon;
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  void _showTermsComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pronto podrás leer nuestros términos')),
    );
  }

  void _showPrivacyComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pronto podrás leer nuestra política de privacidad'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = PassengerTypography.notaBotonInactivo.copyWith(
      color: PassengerColors.textoTenue,
    );
    final linkStyle = PassengerTypography.notaBotonInactivo.copyWith(
      color: PassengerColors.acento,
      fontWeight: FontWeight.w700,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Al crear tu cuenta aceptas nuestros ',
            style: baseStyle,
          ),
          TextSpan(
            text: 'Términos',
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          TextSpan(text: ' y nuestra ', style: baseStyle),
          TextSpan(
            text: 'Política de privacidad',
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
