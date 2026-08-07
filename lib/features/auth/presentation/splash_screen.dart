import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../passenger/data/passenger_profile_repository.dart';
import '../../ride/data/ride_repository.dart';
import '../data/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();

    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(
      const Duration(milliseconds: 800),
    );

    try {
      final authRepository =
          ref.read(authRepositoryProvider);

      final hasSession =
          await authRepository.hasSession();

      if (!mounted) {
        return;
      }

      if (!hasSession) {
        context.go('/login');
        return;
      }

      final user =
          await authRepository.getMe();

      if (!mounted) {
        return;
      }

      final isPassenger =
          user.roles.contains('PASSENGER');

      final isValidPassenger =
          user.status == 'ACTIVE' &&
          user.isPhoneVerified &&
          isPassenger;

      if (!isValidPassenger) {
        await authRepository.clearSession();

        if (!mounted) {
          return;
        }

        context.go('/login');
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

      // IMPORTANTE:
      // Antes de ir al Home comprobamos
      // si este pasajero ya tiene un viaje activo.
      final activeRide = await ref
          .read(rideRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        context.go(
          '/ride/${activeRide.id}',
        );
        return;
      }

      context.go('/home');
    } catch (error) {
      debugPrint(
        'Error restaurando sesión del pasajero: $error',
      );

      await ref
          .read(authRepositoryProvider)
          .clearSession();

      if (!mounted) {
        return;
      }

      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.two_wheeler,
                size: 84,
              ),
              SizedBox(height: 20),
              Text(
                'TukiTuki',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Recuperando tu viaje...',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}