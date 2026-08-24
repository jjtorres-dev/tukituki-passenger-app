import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:passenger/core/widgets/tuki_text_field.dart';
import 'package:passenger/features/passenger/data/passenger_profile_repository.dart';
import 'package:passenger/features/passenger/presentation/complete_profile_screen.dart';

void main() {
  testWidgets('formulario vacío no llama a Backend y muestra validaciones', (
    tester,
  ) async {
    final repository = _FakePassengerProfileRepository();
    final router = _router();
    addTearDown(router.dispose);

    await _pumpScreen(tester, router: router, repository: repository);

    await tester.tap(find.text('Continuar'));
    await tester.pump();

    expect(find.text('Ingresa tus nombres'), findsOneWidget);
    expect(find.text('Ingresa tus apellidos'), findsOneWidget);
    expect(repository.createMyProfileCalls, 0);
  });

  testWidgets(
    'guardado exitoso recorta espacios, llama a Backend una sola vez y '
    'vuelve al resolver de sesión (Splash) en vez de asumir Home',
    (tester) async {
      final repository = _FakePassengerProfileRepository();
      final router = _router();
      addTearDown(router.dispose);

      await _pumpScreen(tester, router: router, repository: repository);

      await tester.enterText(
        fieldWithLabel('Nombres'),
        '  Juan  ',
      );
      await tester.enterText(
        fieldWithLabel('Apellidos'),
        '  Pérez  ',
      );

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(repository.createMyProfileCalls, 1);
      expect(repository.lastFirstName, 'Juan');
      expect(repository.lastLastName, 'Pérez');
      expect(router.routeInformationProvider.value.uri.path, '/splash');
    },
  );

  testWidgets(
    'mientras la solicitud está en curso, el botón queda deshabilitado '
    '(sin doble envío)',
    (tester) async {
      final repository = _FakePassengerProfileRepository()..holdResponse();
      final router = _router();
      addTearDown(router.dispose);

      await _pumpScreen(tester, router: router, repository: repository);

      await tester.enterText(
        fieldWithLabel('Nombres'),
        'Juan',
      );
      await tester.enterText(
        fieldWithLabel('Apellidos'),
        'Pérez',
      );

      await tester.tap(find.text('Continuar'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.createMyProfileCalls, 1);

      repository.release();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    '409 (perfil ya existe, p.ej. doble envío) también vuelve al '
    'resolver de sesión, sin mostrar error',
    (tester) async {
      final repository = _FakePassengerProfileRepository(
        error: _dioHttpError('passengers/me', 409),
      );
      final router = _router();
      addTearDown(router.dispose);

      await _pumpScreen(tester, router: router, repository: repository);

      await tester.enterText(
        fieldWithLabel('Nombres'),
        'Juan',
      );
      await tester.enterText(
        fieldWithLabel('Apellidos'),
        'Pérez',
      );

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/splash');
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('400 muestra mensaje amigable y permanece en la pantalla', (
    tester,
  ) async {
    final repository = _FakePassengerProfileRepository(
      error: _dioHttpError('passengers/me', 400),
    );
    final router = _router();
    addTearDown(router.dispose);

    await _pumpScreen(tester, router: router, repository: repository);

    await tester.enterText(
      fieldWithLabel('Nombres'),
      'Juan',
    );
    await tester.enterText(
      fieldWithLabel('Apellidos'),
      'Pérez',
    );

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Revisa los datos ingresados.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/complete-profile');
  });

  testWidgets(
    'error de red muestra mensaje amigable, nunca la excepción cruda',
    (tester) async {
      final repository = _FakePassengerProfileRepository(
        error: DioException(
          requestOptions: RequestOptions(path: 'passengers/me'),
          type: DioExceptionType.connectionError,
          error: StateError('offline'),
        ),
      );
      final router = _router();
      addTearDown(router.dispose);

      await _pumpScreen(tester, router: router, repository: repository);

      await tester.enterText(
        fieldWithLabel('Nombres'),
        'Juan',
      );
      await tester.enterText(
        fieldWithLabel('Apellidos'),
        'Pérez',
      );

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo conectar con TukiTuki.'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/complete-profile',
      );
    },
  );

  testWidgets('CompleteProfile no desborda en tamaños Passenger aprobados', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      tester.view.physicalSize = size;

      await tester.pumpWidget(_buildCompleteProfile());

      expect(find.text('Cuéntanos quién eres'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'CTA es alcanzable con teclado en tamaños Passenger aprobados '
    '(header se comprime a su mínimo, la hoja hace scroll)',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      for (final size in [const Size(360, 640), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.viewInsets = const FakeViewPadding();

        await tester.pumpWidget(_buildCompleteProfile());
        await tester.ensureVisible(fieldWithLabel('Apellidos'));
        await tester.tap(fieldWithLabel('Apellidos'));
        await tester.pump();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Continuar'));
        await tester.pumpAndSettle();

        final cta = find.text('Continuar');
        final ctaRect = tester.getRect(cta);
        final keyboardTop = size.height - 300;

        expect(cta, findsOneWidget);
        expect(ctaRect.top, greaterThanOrEqualTo(0));
        expect(ctaRect.bottom, lessThanOrEqualTo(keyboardTop));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

/// `passengerProfileRepositoryProvider` no se lee durante `build()` —
/// solo dentro de `_save()`, al tocar "Continuar" con datos válidos —
/// así que estos dos tests (que solo verifican layout/overflow, sin
/// llegar a guardar) no necesitan overridearlo con un fake.
Widget _buildCompleteProfile() {
  return const ProviderScope(child: MaterialApp(home: CompleteProfileScreen()));
}

class _FakePassengerProfileRepository extends PassengerProfileRepository {
  _FakePassengerProfileRepository({this.error}) : super(Dio());

  final Object? error;
  int createMyProfileCalls = 0;
  String? lastFirstName;
  String? lastLastName;

  Completer<void>? _hold;

  void holdResponse() {
    _hold = Completer<void>();
  }

  void release() {
    _hold?.complete();
  }

  @override
  Future<Map<String, dynamic>> createMyProfile({
    required String firstName,
    required String lastName,
  }) async {
    createMyProfileCalls++;
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

    return {'id': 'profile-1', 'firstName': firstName, 'lastName': lastName};
  }
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/complete-profile',
    routes: [
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) =>
            const Scaffold(body: Text('SPLASH_DESTINATION')),
      ),
    ],
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required GoRouter router,
  required PassengerProfileRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        passengerProfileRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();
}

/// `TukiTextField` no pone la etiqueta dentro del campo — es un
/// `Text` hermano que lo precede (`_FieldLabel` en
/// `complete_profile_screen.dart`), así que
/// `find.widgetWithText(TextFormField, label)` ya no encuentra nada
/// (mismo ajuste que en `register_screen_test.dart`). En vez de la
/// etiqueta, este finder ubica el campo por su `hintText`, una
/// propiedad propia y estable del widget.
Finder fieldWithLabel(String label) {
  final hintText = switch (label) {
    'Nombres' => 'Juan José',
    'Apellidos' => 'Torres Solano',
    _ => throw ArgumentError.value(label, 'label', 'Sin hint mapeado'),
  };

  return find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is TukiTextField && widget.hintText == hintText,
    ),
    matching: find.byType(TextFormField),
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
