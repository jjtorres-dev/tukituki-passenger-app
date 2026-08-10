import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _cream = Color(0xFFFFF9EC);
  static const Color _fieldFill = Color(0xFFFFFDF7);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF6F7E72);

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
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
        message = 'Tu cuenta todavía no está verificada o habilitada.';
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
    final compact = MediaQuery.sizeOf(context).height < 700;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final logoWidth = keyboardVisible ? 92.0 : (compact ? 136.0 : 150.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _darkGreen,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_darkGreen, _green],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    keyboardVisible ? 6 : (compact ? 12 : 18),
                    24,
                    keyboardVisible ? 8 : (compact ? 18 : 24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/tukituki_logo.png',
                        width: logoWidth,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      SizedBox(height: keyboardVisible ? 2 : 8),
                      Text(
                        'Tu mototaxi en la selva',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: _cream,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        keyboardVisible ? 16 : 28,
                        24,
                        keyboardVisible ? 12 : 20,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Bienvenido de nuevo',
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 28,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ingresa tus datos para continuar tu viaje.',
                              style: TextStyle(
                                color: _secondaryText,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: keyboardVisible ? 16 : 26),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.telephoneNumberNational,
                              ],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                              cursorColor: _green,
                              style: const TextStyle(
                                color: _primaryText,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Número de celular',
                                hintText: '999 999 999',
                                filled: true,
                                fillColor: _fieldFill,
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 78,
                                ),
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(left: 16, right: 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '+51',
                                        style: TextStyle(
                                          color: _darkGreen,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      SizedBox(
                                        height: 24,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 1,
                                          color: _border,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                border: _fieldBorder(_border),
                                enabledBorder: _fieldBorder(_border),
                                focusedBorder: _fieldBorder(_green, width: 2),
                                errorBorder: _fieldBorder(
                                  const Color(0xFFB3261E),
                                ),
                                focusedErrorBorder: _fieldBorder(
                                  const Color(0xFFB3261E),
                                  width: 2,
                                ),
                              ),
                              validator: (value) {
                                final phone =
                                    value?.replaceAll(' ', '').trim() ?? '';

                                if (phone.isEmpty) {
                                  return 'Ingresa tu número de celular';
                                }

                                if (!RegExp(r'^[0-9]{9}$').hasMatch(phone)) {
                                  return 'Ingresa un número válido de 9 dígitos';
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              scrollPadding: EdgeInsets.only(
                                bottom: keyboardVisible ? 96 : 20,
                              ),
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              cursorColor: _green,
                              style: const TextStyle(
                                color: _primaryText,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                filled: true,
                                fillColor: _fieldFill,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: _secondaryText,
                                ),
                                suffixIcon: IconButton(
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
                                    color: _secondaryText,
                                  ),
                                ),
                                border: _fieldBorder(_border),
                                enabledBorder: _fieldBorder(_border),
                                focusedBorder: _fieldBorder(_green, width: 2),
                                errorBorder: _fieldBorder(
                                  const Color(0xFFB3261E),
                                ),
                                focusedErrorBorder: _fieldBorder(
                                  const Color(0xFFB3261E),
                                  width: 2,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }

                                if (value.length < 8) {
                                  return 'La contraseña debe tener al menos 8 caracteres';
                                }

                                return null;
                              },
                            ),
                            SizedBox(height: keyboardVisible ? 14 : 24),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _loading ? null : _login,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _ctaYellow,
                                  foregroundColor: _darkGreen,
                                  disabledBackgroundColor: _border,
                                  disabledForegroundColor: _secondaryText,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: _loading
                                    ? const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox.square(
                                            dimension: 19,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _darkGreen,
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          Text('Iniciando sesión...'),
                                        ],
                                      )
                                    : const Text('Iniciar sesión'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                context.push('/register');
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: _green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 13,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text(
                                '¿No tienes cuenta? Crear cuenta',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
