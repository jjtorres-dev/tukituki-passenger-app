import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/passenger_profile_repository.dart';

class CompleteProfileScreen
    extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController =
      TextEditingController();

  final _lastNameController =
      TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
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
            firstName:
                _firstNameController.text.trim(),
            lastName:
                _lastNameController.text.trim(),
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

      String message =
          'No se pudo crear tu perfil.';

      if (error.response?.statusCode == 409) {
        // El perfil ya existe (p.ej. doble envío) — igual pasa por el
        // resolver en vez de asumir a dónde ir.
        context.go('/splash');
        return;
      }

      if (error.response?.statusCode == 400) {
        message =
            'Revisa los datos ingresados.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa tu perfil'),
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
                const SizedBox(height: 30),

                const Icon(
                  Icons.person_outline,
                  size: 80,
                ),

                const SizedBox(height: 24),

                const Text(
                  'Cuéntanos quién eres',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Estos datos serán parte de tu '
                  'perfil de pasajero.',
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 36),

                TextFormField(
                  controller:
                      _firstNameController,
                  textCapitalization:
                      TextCapitalization.words,
                  decoration:
                      const InputDecoration(
                    labelText: 'Nombres',
                    prefixIcon:
                        Icon(Icons.person),
                    border:
                        OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';

                    if (text.length < 2) {
                      return 'Ingresa tus nombres';
                    }

                    if (text.length > 80) {
                      return 'Máximo 80 caracteres';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller:
                      _lastNameController,
                  textCapitalization:
                      TextCapitalization.words,
                  decoration:
                      const InputDecoration(
                    labelText: 'Apellidos',
                    prefixIcon:
                        Icon(Icons.badge_outlined),
                    border:
                        OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';

                    if (text.length < 2) {
                      return 'Ingresa tus apellidos';
                    }

                    if (text.length > 80) {
                      return 'Máximo 80 caracteres';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 24),

                FilledButton(
                  onPressed:
                      _loading ? null : _save,
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
                          'Continuar',
                          style:
                              TextStyle(fontSize: 16),
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