import 'package:flutter_test/flutter_test.dart';

import 'package:ban_do/main.dart';

void main() {
  testWidgets('app boots to login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Travel Map Login'), findsOneWidget);
  });
}
