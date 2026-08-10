import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
