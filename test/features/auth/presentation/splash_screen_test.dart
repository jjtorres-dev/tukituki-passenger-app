import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:passenger/features/auth/data/auth_repository.dart';
import 'package:passenger/features/auth/domain/public_user.dart';
import 'package:passenger/features/auth/presentation/splash_screen.dart';
import 'package:passenger/features/notifications/data/device_id_store.dart';
import 'package:passenger/features/notifications/data/push_message_handler.dart';
import 'package:passenger/features/notifications/data/push_messaging_service.dart';
import 'package:passenger/features/notifications/data/push_registration_coordinator.dart';
import 'package:passenger/features/notifications/data/push_registration_repository.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';
import 'package:passenger/features/ride/data/ride_repository.dart';
import 'package:passenger/features/ride/domain/passenger_ride.dart';

void main() {
  testWidgets(
    'PASSENGER ACTIVE verificado con perfil y sin ride conserva sesión y va a home',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: true),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: const {'id': 'profile-1'},
      );
      final rideRepository = _FakeRideRepository();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(authRepository.clearSessionCalls, 0);
      expect(profileRepository.getMyProfileCalls, 1);
      expect(rideRepository.getActiveRideCalls, 1);
    },
  );

  testWidgets(
    'PASSENGER ACTIVE no verificado también conserva sesión y va a home',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: false),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: const {'id': 'profile-1'},
      );
      final rideRepository = _FakeRideRepository();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(authRepository.clearSessionCalls, 0);
      expect(profileRepository.getMyProfileCalls, 1);
      expect(rideRepository.getActiveRideCalls, 1);
    },
  );

  testWidgets('PASSENGER PENDING es inválido y limpia la sesión', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      user: _user(status: 'PENDING', isPhoneVerified: true),
    );
    final profileRepository = _FakePassengerProfileRepository();
    final rideRepository = _FakeRideRepository();
    final router = _splashRouter();
    addTearDown(router.dispose);

    await _pumpSplash(
      tester,
      router: router,
      authRepository: authRepository,
      profileRepository: profileRepository,
      rideRepository: rideRepository,
    );

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(authRepository.clearSessionCalls, 1);
    expect(profileRepository.getMyProfileCalls, 0);
    expect(rideRepository.getActiveRideCalls, 0);
  });

  testWidgets('Sin sesión navega a login', (tester) async {
    final authRepository = _FakeAuthRepository(hasSessionValue: false);
    final profileRepository = _FakePassengerProfileRepository();
    final rideRepository = _FakeRideRepository();
    final router = _splashRouter();
    addTearDown(router.dispose);

    await _pumpSplash(
      tester,
      router: router,
      authRepository: authRepository,
      profileRepository: profileRepository,
      rideRepository: rideRepository,
    );

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(authRepository.getMeCalls, 0);
    expect(authRepository.clearSessionCalls, 0);
    expect(profileRepository.getMyProfileCalls, 0);
    expect(rideRepository.getActiveRideCalls, 0);
  });

  testWidgets(
    'Perfil 404 y sin ride va a completar perfil (R4.2 — identidad '
    'obligatoria antes de Home)',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: false),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: null,
      );
      final rideRepository = _FakeRideRepository();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(
        router.routeInformationProvider.value.uri.path,
        '/complete-profile',
      );
      expect(find.text('PROFILE_DESTINATION'), findsOneWidget);
      expect(profileRepository.getMyProfileCalls, 1);
      expect(rideRepository.getActiveRideCalls, 1);
      expect(authRepository.clearSessionCalls, 0);
    },
  );

  testWidgets(
    'Perfil 404 pero con ride activo prioriza el ride sobre el gate de '
    'identidad (legacy: no bloquea a un Passenger ya en medio de un '
    'viaje)',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: false),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: null,
      );
      final rideRepository = _FakeRideRepository(activeRide: _ride());
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(router.routeInformationProvider.value.uri.path, '/ride/ride-active');
      expect(find.text('RIDE_DESTINATION ride-active'), findsOneWidget);
      expect(rideRepository.getActiveRideCalls, 1);
      expect(authRepository.clearSessionCalls, 0);
    },
  );

  testWidgets(
    'Perfil ya completo (con firstName/lastName) continúa a home — '
    'ningún dato de perfil se descarta silenciosamente',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: true),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: const {
          'id': 'profile-1',
          'firstName': 'María',
          'lastName': 'Rodríguez',
        },
      );
      final rideRepository = _FakeRideRepository();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(profileRepository.getMyProfileCalls, 1);
      expect(rideRepository.getActiveRideCalls, 1);
    },
  );

  testWidgets(
    'Perfil completo y con ride activo va al ride, no a home (las 4 '
    'combinaciones de hasProfile/activeRide quedan cubiertas a nivel '
    'de integración, no solo en el resolver puro)',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: true),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: const {
          'id': 'profile-1',
          'firstName': 'María',
          'lastName': 'Rodríguez',
        },
      );
      final rideRepository = _FakeRideRepository(activeRide: _ride());
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(router.routeInformationProvider.value.uri.path, '/ride/ride-active');
      expect(find.text('RIDE_DESTINATION ride-active'), findsOneWidget);
      expect(profileRepository.getMyProfileCalls, 1);
      expect(rideRepository.getActiveRideCalls, 1);
    },
  );

  testWidgets(
    'No se puede volver de Sobre-ti a Home con el botón atrás — Splash '
    'nunca deja a Home en la pila cuando el gate de identidad aplica',
    (tester) async {
      final authRepository = _FakeAuthRepository(
        user: _user(isPhoneVerified: false),
      );
      final profileRepository = _FakePassengerProfileRepository(
        profile: null,
      );
      final rideRepository = _FakeRideRepository();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
      );

      expect(
        router.routeInformationProvider.value.uri.path,
        '/complete-profile',
      );

      final context = tester.element(find.text('PROFILE_DESTINATION'));
      expect(Navigator.of(context).canPop(), isFalse);
    },
  );

  for (final failure in <(String, DioException)>[
    (
      'network',
      DioException(
        requestOptions: RequestOptions(path: 'passengers/me'),
        type: DioExceptionType.connectionError,
        error: StateError('offline'),
      ),
    ),
    ('5xx', _dioHttpError('passengers/me', 503)),
  ]) {
    testWidgets(
      'Perfil ${failure.$1} no se interpreta como 404 y permite reintentar',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: false),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {
            'id': 'profile-1',
            'firstName': 'Juan',
            'lastName': 'Pérez',
          },
          error: failure.$2,
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
        );

        expect(router.routeInformationProvider.value.uri.path, '/splash');
        expect(find.text('Reintentar'), findsOneWidget);
        expect(rideRepository.getActiveRideCalls, 0);
        expect(authRepository.clearSessionCalls, 0);

        profileRepository.error = null;
        await tester.tap(find.text('Reintentar'));
        await _flushSplash(tester);

        expect(router.routeInformationProvider.value.uri.path, '/home');
        expect(profileRepository.getMyProfileCalls, 2);
        expect(rideRepository.getActiveRideCalls, 1);
      },
    );
  }

  testWidgets('401 definitivo de auth me limpia sesión y navega a login', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository(
      getMeError: _dioHttpError('auth/me', 401),
    );
    final profileRepository = _FakePassengerProfileRepository();
    final rideRepository = _FakeRideRepository();
    final router = _splashRouter();
    addTearDown(router.dispose);

    await _pumpSplash(
      tester,
      router: router,
      authRepository: authRepository,
      profileRepository: profileRepository,
      rideRepository: rideRepository,
    );

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(authRepository.getMeCalls, 1);
    expect(authRepository.clearSessionCalls, 1);
    expect(profileRepository.getMyProfileCalls, 0);
    expect(rideRepository.getActiveRideCalls, 0);
  });

  group('PASSENGER-PUSH-R1 (Etapa 1): registro de dispositivo push', () {
    testWidgets(
      'con destino /home el splash NO dispara push (lo hace HomeScreen '
      'tras resolver el permiso de ubicación) — la navegación a /home se '
      'completa igual',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository();
        final coordinator = _FakePushRegistrationCoordinator();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(router.routeInformationProvider.value.uri.path, '/home');
        expect(coordinator.syncCalls, 0);
      },
    );

    testWidgets('sin sesión NO se intenta registrar el dispositivo', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(hasSessionValue: false);
      final profileRepository = _FakePassengerProfileRepository();
      final rideRepository = _FakeRideRepository();
      final coordinator = _FakePushRegistrationCoordinator();
      final router = _splashRouter();
      addTearDown(router.dispose);

      await _pumpSplash(
        tester,
        router: router,
        authRepository: authRepository,
        profileRepository: profileRepository,
        rideRepository: rideRepository,
        coordinator: coordinator,
      );

      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(coordinator.syncCalls, 0);
    });

    testWidgets(
      'perfil incompleto también dispara el registro antes de ir a '
      '/complete-profile — el enganche es después de resolver el estado '
      'de sesión (ruta distinta a /home), y la navegación se completa '
      'aunque el coordinador nunca termine',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: false),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: null,
        );
        final rideRepository = _FakeRideRepository();
        final coordinator = _FakePushRegistrationCoordinator(
          behavior: _CoordinatorBehavior.hangs,
        );
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'perfil 404 con ride activo (tercer destino de éxito, /ride/:id) '
      'también dispara el registro',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: false),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: null,
        );
        final rideRepository = _FakeRideRepository(activeRide: _ride());
        final coordinator = _FakePushRegistrationCoordinator();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(
          router.routeInformationProvider.value.uri.path,
          '/ride/ride-active',
        );
        expect(coordinator.syncCalls, 1);
      },
    );

    testWidgets(
      'PASSENGER PENDING inválido limpia la sesión antes de la línea de '
      'éxito → no se intenta registrar el dispositivo',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(status: 'PENDING', isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository();
        final rideRepository = _FakeRideRepository();
        final coordinator = _FakePushRegistrationCoordinator();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(authRepository.clearSessionCalls, 1);
        expect(coordinator.syncCalls, 0);
      },
    );

    testWidgets(
      '401 definitivo de auth/me también limpia sesión sin registrar el '
      'dispositivo',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          getMeError: _dioHttpError('auth/me', 401),
        );
        final profileRepository = _FakePassengerProfileRepository();
        final rideRepository = _FakeRideRepository();
        final coordinator = _FakePushRegistrationCoordinator();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(authRepository.clearSessionCalls, 1);
        expect(coordinator.syncCalls, 0);
      },
    );

    testWidgets(
      'dos entradas a /splash con sesión válida en la misma sesión de la '
      'app (p. ej. logout/login), destino /complete-profile → dos '
      'registros con el mismo coordinador, sin lanzar (idempotencia del '
      'coordinador provider-scoped; /complete-profile sí registra desde '
      'el splash, no tiene la carrera de permisos de /home)',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: false),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: null,
        );
        final rideRepository = _FakeRideRepository();
        final coordinator = _FakePushRegistrationCoordinator();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          coordinator: coordinator,
        );

        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(coordinator.syncCalls, 1);

        // Simula reentrar a /splash dentro del mismo proceso de la app
        // (misma ProviderScope, mismo coordinador) — p. ej. tras un
        // logout/login sin reiniciar la app. Un pump vacío primero
        // procesa la navegación (monta el SplashScreen nuevo y corre su
        // initState) antes de avanzar el reloj del delay inicial.
        router.go('/splash');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 801));
        await _flushSplash(tester);

        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(coordinator.syncCalls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PASSENGER-PUSH-R1 (Etapa 3): cold start al recibo', () {
    testWidgets(
      'a) tap de RIDE_COMPLETED con la app terminada y sin viaje activo → '
      'siembra /home y apila el recibo; el back del recibo vuelve a /home',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-receipt',
            'rideId': 'r9',
            'status': 'COMPLETED',
          }),
        );

        // El recibo queda arriba de /home. Se verifica por la pila real
        // del delegate y por la pantalla visible: `pushReplacement` +
        // `push` componen `[/home, recibo]` en el navigator, aunque
        // go_router no actualice `routeInformationProvider` en un push
        // imperativo (solo lo hace `go`) — irrelevante en móvil (sin
        // barra de URL) y el back sí usa la pila del navigator.
        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/home', '/ride/r9/receipt'],
        );
        expect(find.text('RECEIPT_DESTINATION r9'), findsOneWidget);
        expect(find.text('HOME_DESTINATION'), findsNothing);

        // Pila bien formada: el back del recibo cae en /home, no cierra
        // la app.
        final context = tester.element(find.text('RECEIPT_DESTINATION r9'));
        expect(Navigator.of(context).canPop(), isTrue);

        router.pop();
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/home'],
        );
        expect(find.text('HOME_DESTINATION'), findsOneWidget);
        expect(find.text('RECEIPT_DESTINATION r9'), findsNothing);
      },
    );

    testWidgets(
      'b) tap de RIDE_COMPLETED pero hay un viaje activo más nuevo → gana '
      'el viaje activo, no el recibo viejo',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository(activeRide: _ride());
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-receipt',
            'rideId': 'r9',
          }),
        );

        expect(
          router.routeInformationProvider.value.uri.path,
          '/ride/ride-active',
        );
        expect(find.text('RIDE_DESTINATION ride-active'), findsOneWidget);
      },
    );

    testWidgets(
      'c) tap de RIDE_COMPLETED pero el perfil está incompleto → el desvío '
      'se suprime, va a /complete-profile (nunca se salta el gate de '
      'identidad)',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: false),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: null,
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-receipt',
            'rideId': 'r9',
          }),
        );

        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(find.text('PROFILE_DESTINATION'), findsOneWidget);
      },
    );

    testWidgets(
      'd) tap de RIDE_COMPLETED sin sesión → nunca llega al branch, va a '
      '/login',
      (tester) async {
        final authRepository = _FakeAuthRepository(hasSessionValue: false);
        final profileRepository = _FakePassengerProfileRepository();
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-receipt',
            'rideId': 'r9',
          }),
        );

        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(rideRepository.getActiveRideCalls, 0);
      },
    );

    testWidgets(
      'e) tap de DRIVER_ARRIVED no dispara el desvío (lo cubre el resolver '
      'de sesión) → va a /home cuando no hay viaje activo',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-detail',
            'rideId': 'r9',
            'eventType': 'DRIVER_ARRIVED',
          }),
        );

        expect(router.routeInformationProvider.value.uri.path, '/home');
        expect(find.text('HOME_DESTINATION'), findsOneWidget);
      },
    );

    testWidgets(
      'f) tap de RATING_REQUEST (screen ride-rating, no navegable) no '
      'dispara el desvío → cae al resolver normal, /home',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
          initialPushMessage: _initialMessage(const {
            'screen': 'ride-rating',
            'rideId': 'r9',
          }),
        );

        expect(router.routeInformationProvider.value.uri.path, '/home');
        expect(find.text('HOME_DESTINATION'), findsOneWidget);
      },
    );

    testWidgets(
      'g) sin initialMessage (arranque normal) el splash se comporta '
      'exactamente como hoy → /home',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          user: _user(isPhoneVerified: true),
        );
        final profileRepository = _FakePassengerProfileRepository(
          profile: const {'id': 'profile-1'},
        );
        final rideRepository = _FakeRideRepository();
        final router = _splashRouter();
        addTearDown(router.dispose);

        await _pumpSplash(
          tester,
          router: router,
          authRepository: authRepository,
          profileRepository: profileRepository,
          rideRepository: rideRepository,
        );

        expect(router.routeInformationProvider.value.uri.path, '/home');
        expect(find.text('HOME_DESTINATION'), findsOneWidget);
      },
    );
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.hasSessionValue = true, this.user, this.getMeError})
    : super(Dio(), const FlutterSecureStorage());

  final bool hasSessionValue;
  final PublicUser? user;
  final Object? getMeError;

  int getMeCalls = 0;
  int clearSessionCalls = 0;

  @override
  Future<bool> hasSession() async => hasSessionValue;

  @override
  Future<PublicUser> getMe() async {
    getMeCalls++;

    final error = getMeError;
    if (error != null) {
      throw error;
    }

    return user ?? _user(isPhoneVerified: false);
  }

  @override
  Future<void> clearSession() async {
    clearSessionCalls++;
  }
}

