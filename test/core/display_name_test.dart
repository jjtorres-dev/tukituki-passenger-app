import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/core/display_name.dart';

void main() {
  group('displayCompactName', () {
    test('nombre + apellido -> nombre + inicial del apellido', () {
      expect(displayCompactName('Juan', 'Pérez'), 'Juan P.');
    });

    test('apellido compuesto -> inicial del primer apellido (primer carácter)', () {
      expect(displayCompactName('María', 'Rodríguez López'), 'María R.');
    });

    test('recorta espacios en los extremos de ambos campos', () {
      expect(displayCompactName(' María ', ' Rodríguez López '), 'María R.');
    });

    test('sin apellido -> solo el nombre', () {
      expect(displayCompactName('Juan', null), 'Juan');
    });

    test('apellido vacío -> solo el nombre', () {
      expect(displayCompactName('Juan', ''), 'Juan');
    });

    test('apellido solo espacios -> solo el nombre', () {
      expect(displayCompactName('Juan', '   '), 'Juan');
    });

    test('ambos null -> cadena vacía, nunca "null"', () {
      final result = displayCompactName(null, null);

      expect(result, '');
      expect(result, isNot(contains('null')));
    });

    test('nombre vacío con apellido presente -> cadena vacía', () {
      expect(displayCompactName('', 'Pérez'), '');
    });

    test('nunca produce un "." suelto ni espacios dobles', () {
      final result = displayCompactName('Juan', 'Pérez');

      expect(result, isNot(startsWith('.')));
      expect(result, isNot(contains('  ')));
    });

    test('inicial siempre en mayúscula aunque el apellido venga en minúscula', () {
      expect(displayCompactName('Juan', 'pérez'), 'Juan P.');
    });
  });

  group('displayCompactNameFromInitial', () {
    test('nombre + inicial ya derivada -> se combinan tal cual', () {
      expect(displayCompactNameFromInitial('Juan', 'P.'), 'Juan P.');
    });

    test('recorta espacios en los extremos de ambos campos', () {
      expect(displayCompactNameFromInitial(' Juan ', ' P. '), 'Juan P.');
    });

    test('sin inicial -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Juan', null), 'Juan');
    });

    test('inicial vacía -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Juan', ''), 'Juan');
    });

    test('inicial solo espacios (legacy) -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Juan', '   '), 'Juan');
    });

    test('ambos null -> cadena vacía, nunca "null"', () {
      final result = displayCompactNameFromInitial(null, null);

      expect(result, '');
      expect(result, isNot(contains('null')));
    });

    test('nombre vacío con inicial presente -> cadena vacía', () {
      expect(displayCompactNameFromInitial('', 'P.'), '');
    });

    test('nunca produce espacios dobles', () {
      final result = displayCompactNameFromInitial('Juan', 'P.');

      expect(result, isNot(contains('  ')));
    });
  });
}
