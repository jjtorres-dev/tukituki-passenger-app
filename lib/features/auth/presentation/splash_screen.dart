import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(
      const Duration(milliseconds: 1200),
    );

    try {
      final repository =
          ref.read(authRepositoryProvider);

      final hasSession =
          await repository.hasSession();

      if (!hasSession) {
        if (mounted) {
          context.go('/login');
        }
        return;
      }

      final user = await repository.getMe();

      if (!mounted) {
        return;
      }

      final isPassenger =
          user.roles.contains('PASSENGER');

      if (user.status == 'ACTIVE' &&
          user.isPhoneVerified &&
          isPassenger) {
        context.go('/home');
      } else {
        await repository.clearSession();

        if (mounted) {
          context.go('/login');
        }
      }
    } catch (_) {
      await ref
          .read(authRepositoryProvider)
          .clearSession();

      if (mounted) {
        context.go('/login');
      }
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
                'Tu viaje empieza aquí',
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