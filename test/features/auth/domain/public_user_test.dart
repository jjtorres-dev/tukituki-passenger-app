import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/auth/domain/public_user.dart';

void main() {
  test('PublicUser parsea isPhoneVerified false sin excepción', () {
    final user = PublicUser.fromJson({
      'id': 'user-1',
      'phoneE164': '+51999999999',
      'roles': ['PASSENGER'],
      'status': 'ACTIVE',
      'isPhoneVerified': false,
      'createdAt': '2026-08-10T12:00:00.000Z',
    });

    expect(user.isPhoneVerified, isFalse);
    expect(user.roles, ['PASSENGER']);
    expect(user.status, 'ACTIVE');
  });
}
