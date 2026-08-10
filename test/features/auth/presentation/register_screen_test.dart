import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:passenger/features/auth/data/auth_repository.dart';
import 'package:passenger/features/auth/presentation/register_screen.dart';

void main() {
  Widget buildRegister() {
    return const ProviderScope(child: MaterialApp(home: RegisterScreen()));
  }

  Finder fieldWithLabel(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
  }

  testWidgets('Register renderiza branding, formulario único y términos', (
    tester,
  ) async {
    await tester.pumpWidget(buildRegister());

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/tukituki_logo.png',
      ),
      findsOneWidget,
    );
    expect(find.text('Crea tu cuenta de pasajero'), findsOneWidget);
    expect(find.text('+51'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(fieldWithLabel('Contraseña'), findsOneWidget);
    expect(fieldWithLabel('Confirmar contraseña'), findsOneWidget);
    expect(find.text('Fortaleza'), findsOneWidget);
    expect(find.text('Débil'), findsOneWidget);
    expect(
      find.text(
        'Acepto los Términos y Condiciones y la Política de Privacidad',
      ),
      findsOneWidget,
    );
    expect(find.text('¿Ya tienes cuenta? Inicia sesión'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('Register limita celular a nueve dígitos con teclado numérico', (
    tester,
  ) async {
    await tester.pumpWidget(buildRegister());

    final phoneFinder = fieldWithLabel('Número de celular');
    await tester.enterText(phoneFinder, '999a9999999');

    final phoneField = tester.widget<TextFormField>(phoneFinder);
    expect(phoneField.controller?.text, '999999999');

    final phoneEditable = tester.widget<EditableText>(
      find.descendant(of: phoneFinder, matching: find.byType(EditableText)),
    );
    expect(phoneEditable.keyboardType, TextInputType.number);
  });

  testWidgets('Fortaleza es feedback y términos habilitan el CTA', (
    tester,
  ) async {
    await tester.pumpWidget(buildRegister());

    await tester.enterText(fieldWithLabel('Contraseña'), 'Abcdefg1');
    await tester.pump();
    expect(find.text('Media'), findsOneWidget);

    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);

    await tester.enterText(fieldWithLabel('Contraseña'), 'Abcdefg1!234');
    await tester.pump();
    expect(find.text('Fuerte'), findsOneWidget);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Password coincide con las reglas exactas del Backend', (
    tester,
  ) async {
    await tester.pumpWidget(buildRegister());

    final passwordFinder = fieldWithLabel('Contraseña');
    final cases = <(String, bool)>[
      ('Password1', true),
      ('password1', false),
      ('PASSWORD1', false),
      ('Password', false),
      ('Password1!', true),
      ('Pass1', false),
      ('Aa1${List.filled(62, 'x').join()}', false),
    ];

    for (final (password, expectedValid) in cases) {
      await tester.enterText(passwordFinder, password);

      final fieldState = tester.state<FormFieldState<String>>(passwordFinder);
      expect(
        fieldState.validate(),
        expectedValid,
        reason: 'Resultado inesperado para $password',
      );
      await tester.pump();
    }

    await tester.enterText(passwordFinder, 'password1');
    tester.state<FormFieldState<String>>(passwordFinder).validate();
    await tester.pump();
    expect(
      find.text('La contraseña debe incluir mayúscula, minúscula y número'),
      findsOneWidget,
    );
  });

  testWidgets('Register permite mostrar ambas contraseñas', (tester) async {
    await tester.pumpWidget(buildRegister());

    final passwordEditable = find.descendant(
      of: fieldWithLabel('Contraseña'),
      matching: find.byType(EditableText),
    );
    final confirmationEditable = find.descendant(
      of: fieldWithLabel('Confirmar contraseña'),
      matching: find.byType(EditableText),
    );

    expect(tester.widget<EditableText>(passwordEditable).obscureText, isTrue);
    expect(
      tester.widget<EditableText>(confirmationEditable).obscureText,
      isTrue,
    );

    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.tap(find.byTooltip('Mostrar confirmación'));
    await tester.pump();

    expect(tester.widget<EditableText>(passwordEditable).obscureText, isFalse);
    expect(
      tester.widget<EditableText>(confirmationEditable).obscureText,
      isFalse,
    );
  });

  testWidgets('Register no desborda en tamaños Passenger aprobados', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      tester.view.physicalSize = size;

      await tester.pumpWidget(buildRegister());

      expect(find.text('Crea tu cuenta'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('CTA es alcanzable con teclado en tamaños Passenger aprobados', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      tester.view.viewInsets = const FakeViewPadding();

      await tester.pumpWidget(buildRegister());
      await tester.ensureVisible(fieldWithLabel('Confirmar contraseña'));
      await tester.tap(fieldWithLabel('Confirmar contraseña'));
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Crear cuenta'));
      await tester.pumpAndSettle();

      final cta = find.text('Crear cuenta');
      final ctaRect = tester.getRect(cta);
      final keyboardTop = size.height - 300;

      expect(cta, findsOneWidget);
      expect(ctaRect.top, greaterThanOrEqualTo(0));
      expect(ctaRect.bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Register exitoso ejecuta register, login y navega a splash', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final router = _registerRouter();
    addTearDown(router.dispose);

    await _pumpRegisterFlow(tester, repository, router);
    await _submitValidRegister(tester);
    await tester.pumpAndSettle();

    expect(repository.calls, ['register', 'login']);
    expect(repository.registerPhoneE164, '+51999999999');
    expect(repository.registerPassword, 'Password1');
    expect(repository.loginPhoneE164, '+51999999999');
    expect(repository.loginPassword, 'Password1');
    expect(find.text('SPLASH_DESTINATION'), findsOneWidget);
  });

  testWidgets('Register exitoso no solicita OTP ni navega a OTP', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final router = _registerRouter();
    addTearDown(router.dispose);

    await _pumpRegisterFlow(tester, repository, router);
    await _submitValidRegister(tester);
    await tester.pumpAndSettle();

    expect(repository.requestOtpCalls, 0);
    expect(find.text('OTP_DESTINATION'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/splash');
  });

  testWidgets('Register 409 conserva el mensaje de número registrado', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      registerError: _dioHttpError('auth/register/passenger', 409),
    );
    final router = _registerRouter();
    addTearDown(router.dispose);

    await _pumpRegisterFlow(tester, repository, router);
    await _submitValidRegister(tester);
    await _flushAsync(tester);

    expect(repository.registerCalls, 1);
    expect(repository.loginCalls, 0);
    expect(
      find.text('Este número ya está registrado. Intenta iniciar sesión.'),
      findsOneWidget,
    );
    expect(router.routeInformationProvider.value.uri.path, '/register');
  });

  testWidgets(
    'Register creado con fallo de red en login no repite register y orienta a Login',
    (tester) async {
      final repository = _FakeAuthRepository(
        loginError: DioException(
          requestOptions: RequestOptions(path: 'auth/login'),
          type: DioExceptionType.connectionError,
          error: StateError('offline'),
        ),
      );
      final router = _registerRouter();
      addTearDown(router.dispose);

      await _pumpRegisterFlow(tester, repository, router);
      await _submitValidRegister(tester);
      await _flushAsync(tester);

      expect(repository.registerCalls, 1);
      expect(repository.loginCalls, 1);
      expect(repository.calls, ['register', 'login']);
      expect(
        find.text(
          'La cuenta fue creada, pero no se pudo iniciar sesión. '
          'Intenta iniciar sesión desde Login.',
        ),
        findsOneWidget,
      );
      expect(router.routeInformationProvider.value.uri.path, '/register');

      await _flushAsync(tester);
      expect(repository.registerCalls, 1);
    },
  );
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.registerError, this.loginError})
    : super(Dio(), const FlutterSecureStorage());

  final Object? registerError;
  final Object? loginError;

  final List<String> calls = [];
  int registerCalls = 0;
  int loginCalls = 0;
  int requestOtpCalls = 0;
  String? registerPhoneE164;
  String? registerPassword;
  String? loginPhoneE164;
  String? loginPassword;

  @override
  Future<void> registerPassenger({
    required String phoneE164,
    required String password,
  }) async {
    registerCalls++;
    calls.add('register');
    registerPhoneE164 = phoneE164;
    registerPassword = password;

    final error = registerError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    loginCalls++;
    calls.add('login');
    loginPhoneE164 = phoneE164;
    loginPassword = password;

    final error = loginError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<String?> requestOtp({required String phoneE164}) async {
    requestOtpCalls++;
    return '123456';
  }
}

GoRouter _registerRouter() {
  return GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) =>
            const Scaffold(body: Text('SPLASH_DESTINATION')),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) =>
            const Scaffold(body: Text('OTP_DESTINATION')),
      ),
    ],
  );
}

Future<void> _pumpRegisterFlow(
  WidgetTester tester,
  AuthRepository repository,
  GoRouter router,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

Future<void> _submitValidRegister(WidgetTester tester) async {
  await tester.enterText(
    _registerFieldWithLabel('Número de celular'),
    '999999999',
  );
  await tester.enterText(_registerFieldWithLabel('Contraseña'), 'Password1');
  await tester.enterText(
    _registerFieldWithLabel('Confirmar contraseña'),
    'Password1',
  );
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.ensureVisible(find.text('Crear cuenta'));
  await tester.tap(find.text('Crear cuenta'));
}

Finder _registerFieldWithLabel(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );
}

Future<void> _flushAsync(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
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
