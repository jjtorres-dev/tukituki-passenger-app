import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/passenger/data/passenger_storage_repository.dart';

/// Adapter con respuestas guionizadas por path, mismo patrón sin
/// librerías de mocking que el test equivalente del conductor.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final Map<String, (int, Object?)> responses;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    final scripted = responses[options.path];

    if (scripted == null) {
      throw StateError('Sin respuesta configurada para ${options.path}');
    }

    final (statusCode, data) = scripted;

    return ResponseBody.fromString(
      data == null ? '' : jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PassengerStorageRepository.presignProfilePhotoUpload', () {
    test('envía la categoría hardcodeada + contentType/fileSize y parsea '
        'la respuesta', () async {
      final adapter = _ScriptedAdapter({
        'storage/uploads/presign': (
          200,
          {
            'objectKey': 'passengers/profile-1/profile/abc.jpg',
            'uploadUrl': 'https://bucket.example.com/put-url',
            'expiresAt': '2026-09-03T12:00:00.000Z',
            'requiredHeaders': {'Content-Type': 'image/jpeg'},
          },
        ),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = PassengerStorageRepository(dio);

      final result = await repository.presignProfilePhotoUpload(
        contentType: 'image/jpeg',
        fileSize: 204800,
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(body['category'], 'PASSENGER_PROFILE_PHOTO');
      expect(body['contentType'], 'image/jpeg');
      expect(body['fileSize'], 204800);
      expect(result.objectKey, 'passengers/profile-1/profile/abc.jpg');
      expect(result.uploadUrl, 'https://bucket.example.com/put-url');
      expect(result.contentType, 'image/jpeg');
    });

    test('respuesta inválida (sin objectKey) lanza', () async {
      final adapter = _ScriptedAdapter({
        'storage/uploads/presign': (200, {'uploadUrl': 'https://x'}),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = PassengerStorageRepository(dio);

      await expectLater(
        repository.presignProfilePhotoUpload(
          contentType: 'image/jpeg',
          fileSize: 100,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('propaga 400 (mime/tamaño rechazado) sin envolverlo', () async {
      final adapter = _ScriptedAdapter({
        'storage/uploads/presign': (400, {'message': 'no permitido'}),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = PassengerStorageRepository(dio);

      await expectLater(
        repository.presignProfilePhotoUpload(
          contentType: 'image/jpeg',
          fileSize: 100,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('PassengerStorageRepository.completeProfilePhotoUpload', () {
    test('envía la categoría hardcodeada + objectKey reales', () async {
      final adapter = _ScriptedAdapter({
        'storage/uploads/complete': (
          200,
          {
            'category': 'PASSENGER_PROFILE_PHOTO',
            'objectKey': 'passengers/profile-1/profile/abc.jpg',
            'completedAt': '2026-09-03T12:00:05.000Z',
          },
        ),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = PassengerStorageRepository(dio);

      await repository.completeProfilePhotoUpload(
        objectKey: 'passengers/profile-1/profile/abc.jpg',
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(body['category'], 'PASSENGER_PROFILE_PHOTO');
      expect(body['objectKey'], 'passengers/profile-1/profile/abc.jpg');
    });

    test('propaga error sin envolverlo', () async {
      final adapter = _ScriptedAdapter({
        'storage/uploads/complete': (400, {'message': 'boom'}),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = PassengerStorageRepository(dio);

      await expectLater(
        repository.completeProfilePhotoUpload(objectKey: 'passengers/x.jpg'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
