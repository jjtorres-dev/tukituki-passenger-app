import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _secondaryGreen = Color(0xFF5C8A17);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _softWhite = Color(0xFFF4F8F3);

  bool _checking = true;
  String? _errorMessage;
  String _statusMessage = 'Preparando TukiTuki...';

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
        _statusMessage = 'Preparando TukiTuki...';
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

      setState(() {
        _statusMessage = 'Recuperando tu sesión...';
      });

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

      setState(() {
        _statusMessage = 'Recuperando tu viaje...';
      });

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: _darkGreen,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_darkGreen, _green, _secondaryGreen],
                  stops: [0, 0.62, 1],
                ),
              ),
            ),
            const CustomPaint(painter: _SplashBackgroundPainter()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: _buildMainContent(constraints.maxHeight),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooter(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(double availableHeight) {
    final compact = availableHeight < 620;
    final logoWidth = compact ? 200.0 : 225.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.96 + (value * 0.04), child: child),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Logo de TukiTuki',
            image: true,
            child: Image.asset(
              'assets/images/tukituki_logo.png',
              width: logoWidth,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          SizedBox(height: compact ? 20 : 26),
          if (_checking)
            Semantics(
              liveRegion: true,
              label: _statusMessage,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _statusMessage,
                  key: ValueKey(_statusMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            _buildErrorContent(),
        ],
      ),
    );
  }

  Widget _buildErrorContent() {
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No pudimos continuar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'No pudimos recuperar tu sesión.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () {
              unawaited(_checkSession(initialDelay: false));
            },
            style: FilledButton.styleFrom(
              backgroundColor: _ctaYellow,
              foregroundColor: _darkGreen,
              minimumSize: const Size(156, 50),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 21),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_checking)
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: _ctaYellow,
              backgroundColor: Color(0x35FFFFFF),
            ),
          )
        else
          const SizedBox(height: 22),
        const SizedBox(height: 16),
        const Text(
          'Tu viaje empieza aquí',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _softWhite,
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stripePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30;

    canvas.drawLine(
      Offset(-size.width * 0.18, size.height * 0.27),
      Offset(size.width * 0.66, -size.height * 0.04),
      stripePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 1.03),
      Offset(size.width * 1.18, size.height * 0.73),
      stripePaint,
    );

    final yellowDotPaint = Paint()
      ..color = _SplashScreenState._ctaYellow.withValues(alpha: 0.18);
    final greenDotPaint = Paint()
      ..color = const Color(0xFFB5D96D).withValues(alpha: 0.14);

    canvas.drawCircle(
      Offset(size.width * 0.14, size.height * 0.19),
      4,
      yellowDotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.26),
      7,
      greenDotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.72),
      6,
      greenDotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.78),
      4,
      yellowDotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashBackgroundPainter oldDelegate) => false;
}
