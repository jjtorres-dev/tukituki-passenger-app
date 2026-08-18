import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:passenger/features/auth/data/auth_repository.dart';
import 'package:passenger/features/auth/domain/public_user.dart';
import 'package:passenger/features/auth/presentation/splash_screen.dart';
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        passengerProfileRepositoryProvider.overrideWithValue(profileRepository),
        rideRepositoryProvider.overrideWithValue(rideRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pump(const Duration(milliseconds: 801));
  await _flushSplash(tester);
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
