import 'package:flutter_test/flutter_test.dart';

import 'package:phone/app.dart';

void main() {
  testWidgets('shows connection page placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const BtInputApp());

    final hasChinese = find.text('正在搜索附近的 BT Input...').evaluate().isNotEmpty;
    final hasEnglish = find.text('Scanning for nearby BT Input devices...').evaluate().isNotEmpty;
    expect(hasChinese || hasEnglish, isTrue);
  });
}
