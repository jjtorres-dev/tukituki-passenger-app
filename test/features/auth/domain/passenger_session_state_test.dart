import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/auth/domain/passenger_session_state.dart';

void main() {
  group('resolvePassengerSessionState', () {
    test('sin perfil y sin ride activo -> identityRequired', () {
      final state = resolvePassengerSessionState(hasProfile: false);

      expect(state.kind, PassengerSessionKind.identityRequired);
      expect(state.activeRideId, isNull);
    });

    test('con perfil y sin ride activo -> ready sin rideId', () {
      final state = resolvePassengerSessionState(hasProfile: true);

      expect(state.kind, PassengerSessionKind.ready);
      expect(state.activeRideId, isNull);
    });

    test(
      'sin perfil PERO con ride activo -> ready con rideId '
      '(el viaje activo prioriza sobre el gate de identidad)',
      () {
        final state = resolvePassengerSessionState(
          hasProfile: false,
          activeRideId: 'ride-1',
        );

        expect(state.kind, PassengerSessionKind.ready);
        expect(state.activeRideId, 'ride-1');
      },
    );

    test('con perfil y con ride activo -> ready con rideId', () {
      final state = resolvePassengerSessionState(
        hasProfile: true,
        activeRideId: 'ride-1',
      );

      expect(state.kind, PassengerSessionKind.ready);
      expect(state.activeRideId, 'ride-1');
    });
  });

  group('routeForPassengerSessionState', () {
    test('identityRequired -> /complete-profile', () {
      const state = PassengerSessionState.identityRequired();

      expect(routeForPassengerSessionState(state), '/complete-profile');
    });

    test('ready sin rideId -> /home', () {
      const state = PassengerSessionState.ready();

      expect(routeForPassengerSessionState(state), '/home');
    });

    test('ready con rideId -> /ride/:id', () {
      const state = PassengerSessionState.ready(activeRideId: 'ride-42');

      expect(routeForPassengerSessionState(state), '/ride/ride-42');
    });
  });
}
