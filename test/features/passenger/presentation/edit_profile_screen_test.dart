import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/core/widgets/tuki_text_field.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';
import 'package:passenger/features/passenger/domain/passenger_profile.dart';
import 'package:passenger/features/passenger/presentation/edit_profile_screen.dart';

void main() {
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
      expect(harness.popped, isTrue);
      expect(harness.result, isA<PassengerProfile>());
      expect(harness.result!.firstName, 'Ana María');
      expect(find.byType(EditProfileScreen), findsNothing);
    },
  );

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
}) async {
  final harness = _Harness();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        passengerProfileRepositoryProvider.overrideWithValue(repository),
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
  _FakeRepo({this.error}) : super(Dio());

  final Object? error;
  int calls = 0;
  String? lastFirstName;
  String? lastLastName;

  Completer<void>? _hold;

  void hold() => _hold = Completer<void>();
  void release() => _hold?.complete();

  @override
  Future<PassengerProfile> updateMyProfile({
    String? firstName,
    String? lastName,
  }) async {
    calls++;
    lastFirstName = firstName;
    lastLastName = lastName;

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
      ratingAverage: 4.5,
      ratingCount: 3,
    );
  }
}
