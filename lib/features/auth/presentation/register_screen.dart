import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'otp_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() =>
      _RegisterScreenState();
}

class _RegisterScreenState
    extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final phone = _phoneController.text
        .replaceAll(' ', '')
        .trim();

    final phoneE164 = '+51$phone';
    final password = _passwordController.text;

    try {
      final repository =
          ref.read(authRepositoryProvider);

      await repository.registerPassenger(
        phoneE164: phoneE164,
        password: password,
      );

      final debugOtp = await repository.requestOtp(
        phoneE164: phoneE164,
      );

      if (!mounted) {
        return;
      }

      context.push(
        '/otp',
        extra: OtpArguments(
          phoneE164: phoneE164,
          password: password,
          debugOtp: debugOtp,
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo crear la cuenta.';

      if (error.response?.statusCode == 409) {
        message =
            'Este número ya está registrado. '
            'Intenta iniciar sesión.';
      } else if (error.response?.statusCode == 400) {
        message =
            'Revisa los datos ingresados.';
      } else if (error.response?.statusCode == 429) {
        message =
            'Espera un momento antes de solicitar '
            'otro código.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ocurrió un error inesperado.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                const Icon(
                  Icons.two_wheeler,
                  size: 72,
                ),

                const SizedBox(height: 24),

                const Text(
                  'Únete a TukiTuki',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Crea tu cuenta de pasajero',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 36),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Número de celular',
                    hintText: '999 999 999',
                    prefixText: '+51 ',
                    prefixIcon:
                        Icon(Icons.phone_android),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final phone = value
                            ?.replaceAll(' ', '')
                            .trim() ??
                        '';

                    if (!RegExp(r'^[0-9]{9}$')
                        .hasMatch(phone)) {
                      return 'Ingresa un número válido '
                          'de 9 dígitos';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon:
                        const Icon(Icons.lock_outline),
                    border:
                        const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.length < 8) {
                      return 'Usa al menos 8 caracteres';
                    }

                    if (value.length > 64) {
                      return 'La contraseña es demasiado larga';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller:
                      _confirmPasswordController,
                  obscureText: _obscureConfirmation),

                TextFormField(
                  controller:
                      _confirmPasswordController,
                  obscureText: _obscureConfirmation,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon:
                        const Icon(Icons.lock_outline),
                    border:
                        const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscureConfirmation =
                              !_obscureConfirmation;
                        });
                      },
                      icon: Icon(
                        _obscureConfirmation
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value !=
                        _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 24),

                FilledButton(
                  onPressed:
                      _loading ? null : _register,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Crear cuenta',
                          style:
                              TextStyle(fontSize: 16),
                        ),
                ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          context.pop();
                        },
                  child: const Text(
                    'Ya tengo una cuenta',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}