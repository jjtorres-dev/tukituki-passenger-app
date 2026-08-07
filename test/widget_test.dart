import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passenger/app.dart';

void main() {
  testWidgets('TukiTuki app inicia correctamente', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TukiTukiApp(),
      ),
    );

    expect(find.text('TukiTuki Passenger'), findsOneWidget);
  });
}