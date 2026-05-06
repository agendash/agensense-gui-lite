import 'package:agensense_gui_lite/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows AgenSense validation client shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AgenSenseGuiLiteApp());
    await tester.pumpAndSettle();

    expect(find.text('AgenSense GUI Lite'), findsOneWidget);
    expect(find.text('Providers'), findsOneWidget);
    expect(find.text('Voice WS'), findsOneWidget);
  });
}