class _FakePassengerProfileRepository extends PassengerProfileRepository {
  _FakePassengerProfileRepository({this.profile, this.error}) : super(Dio());

  final Map<String, dynamic>? profile;
  Object? error;
  int getMyProfileCalls = 0;

  @override
  Future<Map<String, dynamic>?> getMyProfile() async {
    getMyProfileCalls++;

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    return profile;
  }
}

class _FakeRideRepository extends RideRepository {
  _FakeRideRepository({this.activeRide}) : super(Dio());

  final PassengerRide? activeRide;
  int getActiveRideCalls = 0;

  @override
  Future<PassengerRide?> getActiveRide() async {
    getActiveRideCalls++;
    return activeRide;
  }
}

enum _CoordinatorBehavior { noop, hangs }

class _NoopPushMessagingService implements PushMessagingService {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
}

/// Doble del coordinador de push para los tests del splash: cuenta las
/// invocaciones y puede simular un cuelgue para verificar que la
/// navegación del splash no depende de él.
class _FakePushRegistrationCoordinator extends PushRegistrationCoordinator {
  _FakePushRegistrationCoordinator({
    this.behavior = _CoordinatorBehavior.noop,
  }) : super(
         _NoopPushMessagingService(),
         DeviceIdStore(const FlutterSecureStorage()),
         PushRegistrationRepository(Dio()),
       );

