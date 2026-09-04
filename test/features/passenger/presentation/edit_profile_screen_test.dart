import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/core/widgets/tuki_text_field.dart';
import 'package:passenger/features/passenger/data/passenger_photo_uploader.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';
import 'package:passenger/features/passenger/data/passenger_storage_repository.dart';
import 'package:passenger/features/passenger/domain/passenger_profile.dart';
import 'package:passenger/features/passenger/presentation/edit_profile_screen.dart';
import 'package:passenger/features/passenger/presentation/passenger_avatar.dart';
import 'package:passenger/features/passenger/presentation/profile_photo_picker.dart';

void main() {
  setUp(() => profilePhotoPickerOverride = null);
  tearDown(() => profilePhotoPickerOverride = null);

  testWidgets('renderiza con los nombres precargados', (tester) async {
    final harness = await _pump(tester, repository: _FakeRepo());

    expect(
      tester.widget<TextFormField>(_field('Juan José')).controller!.text,
      'Ana',
    );
    expect(
      tester.widget<TextFormField>(_field('Torres Solano')).controller!.text,
      'Ruiz',
    );
    expect(harness.popped, isFalse);
  });

  testWidgets('renderiza el correo precargado', (tester) async {
    await _pump(tester, repository: _FakeRepo(), email: 'ana@ejemplo.com');

    expect(
      tester.widget<TextFormField>(_field('juan@ejemplo.com')).controller!.text,
      'ana@ejemplo.com',
    );
  });

  testWidgets(
    'la fila de teléfono muestra el número y no es un campo editable',
    (tester) async {
      await _pump(
        tester,
        repository: _FakeRepo(),
        phoneE164: '+51955555555',
      );

      expect(find.text('+51955555555'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // Solo hay 3 campos de texto reales: nombres, apellidos, correo.
      // El teléfono NO es un TukiTextField.
      expect(find.byType(TukiTextField), findsNWidgets(3));
    },
  );

  testWidgets(
    'campo vacío deshabilita el botón, muestra la nota y no llama a la red',
    (tester) async {
      final repository = _FakeRepo();
      await _pump(tester, repository: repository);

      await tester.enterText(_field('Juan José'), '');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('2 a 80 caracteres'),
        findsOneWidget,
      );

      // Tocarlo igual no dispara nada.
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pump();
      expect(repository.calls, 0);
    },
  );

  testWidgets(
    'correo con formato inválido deshabilita el botón y no llama a la red',
    (tester) async {
      final repository = _FakeRepo();
      await _pump(tester, repository: repository);

      await tester.enterText(_field('juan@ejemplo.com'), 'no-es-un-correo');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('edit-profile-save-button')),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('formato'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pump();
      expect(repository.calls, 0);
    },
  );

  testWidgets(
    'guardado válido recorta espacios, llama una sola vez y hace pop con el '
    'perfil devuelto',
    (tester) async {
      final repository = _FakeRepo();
      final harness = await _pump(tester, repository: repository);

      await tester.enterText(_field('Juan José'), '  Ana María  ');
      await tester.enterText(_field('Torres Solano'), '  Ruiz Pérez  ');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(repository.lastFirstName, 'Ana María');
      expect(repository.lastLastName, 'Ruiz Pérez');
      // El correo no se tocó → el parámetro `email` no se pasa.
      expect(repository.emailPassed, isFalse);
      expect(harness.popped, isTrue);
      expect(harness.result, isA<PassengerProfile>());
      expect(harness.result!.firstName, 'Ana María');
      expect(find.byType(EditProfileScreen), findsNothing);
    },
  );

  testWidgets('editar solo el correo y guardar → updateMyProfile con el '
      'valor nuevo', (tester) async {
    final repository = _FakeRepo();
    final harness = await _pump(tester, repository: repository);

    await tester.enterText(_field('juan@ejemplo.com'), 'nuevo@x.com');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.emailPassed, isTrue);
    expect(repository.lastEmail, 'nuevo@x.com');
    expect(harness.popped, isTrue);
  });

  testWidgets('borrar un correo que tenía valor y guardar → updateMyProfile '
      'con email: null', (tester) async {
    final repository = _FakeRepo();
    final harness = await _pump(
      tester,
      repository: repository,
      email: 'viejo@x.com',
    );

    await tester.enterText(_field('juan@ejemplo.com'), '');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.emailPassed, isTrue);
    expect(repository.lastEmail, isNull);
    expect(harness.popped, isTrue);
  });

  testWidgets('cambiar solo el nombre (correo intacto) → updateMyProfile SIN '
      'el parámetro email', (tester) async {
    final repository = _FakeRepo();
    await _pump(tester, repository: repository, email: 'ana@x.com');

    await tester.enterText(_field('Juan José'), 'Nuevo Nombre');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.emailPassed, isFalse);
  });

  testWidgets('guardar sin cambios hace pop(null) sin tocar la red', (
    tester,
  ) async {
    final repository = _FakeRepo();
    final harness = await _pump(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(harness.popped, isTrue);
    expect(harness.result, isNull);
  });

  testWidgets(
    'correo vacío desde el inicio sin otros cambios → pop(null) sin red',
    (tester) async {
      final repository = _FakeRepo();
      final harness = await _pump(tester, repository: repository, email: null);

      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(repository.calls, 0);
      expect(harness.popped, isTrue);
      expect(harness.result, isNull);
    },
  );

  testWidgets('mientras guarda, el botón queda deshabilitado (sin doble envío)', (
    tester,
  ) async {
    final repository = _FakeRepo()..hold();
    await _pump(tester, repository: repository);

    await tester.enterText(_field('Juan José'), 'Nuevo');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('edit-profile-save-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.calls, 1);

    repository.release();
    await tester.pumpAndSettle();
  });

  testWidgets('400 muestra "Revisa los datos ingresados." y no navega', (
    tester,
  ) async {
    final repository = _FakeRepo(error: _dioHttpError(400));
    final harness = await _pump(tester, repository: repository);

    await tester.enterText(_field('Juan José'), 'Nuevo');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Revisa los datos ingresados.'), findsOneWidget);
    expect(harness.popped, isFalse);
    expect(find.byType(EditProfileScreen), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('edit-profile-save-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('404 muestra "No encontramos tu perfil." y no navega', (
    tester,
  ) async {
    final repository = _FakeRepo(error: _dioHttpError(404));
    final harness = await _pump(tester, repository: repository);

    await tester.enterText(_field('Juan José'), 'Nuevo');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('No encontramos tu perfil.'), findsOneWidget);
    expect(harness.popped, isFalse);
  });

  testWidgets(
    'error de red muestra "No se pudo conectar con TukiTuki." y no navega',
    (tester) async {
      final repository = _FakeRepo(
        error: DioException(
          requestOptions: RequestOptions(path: 'passengers/me'),
          type: DioExceptionType.connectionError,
          error: StateError('offline'),
        ),
      );
      final harness = await _pump(tester, repository: repository);

      await tester.enterText(_field('Juan José'), 'Nuevo');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('edit-profile-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo conectar con TukiTuki.'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(harness.popped, isFalse);
    },
  );

  testWidgets('volver con la flecha hace pop sin resultado', (tester) async {
    final repository = _FakeRepo();
    final harness = await _pump(tester, repository: repository);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
    expect(harness.popped, isTrue);
    expect(harness.result, isNull);
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  // --- Sub-etapa 2b: foto de perfil -----------------------------------

  testWidgets('subir foto con éxito: presign+PUT+complete, refetch, el '
      'avatar toma la URL nueva y el spinner desaparece', (tester) async {
    final repository = _FakeRepo(
      refreshedPhotoUrl: 'https://cdn.example/nueva.jpg',
    );
    final storage = _FakeStorageRepo();
    final uploader = _FakeUploader();

    profilePhotoPickerOverride = (source) async => PickedProfilePhoto(
      bytes: _validPngBytes(),
      contentType: 'image/png',
    );

    final harness = await _pump(
      tester,
      repository: repository,
      storage: storage,
      uploader: uploader,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pumpAndSettle();

    expect(storage.presignCalls, 1);
    expect(storage.lastContentType, 'image/png');
    expect(storage.lastFileSize, _validPngBytes().length);
    expect(uploader.uploadCalls, 1);
    expect(storage.completeCalls, 1);
    expect(repository.getCalls, 1);

    final avatar = tester.widget<PassengerAvatar>(
      find.byType(PassengerAvatar),
    );
    expect(avatar.photoUrl, 'https://cdn.example/nueva.jpg');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.popped, isFalse);

    // El botón pasó de "Agregar foto" a "Cambiar foto".
    expect(find.text('Cambiar foto'), findsOneWidget);
  });

  testWidgets('cancelar el picker (devuelve null): no toca red ni muestra '
      'error', (tester) async {
    final storage = _FakeStorageRepo();
    final uploader = _FakeUploader();

    profilePhotoPickerOverride = (source) async => null;

    await _pump(
      tester,
      repository: _FakeRepo(),
      storage: storage,
      uploader: uploader,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-gallery')),
    );
    await tester.pumpAndSettle();

    expect(storage.presignCalls, 0);
    expect(uploader.uploadCalls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('foto'),
      findsWidgets, // solo el botón "Agregar foto", ningún mensaje de error
    );
    expect(find.text('Elige una foto en formato JPG, PNG o WEBP.'), findsNothing);
  });

  testWidgets('formato no soportado: muestra el mensaje de error y no sube', (
    tester,
  ) async {
    final storage = _FakeStorageRepo();
    final uploader = _FakeUploader();

    profilePhotoPickerOverride = (source) async =>
        throw const ProfilePhotoUnsupportedFormatException();

    await _pump(
      tester,
      repository: _FakeRepo(),
      storage: storage,
      uploader: uploader,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Elige una foto en formato JPG, PNG o WEBP.'),
      findsOneWidget,
    );
    expect(storage.presignCalls, 0);
    expect(uploader.uploadCalls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('presign 400: mensaje "demasiado grande"', (tester) async {
    final storage = _FakeStorageRepo(presignError: _presignBadRequest());

    profilePhotoPickerOverride = (source) async => PickedProfilePhoto(
      bytes: _validPngBytes(),
      contentType: 'image/jpeg',
    );

    await _pump(tester, repository: _FakeRepo(), storage: storage);

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('La foto es demasiado grande. Prueba con otra.'),
      findsOneWidget,
    );
  });

  testWidgets('el PUT al bucket falla: mensaje genérico de subida', (
    tester,
  ) async {
    final storage = _FakeStorageRepo();
    final uploader = _FakeUploader(
      error: DioException(
        requestOptions: RequestOptions(path: 'https://bucket.example.com/put'),
        type: DioExceptionType.sendTimeout,
      ),
    );

    profilePhotoPickerOverride = (source) async => PickedProfilePhoto(
      bytes: _validPngBytes(),
      contentType: 'image/jpeg',
    );

    await _pump(
      tester,
      repository: _FakeRepo(),
      storage: storage,
      uploader: uploader,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pumpAndSettle();

    expect(storage.presignCalls, 1);
    expect(uploader.uploadCalls, 1);
    expect(storage.completeCalls, 0);
    expect(
      find.text('No pudimos subir tu foto. Inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('removeMyPhoto falla: mensaje de error, el avatar se mantiene', (
    tester,
  ) async {
    final repository = _FakeRepo(
      removeError: StateError('boom'),
    );

    await _pump(
      tester,
      repository: repository,
      photoUrl: 'https://cdn.example/actual.jpg',
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-remove')),
    );
    await tester.pumpAndSettle();

    expect(repository.removeCalls, 1);
    expect(
      find.text('No pudimos quitar tu foto. Inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(
      tester.widget<PassengerAvatar>(find.byType(PassengerAvatar)).photoUrl,
      'https://cdn.example/actual.jpg',
    );
  });

  testWidgets('quitar foto: llama a removeMyPhoto, el avatar vuelve al '
      'ícono genérico y devuelve el perfil por pop', (tester) async {
    final repository = _FakeRepo();

    final harness = await _pump(
      tester,
      repository: repository,
      photoUrl: 'https://cdn.example/actual.jpg',
    );

    // Con foto cargada el avatar arranca con esa URL.
    expect(
      tester.widget<PassengerAvatar>(find.byType(PassengerAvatar)).photoUrl,
      'https://cdn.example/actual.jpg',
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-remove')),
    );
    await tester.pumpAndSettle();

    expect(repository.removeCalls, 1);
    expect(
      tester.widget<PassengerAvatar>(find.byType(PassengerAvatar)).photoUrl,
      isNull,
    );
    expect(find.byIcon(Icons.person), findsOneWidget);

    // Al volver con la flecha, el perfil fresco viaja por el pop.
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(harness.result, isA<PassengerProfile>());
    expect(harness.result!.photoUrl, isNull);
  });

  testWidgets('"Quitar foto" NO aparece en la hoja si no hay foto cargada', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepo()); // sin photoUrl

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('edit-profile-photo-sheet-remove')),
      findsNothing,
    );
  });

  testWidgets('doble toque mientras sube: no dispara una segunda subida', (
    tester,
  ) async {
    final storage = _FakeStorageRepo();
    final uploader = _FakeUploader();

    final gate = Completer<PickedProfilePhoto?>();
    var pickCalls = 0;
    profilePhotoPickerOverride = (source) {
      pickCalls += 1;
      return gate.future;
    };

    await _pump(
      tester,
      repository: _FakeRepo(),
      storage: storage,
      uploader: uploader,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pump(); // arranca la subida: _uploadingPhoto = true

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // El disparador está deshabilitado: tocarlo otra vez no hace nada.
    final trigger = tester.widget<TextButton>(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    expect(trigger.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(pickCalls, 1);

    // Se libera la selección con un cancel para cerrar el flujo limpio.
    gate.complete(null);
    await tester.pumpAndSettle();
    expect(storage.presignCalls, 0);
  });

  testWidgets('tocar el avatar con foto abre el visor ampliado; la X lo '
      'cierra', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepo(),
      photoUrl: 'https://cdn.example/actual.jpg',
    );

    expect(
      find.byKey(const ValueKey('edit-profile-photo-viewer')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-avatar-tap')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('edit-profile-photo-viewer')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-viewer-close')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('edit-profile-photo-viewer')),
      findsNothing,
    );
  });

  testWidgets('tocar el avatar SIN foto no hace nada (no hay zona de tap ni '
      'visor)', (tester) async {
    await _pump(tester, repository: _FakeRepo()); // sin photoUrl

    expect(
      find.byKey(const ValueKey('edit-profile-photo-avatar-tap')),
      findsNothing,
    );

    await tester.tap(
      find.byType(PassengerAvatar),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('edit-profile-photo-viewer')),
      findsNothing,
    );
  });

  testWidgets('tocar el avatar mientras sube (con foto previa) no abre el '
      'visor', (tester) async {
    final storage = _FakeStorageRepo();

    final gate = Completer<PickedProfilePhoto?>();
    profilePhotoPickerOverride = (source) => gate.future;

    await _pump(
      tester,
      repository: _FakeRepo(),
      storage: storage,
      photoUrl: 'https://cdn.example/actual.jpg',
    );

    // Arranca una subida: _uploadingPhoto = true.
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-trigger')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('edit-profile-photo-sheet-camera')),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // El wrapper tocable se retira mientras sube.
    expect(
      find.byKey(const ValueKey('edit-profile-photo-avatar-tap')),
      findsNothing,
    );

    await tester.tap(
      find.byType(PassengerAvatar),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('edit-profile-photo-viewer')),
      findsNothing,
    );

    gate.complete(null);
    await tester.pumpAndSettle();
  });
}

Finder _field(String hint) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is TukiTextField && widget.hintText == hint,
  ),
  matching: find.byType(TextFormField),
);

class _Harness {
  bool popped = false;
  PassengerProfile? result;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required PassengerProfileRepository repository,
  String firstName = 'Ana',
  String lastName = 'Ruiz',
  String? email,
  String phoneE164 = '+51987654321',
  String? photoUrl,
  PassengerStorageRepository? storage,
  PassengerPhotoUploader? uploader,
}) async {
  final harness = _Harness();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        passengerProfileRepositoryProvider.overrideWithValue(repository),
        passengerStorageRepositoryProvider.overrideWithValue(
          storage ?? _FakeStorageRepo(),
        ),
        passengerPhotoUploaderProvider.overrideWithValue(
          uploader ?? _FakeUploader(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  harness.result = await Navigator.of(context)
                      .push<PassengerProfile>(
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            initialFirstName: firstName,
                            initialLastName: lastName,
                            initialEmail: email,
                            initialPhoneE164: phoneE164,
                            initialPhotoUrl: photoUrl,
                          ),
                        ),
                      );
                  harness.popped = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();

  return harness;
}

Uint8List _validPngBytes() => Uint8List.fromList(const [1, 2, 3, 4, 5]);

class _FakeStorageRepo extends PassengerStorageRepository {
  _FakeStorageRepo({this.presignError}) : super(Dio());

  Object? presignError;

  int presignCalls = 0;
  int completeCalls = 0;
  String? lastContentType;
  int? lastFileSize;

  @override
  Future<PassengerPresignedUpload> presignProfilePhotoUpload({
    required String contentType,
    required int fileSize,
  }) async {
    presignCalls += 1;
    lastContentType = contentType;
    lastFileSize = fileSize;

    if (presignError case final e?) {
      throw e;
    }

    return const PassengerPresignedUpload(
      objectKey: 'passengers/profile-1/profile/abc.jpg',
      uploadUrl: 'https://bucket.example.com/put',
      contentType: 'image/jpeg',
    );
  }

  @override
  Future<void> completeProfilePhotoUpload({required String objectKey}) async {
    completeCalls += 1;
  }
}

class _FakeUploader extends PassengerPhotoUploader {
  _FakeUploader({this.error});

  Object? error;
  int uploadCalls = 0;

  @override
  Future<void> upload({
    required String uploadUrl,
    required String contentType,
    required Uint8List bytes,
  }) async {
    uploadCalls += 1;

    if (error case final e?) {
      throw e;
    }
  }
}

DioException _presignBadRequest() {
  final options = RequestOptions(path: 'storage/uploads/presign');

  return DioException(
    requestOptions: options,
    response: Response<void>(requestOptions: options, statusCode: 400),
  );
}

DioException _dioHttpError(int statusCode) {
  final requestOptions = RequestOptions(path: 'passengers/me');

  return DioException(
    requestOptions: requestOptions,
    response: Response<void>(
      requestOptions: requestOptions,
      statusCode: statusCode,
    ),
  );
}

class _FakeRepo extends PassengerProfileRepository {
  _FakeRepo({
    this.error,
    this.refreshedPhotoUrl = 'https://cdn.example/photo-nueva.jpg',
    this.removeError,
  }) : super(Dio());

  /// Centinela propio del fake para distinguir "no se pasó `email`" de
  /// "se pasó `email: null`" — mismo motivo que el centinela real del
  /// repositorio.
  static const Object _notPassed = Object();

  final Object? error;

  /// `photoUrl` que devuelve `getMyProfile()` — simula lo que el
  /// backend resuelve tras un `complete` exitoso.
  final String? refreshedPhotoUrl;

  /// Error a lanzar desde `removeMyPhoto()`, si se configura.
  final Object? removeError;

  int calls = 0;
  int getCalls = 0;
  int removeCalls = 0;
  String? lastFirstName;
  String? lastLastName;

  bool emailPassed = false;
  Object? lastEmail;

  Completer<void>? _hold;

  void hold() => _hold = Completer<void>();
  void release() => _hold?.complete();

  @override
  Future<Map<String, dynamic>?> getMyProfile() async {
    getCalls++;
    return {
      'firstName': 'Ana',
      'lastName': 'Ruiz',
      'email': null,
      'phoneE164': '+51987654321',
      'photoUrl': refreshedPhotoUrl,
      'ratingAverage': '4.50',
      'ratingCount': 3,
    };
  }

  @override
  Future<PassengerProfile> removeMyPhoto() async {
    removeCalls++;

    final e = removeError;
    if (e != null) {
      throw e;
    }

    return const PassengerProfile(
      firstName: 'Ana',
      lastName: 'Ruiz',
      email: null,
      phoneE164: '+51987654321',
      photoUrl: null,
      ratingAverage: 4.5,
      ratingCount: 3,
    );
  }

  @override
  Future<PassengerProfile> updateMyProfile({
    String? firstName,
    String? lastName,
    Object? email = _notPassed,
  }) async {
    calls++;
    lastFirstName = firstName;
    lastLastName = lastName;
    emailPassed = !identical(email, _notPassed);
    lastEmail = emailPassed ? email : null;

    final hold = _hold;
    if (hold != null) {
      await hold.future;
    }

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    return PassengerProfile(
      firstName: firstName ?? 'Ana',
      lastName: lastName ?? 'Ruiz',
      email: emailPassed ? email as String? : null,
      phoneE164: '+51987654321',
      photoUrl: null,
      ratingAverage: 4.5,
      ratingCount: 3,
    );
  }
}
