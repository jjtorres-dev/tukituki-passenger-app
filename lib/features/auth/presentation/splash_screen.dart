import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../passenger/data/passenger_profile_repository.dart';
import '../../ride/data/ride_repository.dart';
import '../data/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _checking = true;
  String? _errorMessage;

  Timer? _initialDelayTimer;
  Completer<void>? _initialDelayCompleter;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSession());
  }

  @override
  void dispose() {
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;

    final completer = _initialDelayCompleter;
    _initialDelayCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    super.dispose();
  }

  Future<void> _waitInitialDelay() {
    _initialDelayTimer?.cancel();

    final completer = Completer<void>();
    _initialDelayCompleter = completer;

    _initialDelayTimer = Timer(const Duration(milliseconds: 800), () {
      _initialDelayTimer = null;

      if (!completer.isCompleted) {
        completer.complete();
      }

      if (identical(_initialDelayCompleter, completer)) {
        _initialDelayCompleter = null;
      }
    });

    return completer.future;
  }

  Future<void> _checkSession({bool initialDelay = true}) async {
    if (mounted) {
      setState(() {
        _checking = true;
        _errorMessage = null;
      });
    }

    if (initialDelay) {
      await _waitInitialDelay();

      if (!mounted) {
        return;
      }
    }

    try {
      final authRepository = ref.read(authRepositoryProvider);

      final hasSession = await authRepository.hasSession();

      if (!mounted) {
        return;
      }

      if (!hasSession) {
        context.go('/login');
        return;
      }

      final user = await authRepository.getMe();

      if (!mounted) {
        return;
      }

      final isPassenger = user.roles.contains('PASSENGER');

      final isValidPassenger =
          user.status == 'ACTIVE' && user.isPhoneVerified && isPassenger;

      if (!isValidPassenger) {
        await _clearSessionAndGoToLogin(authRepository);
        return;
      }

      final profile = await ref
          .read(passengerProfileRepositoryProvider)
          .getMyProfile();

      if (!mounted) {
        return;
      }

      if (profile == null) {
        context.go('/complete-profile');
        return;
      }

      final activeRide = await ref.read(rideRepositoryProvider).getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        context.go('/ride/${activeRide.id}');
        return;
      }

      context.go('/home');
    } on DioException catch (error) {
      debugPrint(
        'Error HTTP restaurando sesión del pasajero: '
        '${error.response?.statusCode} '
        '${error.requestOptions.path} '
        '${error.type}',
      );

      if (error.response?.statusCode == 401) {
        final authRepository = ref.read(authRepositoryProvider);

        await _clearSessionAndGoToLogin(authRepository);
        return;
      }

      _showRecoverableError(_messageForDioError(error));
    } catch (error) {
      debugPrint('Error restaurando sesión del pasajero: $error');

      // Un error de parsing, almacenamiento, backend,
      // perfil o viaje no demuestra por sí solo que la
      // sesión haya dejado de ser válida.
      //
      // Conservamos las credenciales y permitimos
      // reintentar.
      _showRecoverableError(
        'No pudimos recuperar tu sesión en este momento. '
        'Intenta nuevamente.',
      );
    }
  }

  Future<void> _clearSessionAndGoToLogin(AuthRepository authRepository) async {
    try {
      await authRepository.clearSession();
    } catch (error) {
      debugPrint(
        'No se pudo limpiar completamente '
        'la sesión local: $error',
      );
    }

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  void _showRecoverableError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _checking = false;
      _errorMessage = message;
    });
  }

  String _messageForDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TukiTuki está tardando más de lo esperado. '
            'Tu sesión se mantiene guardada.';

      case DioExceptionType.connectionError:
        return 'No pudimos conectarnos con TukiTuki. '
            'Revisa tu conexión e intenta nuevamente.';

      default:
        final statusCode = error.response?.statusCode;

        if (statusCode != null && statusCode >= 500) {
          return 'El servidor de TukiTuki no está disponible '
              'temporalmente. Tu sesión se mantiene guardada.';
        }

        return 'No pudimos recuperar tu sesión en este momento. '
            'Intenta nuevamente.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.two_wheeler, size: 84),
                const SizedBox(height: 20),
                const Text(
                  'TukiTuki',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _checking
                      ? 'Recuperando tu viaje...'
                      : 'No pudimos continuar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                if (_checking)
                  const CircularProgressIndicator()
                else ...[
                  Text(
                    _errorMessage ?? 'No pudimos recuperar tu sesión.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      unawaited(_checkSession(initialDelay: false));
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
