import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';

void main() {
  test(
    'updateMyProfile hace PATCH a passengers/me con firstName y lastName',
    () async {
      late RequestOptions captured;
      final repository = PassengerProfileRepository(
        _dioReturning(_profileJson(), onRequest: (r) => captured = r),
      );

      final profile = await repository.updateMyProfile(
        firstName: 'Ana',
        lastName: 'Ruiz',
      );

      expect(captured.method, 'PATCH');
      expect(captured.path, 'passengers/me');
      expect(captured.data, {'firstName': 'Ana', 'lastName': 'Ruiz'});
      expect(profile.firstName, 'Ana María');
      expect(profile.lastName, 'Ruiz Pérez');
      expect(profile.ratingCount, 4);
    },
  );

  test('updateMyProfile solo con firstName manda únicamente esa clave', () async {
    late RequestOptions captured;
    final repository = PassengerProfileRepository(
      _dioReturning(_profileJson(), onRequest: (r) => captured = r),
    );

    await repository.updateMyProfile(firstName: 'Ana');

    expect(captured.data, {'firstName': 'Ana'});
    expect((captured.data as Map).containsKey('lastName'), isFalse);
  });

  test('updateMyProfile sin argumentos manda un body vacío', () async {
    late RequestOptions captured;
    final repository = PassengerProfileRepository(
      _dioReturning(_profileJson(), onRequest: (r) => captured = r),
    );

    await repository.updateMyProfile();

    expect(captured.data, <String, dynamic>{});
  });

  test('updateMyProfile lanza si el backend devuelve una respuesta vacía', () {
    final repository = PassengerProfileRepository(_dioReturning(null));

    expect(
      () => repository.updateMyProfile(firstName: 'Ana', lastName: 'Ruiz'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'mensaje',
          contains('respuesta vacía'),
        ),
      ),
    );
  });

  test('updateMyProfile propaga DioException (p. ej. 400 de validación)', () {
    final repository = PassengerProfileRepository(
      _dioRejecting(
        DioException(
          requestOptions: RequestOptions(path: 'passengers/me'),
          response: Response<void>(
            requestOptions: RequestOptions(path: 'passengers/me'),
            statusCode: 400,
          ),
        ),
      ),
    );

    expect(
      () => repository.updateMyProfile(firstName: 'A', lastName: 'B'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          400,
        ),
      ),
    );
  });
}

Map<String, dynamic> _profileJson() {
  return {
    'id': 'profile-1',
    'userId': 'user-1',
    'firstName': 'Ana María',
    'lastName': 'Ruiz Pérez',
    'photoUrl': null,
    'ratingAverage': '4.50',
    'ratingCount': 4,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-02-01T00:00:00.000Z',
  };
}

Dio _dioReturning(
  Map<String, dynamic>? responseData, {
  void Function(RequestOptions request)? onRequest,
}) {
  final dio = Dio();

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: responseData,
          ),
        );
      },
    ),
  );

  return dio;
}

Dio _dioRejecting(DioException error) {
  final dio = Dio();

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: error.response == null
                ? null
                : Response<void>(
                    requestOptions: options,
                    statusCode: error.response?.statusCode,
                  ),
            type: error.type,
          ),
        );
      },
    ),
  );

  return dio;
}
