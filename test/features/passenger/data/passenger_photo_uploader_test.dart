import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/passenger/data/passenger_photo_uploader.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Uint8List? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      lastBody = Uint8List.fromList(chunks);
    }

    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{"message":"boom"}', 500);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PassengerPhotoUploader.upload', () {
    test('hace PUT a la uploadUrl con Content-Type exacto, SIN '
        'Authorization', () async {
      final adapter = _RecordingAdapter();
      final uploader = PassengerPhotoUploader(
        dioFactory: () => Dio()..httpClientAdapter = adapter,
      );

      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      await uploader.upload(
        uploadUrl: 'https://bucket.example.com/objectKey?X-Signature=abc',
        contentType: 'image/webp',
        bytes: bytes,
      );

      final request = adapter.lastRequest!;

      expect(request.method, 'PUT');
      expect(
        request.uri.toString(),
        'https://bucket.example.com/objectKey?X-Signature=abc',
      );
      expect(request.headers['Content-Type'], 'image/webp');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(_bytesEqual(adapter.lastBody, bytes), isTrue);
    });

    test('cada llamada usa un Dio nuevo del factory (aislado)', () async {
      var factoryCalls = 0;
      final adapter = _RecordingAdapter();

      final uploader = PassengerPhotoUploader(
        dioFactory: () {
          factoryCalls += 1;
          return Dio()..httpClientAdapter = adapter;
        },
      );

      await uploader.upload(
        uploadUrl: 'https://bucket.example.com/a',
        contentType: 'image/png',
        bytes: Uint8List.fromList([1]),
      );
      await uploader.upload(
        uploadUrl: 'https://bucket.example.com/b',
        contentType: 'image/png',
        bytes: Uint8List.fromList([2]),
      );

      expect(factoryCalls, 2);
    });

    test('el Dio efímero por defecto fija timeouts propios (desviación '
        'deliberada respecto al conductor)', () {
      final dio = PassengerPhotoUploader.defaultDio();

      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.sendTimeout, const Duration(seconds: 60));
      expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    });

    test('propaga errores del PUT sin envolverlos', () async {
      final uploader = PassengerPhotoUploader(
        dioFactory: () => Dio()..httpClientAdapter = _FailingAdapter(),
      );

      await expectLater(
        uploader.upload(
          uploadUrl: 'https://bucket.example.com/objectKey',
          contentType: 'image/jpeg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}

bool _bytesEqual(Uint8List? actual, Uint8List expected) {
  if (actual == null || actual.length != expected.length) {
    return false;
  }

  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      return false;
    }
  }

  return true;
}
