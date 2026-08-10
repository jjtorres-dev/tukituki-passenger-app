import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/auth/presentation/login_screen.dart';

void main() {
  Widget buildLogin() {
    return const ProviderScope(child: MaterialApp(home: LoginScreen()));
  }

  testWidgets('Login renderiza branding, formulario y enlace Register', (
    tester,
  ) async {
    await tester.pumpWidget(buildLogin());

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
    expect(find.text('Tu mototaxi en la selva'), findsOneWidget);
    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('+51'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('¿No tienes cuenta? Crear cuenta'), findsOneWidget);
  });

  testWidgets('Login limita el celular y permite mostrar la contraseña', (
    tester,
  ) async {
    await tester.pumpWidget(buildLogin());

    final phoneFinder = find.byType(TextFormField).first;
    await tester.enterText(phoneFinder, '999a9999999');

    final phoneField = tester.widget<TextFormField>(phoneFinder);
    expect(phoneField.controller?.text, '999999999');

    final phoneEditable = tester.widget<EditableText>(
      find.descendant(of: phoneFinder, matching: find.byType(EditableText)),
    );
    expect(phoneEditable.keyboardType, TextInputType.number);

    final passwordFieldFinder = find.descendant(
      of: find.byType(TextFormField).at(1),
      matching: find.byType(EditableText),
    );
    var passwordField = tester.widget<EditableText>(passwordFieldFinder);
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();

    passwordField = tester.widget<EditableText>(passwordFieldFinder);
    expect(passwordField.obscureText, isFalse);
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  testWidgets('Login no desborda en tamaños Passenger aprobados', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      tester.view.physicalSize = size;

      await tester.pumpWidget(buildLogin());

      expect(find.text('Bienvenido de nuevo'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
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

      await tester.pumpWidget(buildLogin());
      await tester.tap(find.byType(TextFormField).at(1));
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      final cta = find.text('Iniciar sesión');
      final ctaRect = tester.getRect(cta);
      final keyboardTop = size.height - 300;

      expect(cta, findsOneWidget);
      expect(ctaRect.top, greaterThanOrEqualTo(0));
      expect(ctaRect.bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
