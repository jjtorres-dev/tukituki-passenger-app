import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/home/profile_menu_drawer.dart';
import 'package:passenger/features/passenger/domain/passenger_profile.dart';

void main() {
  testWidgets(
    'perfil cargado con calificación: nombre + 5 estrellas (4.85 ⇒ 5 llenas), '
    'cabecera dispara onEditProfile',
    (tester) async {
      var editTaps = 0;
      await _pump(
        tester,
        initialProfile: _profile(
          firstName: 'Ana',
          lastName: 'Ruiz',
          ratingAverage: 4.85,
          ratingCount: 20,
        ),
        loader: () async => _profile(
          firstName: 'Ana',
          lastName: 'Ruiz',
          ratingAverage: 4.85,
          ratingCount: 20,
        ),
        onEditProfile: () => editTaps++,
      );

      expect(find.text('Ana Ruiz'), findsOneWidget);

      final stars = find.descendant(
        of: find.byKey(const ValueKey('profile-menu-rating')),
        matching: find.byType(Icon),
      );
      expect(stars, findsNWidgets(5));
      expect(
        tester.widgetList<Icon>(stars).where((i) => i.icon == Icons.star).length,
        5,
      );
      expect(find.text('Nuevo'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('profile-menu-header')));
      await tester.pump();
      expect(editTaps, 1);
    },
  );

  testWidgets('3.5 ⇒ 3 llenas + 1 media + 1 vacía', (tester) async {
    await _pump(
      tester,
      initialProfile: _profile(ratingAverage: 3.5, ratingCount: 8),
      loader: () async => _profile(ratingAverage: 3.5, ratingCount: 8),
    );

    final icons = tester
        .widgetList<Icon>(
          find.descendant(
            of: find.byKey(const ValueKey('profile-menu-rating')),
            matching: find.byType(Icon),
          ),
        )
        .toList();

    expect(icons.where((i) => i.icon == Icons.star).length, 3);
    expect(icons.where((i) => i.icon == Icons.star_half).length, 1);
    expect(icons.where((i) => i.icon == Icons.star_border).length, 1);
  });

  testWidgets('ratingCount 0 ⇒ píldora "Nuevo", sin estrellas', (tester) async {
    await _pump(
      tester,
      initialProfile: _profile(ratingAverage: 0, ratingCount: 0),
      loader: () async => _profile(ratingAverage: 0, ratingCount: 0),
    );

    expect(find.text('Nuevo'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-menu-rating')), findsNothing);
  });

  testWidgets(
    'sin cache y loader pendiente: "Cargando…", cabecera no tocable',
    (tester) async {
      var editTaps = 0;
      final gate = Completer<void>();

      await _pump(
        tester,
        initialProfile: null,
        loader: () async {
          await gate.future;
          return _profile(ratingAverage: 4.0, ratingCount: 3);
        },
        onEditProfile: () => editTaps++,
      );

      expect(find.text('Cargando tu perfil…'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-menu-header')), findsNothing);

      await tester.tap(find.text('Cargando tu perfil…'));
      await tester.pump();
      expect(editTaps, 0);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-menu-header')), findsOneWidget);
    },
  );

  testWidgets(
    'sin cache y loader devuelve null: estado fallido + "Reintentar" recarga',
    (tester) async {
      var call = 0;

      await _pump(
        tester,
        initialProfile: null,
        loader: () async {
          call++;
          if (call == 1) {
            return null; // falla / 404
          }
          return _profile(
            firstName: 'Ana',
            lastName: 'Ruiz',
            ratingAverage: 4.0,
            ratingCount: 3,
          );
        },
      );

      expect(find.text('No pudimos cargar tu perfil'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-menu-retry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-menu-retry')));
      await tester.pumpAndSettle();

      expect(call, 2);
      expect(find.text('Ana Ruiz'), findsOneWidget);
      expect(find.text('No pudimos cargar tu perfil'), findsNothing);
    },
  );

  testWidgets('"Cerrar sesión" dispara onLogout', (tester) async {
    var logoutTaps = 0;

    await _pump(
      tester,
      initialProfile: _profile(ratingAverage: 4.0, ratingCount: 3),
      loader: () async => _profile(ratingAverage: 4.0, ratingCount: 3),
      onLogout: () => logoutTaps++,
    );

    await tester.tap(find.byKey(const ValueKey('profile-menu-logout')));
    await tester.pump();
    expect(logoutTaps, 1);
  });

  testWidgets('falló el refresh pero hay cache: se sigue mostrando el cache', (
    tester,
  ) async {
    await _pump(
      tester,
      initialProfile: _profile(
        firstName: 'Ana',
        lastName: 'Ruiz',
        ratingAverage: 4.0,
        ratingCount: 3,
      ),
      loader: () async => null, // refresh falla
    );

    expect(find.text('Ana Ruiz'), findsOneWidget);
    expect(find.text('No pudimos cargar tu perfil'), findsNothing);
    expect(find.byKey(const ValueKey('profile-menu-header')), findsOneWidget);
  });
}

PassengerProfile _profile({
  String firstName = 'Ana',
  String lastName = 'Ruiz',
  required double ratingAverage,
  required int ratingCount,
}) {
  return PassengerProfile(
    firstName: firstName,
    lastName: lastName,
    email: null,
    phoneE164: '+51987654321',
    photoUrl: null,
    ratingAverage: ratingAverage,
    ratingCount: ratingCount,
  );
}

/// Monta el `ProfileMenuDrawer` en el slot real `Scaffold.drawer` y lo
/// abre por código (igual que Home vía `_scaffoldKey`), en vez de
/// montarlo suelto. Los cuerpos de aserción no dependen del mecanismo.
Future<void> _pump(
  WidgetTester tester, {
  required PassengerProfile? initialProfile,
  required Future<PassengerProfile?> Function() loader,
  VoidCallback? onEditProfile,
  VoidCallback? onLogout,
}) async {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        drawerEnableOpenDragGesture: false,
        drawer: ProfileMenuDrawer(
          initialProfile: initialProfile,
          loader: loader,
          onEditProfile: onEditProfile ?? () {},
          onLogout: onLogout ?? () {},
        ),
        body: const SizedBox(),
      ),
    ),
  );

  scaffoldKey.currentState!.openDrawer();
  await tester.pumpAndSettle();
}
