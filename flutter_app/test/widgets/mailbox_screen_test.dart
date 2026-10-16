import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/screens/mailbox_screen.dart';
import 'package:tichu_online/services/game_service.dart';

class _FakeGame extends ChangeNotifier implements GameService {
  @override
  List<Map<String, dynamic>> mailbox = [];
  @override
  bool mailboxLoading = false;
  @override
  List<Color> get themeGradient => const [Color(0xFF9ADCFF), Color(0xFFFFF1D6)];
  final calls = <String>[];
  @override
  void loadMailbox() => calls.add('load');
  @override
  ({int? id, String? message})? takeFailedMailClaim() => null;
  @override
  Map<String, dynamic>? takeMailReward() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('받을 보상이 든 우편도 줄에 그려지고 받기 버튼이 보인다(레이아웃 예외 없음)', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 800));
    final game = _FakeGame()
      ..mailbox = [
        {
          'id': 574,
          'title': '테스트우편',
          'body': 'ㅎ',
          'reward_gold': 5000,
          'reward_item_key': null,
          'reward_days': null,
          'expires_at': null,
          'created_at': '2026-10-16T09:40:29.996Z',
          'sender_name': null,
          'read_at': null,
          'claimed_at': null,
        },
        {
          'id': 575,
          'title': '보상 없는 편지',
          'body': '안녕',
          'reward_gold': 0,
          'reward_item_key': null,
          'created_at': '2026-10-15T09:40:29.996Z',
          'read_at': null,
          'claimed_at': null,
        },
      ];
    await t.pumpWidget(
      ChangeNotifierProvider<GameService>.value(
        value: game,
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          home: const MailboxScreen(),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 900));
    expect(t.takeException(), isNull);
    expect(find.text('테스트우편'), findsOneWidget);
    expect(find.text('보상 없는 편지'), findsOneWidget);
    // 줄에서 바로 받기: 받기 버튼은 글자 크기만큼의 폭.
    expect(find.text('받기'), findsWidgets);
    final btn = find.byType(ListTile).first;
    expect(btn, findsOneWidget);
  });
}
