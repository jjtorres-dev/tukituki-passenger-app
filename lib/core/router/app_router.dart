import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/passenger/presentation/complete_profile_screen.dart';
import '../../features/ride/presentation/ride_searching_screen.dart';
import '../../features/ride/presentation/ride_receipt_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      // `pageBuilder` (no `builder`) para poder definir una
      // transición propia: el salto brusco de crema a verde oscuro a
      // pantalla completa es lo que hace sentir que la app se
      // reinició al pasar por acá entre registro/login y el resto del
      // flujo. Un fundido corto suaviza tanto la entrada como la
      // salida (la misma `animation` de la página gobierna las dos).
      pageBuilder: (context, state) {
        final arguments = state.extra;
        final skipInitialDelay =
            arguments is SplashArguments && arguments.skipInitialDelay;

        return CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: SplashScreen(skipInitialDelay: skipInitialDelay),
        );
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) =>
          const RegisterScreen(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final arguments = state.extra;

        if (arguments is! OtpArguments) {
          return const LoginScreen();
        }

        return OtpScreen(
          arguments: arguments,
        );
      },
    ),

    GoRoute(
      path: '/complete-profile',
      builder: (context, state) =>
          const CompleteProfileScreen(),
    ),

    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const HomeScreen(),
    ),

    GoRoute(
      path: '/ride/:rideId/receipt',
      builder: (context, state) {
        final rideId =
            state.pathParameters['rideId']!;

        return RideReceiptScreen(
          rideId: rideId,
        );
      },
    ),

    GoRoute(
      path: '/ride/:rideId',
      builder: (context, state) {
        final rideId =
            state.pathParameters['rideId']!;

        return RideSearchingScreen(
          rideId: rideId,
        );
      },
    ),
  ],
);