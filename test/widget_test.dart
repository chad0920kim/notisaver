import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:notisaver/main.dart';
import 'package:notisaver/providers/notification_provider.dart';

void main() {
  testWidgets('NotiSaver App Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NotificationProvider(),
        child: const NotiSaverApp(),
      ),
    );

    // 알림 보관함 앱 타이틀이 화면에 그려지는지 확인
    expect(find.text('알림 보관함'), findsOneWidget);
  });
}
