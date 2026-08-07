import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';

class OtpArguments {
  const OtpArguments({
    required this.phoneE164,
    required this.password,
    this.debugOtp,
  });

  final String phoneE164;
  final String password;
  final String? debugOtp;
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    required this.arguments,
    super.key,
  });

  final OtpArguments arguments;

  @override
  ConsumerState<OtpScreen> createState() =>
      _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _codeController = TextEditingController();

  bool _loading = false;
  bool _resending = false;

  String? _debugOtp;

  @override
  void initState() {
    super.initState();
    _debugOtp = widget.arguments.debugOtp;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();

    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa el código de 6 dígitos.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final repository =
          ref.read(authRepositoryProvider);

      await repository.verifyOtp(
        phoneE164: widget.arguments.phoneE164,
        code: code,
      );

      // Después de verificar el teléfono,
      // iniciamos sesión automáticamente.
      await repository.login(
        phoneE164: widget.arguments.phoneE164,
        password: widget.arguments.password,
      );

      if (!mounted) {
        return;
      }

      context.go('/home');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo verificar el código.';

      if (error.response?.statusCode == 400) {
        message =
            'El código expiró o ya no existe.';
      } else if (error.response?.statusCode == 401) {
        message =
            'El código ingresado es incorrecto.';
      } else if (error.response?.statusCode == 429) {
        message =
            'Se alcanzó el máximo de intentos.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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

  Future<void> _resend() async {
    setState(() {
      _resending = true;
    });

    try {
      final debugOtp = await ref
          .read(authRepositoryProvider)
          .requestOtp(
            phoneE164:
                widget.arguments.phoneE164,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _debugOtp = debugOtp;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se generó un nuevo código.',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo reenviar el código.';

      if (error.response?.statusCode == 429) {
        message =
            'Espera antes de solicitar otro código.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificar celular'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 50),

              const Icon(
                Icons.sms_outlined,
                size: 76,
              ),

              const SizedBox(height: 24),

              const Text(
                'Ingresa tu código',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Enviamos un código a '
                '${widget.arguments.phoneE164}',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType:
                    TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter
                      .digitsOnly,
                  LengthLimitingTextInputFormatter(
                    6,
                  ),
                ],
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 10,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: '000000',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),

              if (_debugOtp != null) ...[
                const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Solo staging',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Código OTP de depuración:',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _debugOtp!,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight:
                                FontWeight.bold,
                            letterSpacing: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              FilledButton(
                onPressed:
                    _loading ? null : _verify,
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
                        'Verificar',
                        style:
                            TextStyle(fontSize: 16),
                      ),
              ),

              const SizedBox(height: 8),

              TextButton(
                onPressed:
                    _resending ? null : _resend,
                child: Text(
                  _resending
                      ? 'Enviando...'
                      : 'Reenviar código',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}