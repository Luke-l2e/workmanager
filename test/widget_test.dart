import 'package:flutter_test/flutter_test.dart';

import 'package:workmanager_demo/main.dart';

void main() {
  testWidgets('renders the live demo screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Workmanager live demo'), findsOneWidget);
    expect(find.text('Schedule demo task'), findsOneWidget);
    await tester.pump();
  });
}