  final _CoordinatorBehavior behavior;
  int syncCalls = 0;

  @override
  Future<void> syncDeviceRegistration() async {
    syncCalls += 1;

    switch (behavior) {
      case _CoordinatorBehavior.noop:
        return;
      case _CoordinatorBehavior.hangs:
        await Completer<void>().future;
    }
  }
}

GoRouter _splashRouter() {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('LOGIN_DESTINATION')),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Text('HOME_DESTINATION')),
      ),
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) =>
            const Scaffold(body: Text('PROFILE_DESTINATION')),
      ),
      GoRoute(
        path: '/ride/:rideId/receipt',
        builder: (context, state) => Scaffold(
          body: Text('RECEIPT_DESTINATION ${state.pathParameters['rideId']}'),
        ),
      ),
      GoRoute(
        path: '/ride/:rideId',
        builder: (context, state) => Scaffold(
          body: Text('RIDE_DESTINATION ${state.pathParameters['rideId']}'),
        ),
      ),
    ],
  );
}

Future<void> _pumpSplash(
  WidgetTester tester, {
  required GoRouter router,
  required AuthRepository authRepository,
  required PassengerProfileRepository profileRepository,
  required RideRepository rideRepository,
  PushRegistrationCoordinator? coordinator,
  RemoteMessage? initialPushMessage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        passengerProfileRepositoryProvider.overrideWithValue(profileRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
        // El coordinador real toca FirebaseMessaging.instance, que no
        // existe en flutter_test. Se reemplaza por un doble no-op
        // salvo que el test quiera otro comportamiento.
        pushRegistrationCoordinatorProvider.overrideWithValue(
          coordinator ?? _FakePushRegistrationCoordinator(),
        ),
        // PASSENGER-PUSH-R1 (Etapa 3): en producción lo sobreescribe
        // `main()` con `getInitialMessage()`. Por defecto null (arranque
        // normal, sin tap de notificación con la app terminada).
        initialPushMessageProvider.overrideWithValue(initialPushMessage),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pump(const Duration(milliseconds: 801));
  await _flushSplash(tester);
}

/// `RemoteMessage` mínimo para simular el `getInitialMessage()` de un
/// cold start por tap de notificación.
RemoteMessage _initialMessage(Map<String, dynamic> data) {
  return RemoteMessage(data: data);
}

Future<void> _flushSplash(WidgetTester tester) async {
  for (var index = 0; index < 14; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

PublicUser _user({String status = 'ACTIVE', required bool isPhoneVerified}) {
  return PublicUser(
    id: 'user-1',
    phoneE164: '+51999999999',
    roles: const ['PASSENGER'],
    status: status,
    isPhoneVerified: isPhoneVerified,
    createdAt: DateTime.utc(2026, 8, 10),
  );
}

PassengerRide _ride() {
  return PassengerRide(
    id: 'ride-active',
    fareQuoteId: 'quote-1',
    status: 'SEARCHING_DRIVER',
    distanceMeters: 1500,
    estimatedDurationSeconds: 600,
    estimatedFare: '7.00',
    estimatedPassengerFare: '7.00',
    passengerOfferFare: '7.00',
    agreedFare: null,
    currency: 'PEN',
    paymentMethod: 'CASH',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    requestedAt: DateTime.utc(2026, 8, 10),
    searchExpiresAt: null,
  );
}

DioException _dioHttpError(String path, int statusCode) {
  final requestOptions = RequestOptions(path: path);

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(
      requestOptions: requestOptions,
      statusCode: statusCode,
    ),
  );
}
