import 'package:flutter_test/flutter_test.dart';
import 'package:fb_share_automation/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const FbShareApp());
    expect(find.byType(FbShareApp), findsOneWidget);
  });
}
