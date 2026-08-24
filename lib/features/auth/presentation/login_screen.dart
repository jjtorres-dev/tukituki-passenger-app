import 'package:dio/dio.dart';
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

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _phoneError;
  String? _passwordError;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
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

  String? _validatePassword(String value) {
    if (value.isEmpty) {
      return 'Ingresa tu contraseña';
    }

    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }

    return null;
  }

  Future<void> _login() async {
    final phoneError = _validatePhone(_phoneController.text);
    final passwordError = _validatePassword(_passwordController.text);

    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
    });

    if (phoneError != null || passwordError != null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').trim();

    final phoneE164 = '+51$phone';

    try {
      await ref
          .read(authRepositoryProvider)
          .login(phoneE164: phoneE164, password: _passwordController.text);

      if (!mounted) {
        return;
      }

      context.go('/splash');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo iniciar sesión.';

      if (error.response?.statusCode == 401) {
        message = 'Teléfono o contraseña incorrectos.';
      } else if (error.response?.statusCode == 403) {
        message = 'Tu cuenta no está habilitada para iniciar sesión.';
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
        const SnackBar(content: Text('Ocurrió un error inesperado.')),
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
          tagline: Text(
            'Tu mototaxi en la selva',
            textAlign: TextAlign.center,
            style: PassengerTypography.subtitulo.copyWith(
              color: PassengerColors.blanco.withValues(alpha: 0.9),
            ),
          ),
          sheetChildren: [
            Text(
              'Bienvenido de nuevo',
              style: PassengerTypography.tituloPantalla.copyWith(
                color: PassengerColors.textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ingresa tus datos para continuar tu viaje.',
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
              textInputAction: TextInputAction.done,
              errorText: _passwordError,
              autofillHints: const [AutofillHints.password],
              scrollPadding: EdgeInsets.only(
                bottom: keyboardVisible ? 96 : 20,
              ),
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
            // Con teclado abierto se oculta, mismo criterio que el
            // subtítulo del header: el espacio es escaso justo cuando
            // el usuario está escribiendo la contraseña, y este enlace
            // no es crítico en ese momento.
            if (!keyboardVisible) ...[
              const SizedBox(
                height: PassengerSpacing.espacioAntesEnlaceSecundario,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Pronto podrás recuperar tu contraseña',
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    // Sin padding a la derecha para que el texto quede
                    // alineado con el borde derecho de los campos (el
                    // padding solo agranda el área táctil hacia la
                    // izquierda y verticalmente).
                    padding: const EdgeInsets.only(
                      left: 4,
                      top: 8,
                      bottom: 8,
                    ),
                    child: Text(
                      '¿Olvidaste tu contraseña?',
                      style: PassengerTypography.enlaceAuxiliar.copyWith(
                        color: PassengerColors.acento,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: PassengerSpacing.espacioAntesBotonPrincipal),
            SizedBox(
              height: PassengerSpacing.alturaBotonPrincipal,
              child: FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(
                  backgroundColor: PassengerColors.amarilloCTA,
                  foregroundColor: PassengerColors.textoPrimario,
                  disabledBackgroundColor: PassengerColors.inactivo,
                  disabledForegroundColor: PassengerColors.textoTenue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      PassengerSpacing.radioCampoBoton,
                    ),
                  ),
                  textStyle: PassengerTypography.botonPrincipal,
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
                          const Text('Iniciando sesión...'),
                        ],
                      )
                    : const Text('Iniciar sesión'),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: InkWell(
                onTap: () {
                  context.push('/register');
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
                          text: '¿No tienes cuenta? ',
                          style: PassengerTypography.subtitulo.copyWith(
                            color: PassengerColors.textoSecundario,
                          ),
                        ),
                        TextSpan(
                          text: 'Crear cuenta',
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
/// `sistema-de-diseno.md` sección 5 "Campo de texto".
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
