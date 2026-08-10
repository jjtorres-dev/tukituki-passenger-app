import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:passenger/app.dart';

void main() {
  testWidgets('TukiTuki app inicia correctamente', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TukiTukiApp()));

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
    expect(find.text('Preparando TukiTuki...'), findsOneWidget);
    expect(find.text('Tu viaje empieza aquí'), findsOneWidget);
  });

  testWidgets('Splash se adapta a pantallas Passenger compactas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      tester.view.physicalSize = size;

      await tester.pumpWidget(const ProviderScope(child: TukiTukiApp()));

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Tu viaje empieza aquí'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
