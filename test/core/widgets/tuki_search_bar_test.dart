import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/core/theme/passenger_colors.dart';
import 'package:passenger/core/widgets/tuki_search_bar.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  Border fieldBorder(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Container),
      ),
    );
    return (container.decoration as BoxDecoration).border as Border;
  }

  testWidgets('muestra el ícono de lupa y el hint, sin botón de limpiar '
      'vacío', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      wrap(
        TukiSearchBar(controller: controller, hintText: 'Buscar destino'),
      ),
    );

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('Buscar destino'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('con texto y onClear, muestra el botón de limpiar y lo '
      'invoca al tocarlo', (tester) async {
    final controller = TextEditingController(text: 'Municipalidad');
    var cleared = false;

    await tester.pumpWidget(
      wrap(
        TukiSearchBar(controller: controller, onClear: () => cleared = true),
      ),
    );

    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('con texto pero sin onClear, no muestra botón de limpiar', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Municipalidad');

    await tester.pumpWidget(wrap(TukiSearchBar(controller: controller)));

    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets(
    'isLoading muestra el spinner y oculta el botón de limpiar aunque '
    'haya texto',
    (tester) async {
      final controller = TextEditingController(text: 'Municipalidad');

      await tester.pumpWidget(
        wrap(
          TukiSearchBar(
            controller: controller,
            isLoading: true,
            onClear: () {},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    },
  );

  testWidgets('escribir dispara onChanged y el botón de limpiar aparece '
      'sin necesidad de que el padre haga setState', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];

    await tester.pumpWidget(
      wrap(
        TukiSearchBar(
          controller: controller,
          onChanged: changes.add,
          onClear: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), 'UPEU');
    await tester.pump();

    expect(changes, ['UPEU']);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('enabled: false deshabilita el campo interno y usa el '
      'borde deshabilitado', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      wrap(TukiSearchBar(controller: controller, enabled: false)),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);

    final side = fieldBorder(tester).top;
    expect(side.color, PassengerColors.bordeSuave);
  });

  testWidgets(
    'en reposo (habilitado, sin foco) el borde es bordeCampo; con foco '
    'pasa a verdeMarca',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        wrap(TukiSearchBar(controller: controller, focusNode: focusNode)),
      );

      final restingSide = fieldBorder(tester).top;
      expect(restingSide.color, PassengerColors.bordeCampo);
      expect(restingSide.width, 1);

      focusNode.requestFocus();
      await tester.pump();

      final focusedSide = fieldBorder(tester).top;
      expect(focusedSide.color, PassengerColors.verdeMarca);
      expect(focusedSide.width, 1.5);
    },
  );
}
