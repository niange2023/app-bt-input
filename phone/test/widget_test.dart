import 'package:flutter_test/flutter_test.dart';

import 'package:phone/app.dart';

void main() {
  testWidgets('shows connection page placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const BtInputApp());

    expect(find.text('正在搜索附近的 BT Input...'), findsOneWidget);
  });
}
