import 'package:flutter_test/flutter_test.dart';
import 'package:money_identifier_ai/main.dart';

void main() {
  testWidgets('home screen shows the main app actions', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('MONEY SENSE'), findsOneWidget);
    expect(find.text('Mở camera'), findsOneWidget);
    expect(find.text('Thư viện ảnh'), findsOneWidget);
  });
}
