import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/passenger/domain/passenger_profile.dart';

void main() {
  test('parsea un JSON completo del backend', () {
    final profile = PassengerProfile.fromJson({
      'id': 'profile-1',
      'userId': 'user-1',
      'firstName': 'Juan José',
      'lastName': 'Torres Solano',
      'email': 'juan@example.com',
      'phoneE164': '+51987654321',
      'photoUrl': null,
      'emergencyContactName': null,
      'ratingAverage': '4.85',
      'ratingCount': 12,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-02-01T00:00:00.000Z',
    });

    expect(profile.firstName, 'Juan José');
    expect(profile.lastName, 'Torres Solano');
    expect(profile.email, 'juan@example.com');
    expect(profile.phoneE164, '+51987654321');
    expect(profile.ratingAverage, 4.85);
    expect(profile.ratingCount, 12);
    expect(profile.hasRating, isTrue);
  });

  test('email ausente en el JSON ⇒ null', () {
    final profile = PassengerProfile.fromJson({
      'firstName': 'Ana',
      'lastName': 'Ruiz',
    });

    expect(profile.email, isNull);
  });

  test('email: null en el JSON ⇒ null', () {
    final profile = PassengerProfile.fromJson({'email': null});

    expect(profile.email, isNull);
  });

  test('email no-string en el JSON ⇒ null, sin lanzar', () {
    final profile = PassengerProfile.fromJson({'email': 123});

    expect(profile.email, isNull);
  });

  test('phoneE164 ausente ⇒ cadena vacía, sin lanzar', () {
    final profile = PassengerProfile.fromJson({'firstName': 'Ana'});

    expect(profile.phoneE164, '');
  });

  test('ratingCount > 0 ⇒ hasRating true; == 0 ⇒ false', () {
    expect(
      PassengerProfile.fromJson({'ratingCount': 1}).hasRating,
      isTrue,
    );
    expect(
      PassengerProfile.fromJson({'ratingCount': 0}).hasRating,
      isFalse,
    );
  });

  test('ratingAverage ausente o no numérico cae a 0.0 sin lanzar', () {
    expect(PassengerProfile.fromJson({}).ratingAverage, 0.0);
    expect(
      PassengerProfile.fromJson({'ratingAverage': 'n/a'}).ratingAverage,
      0.0,
    );
    expect(
      PassengerProfile.fromJson({'ratingAverage': null}).ratingAverage,
      0.0,
    );
  });

  test('ratingAverage acepta num directo (no solo string)', () {
    expect(
      PassengerProfile.fromJson({'ratingAverage': 4.5}).ratingAverage,
      4.5,
    );
    expect(
      PassengerProfile.fromJson({'ratingAverage': 5}).ratingAverage,
      5.0,
    );
  });

  test('ratingCount ausente o no numérico cae a 0', () {
    expect(PassengerProfile.fromJson({}).ratingCount, 0);
    expect(
      PassengerProfile.fromJson({'ratingCount': 'x'}).ratingCount,
      0,
    );
  });

  test('ratingCount acepta string numérico y num', () {
    expect(
      PassengerProfile.fromJson({'ratingCount': '7'}).ratingCount,
      7,
    );
    expect(
      PassengerProfile.fromJson({'ratingCount': 3.0}).ratingCount,
      3,
    );
  });

  test('firstName/lastName ausentes caen a cadena vacía, sin lanzar', () {
    final profile = PassengerProfile.fromJson({'ratingCount': 0});

    expect(profile.firstName, '');
    expect(profile.lastName, '');
  });

  test('ignora campos desconocidos sin romper', () {
    final profile = PassengerProfile.fromJson({
      'firstName': 'Ana',
      'lastName': 'Ruiz',
      'ratingAverage': '3.00',
      'ratingCount': 2,
      'algoNuevoDelBackend': {'x': 1},
      'otroCampo': [1, 2, 3],
    });

    expect(profile.firstName, 'Ana');
    expect(profile.ratingCount, 2);
  });
}
