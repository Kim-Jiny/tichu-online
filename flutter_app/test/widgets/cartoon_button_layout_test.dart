import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/theme/cartoon.dart';

/// 폭이 정해진 자리(ListTile.trailing)에 넣은 expand:false 버튼이 줄 전체로 부풀지 않는다.
/// 예전에는 Center 가 남는 폭을 다 차지해 우편함 줄의 '받기' 버튼이
/// "Trailing widget consumes the entire tile width" 로 레이아웃을 깨뜨렸다.
void main() {
  testWidgets('ListTile 의 trailing 에 넣어도 예외 없이 글자 크기만큼만 차지한다', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('우편'),
                trailing: CartoonButton(
                  expand: false,
                  height: 40,
                  radius: 14,
                  onPressed: () {},
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('받기'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    final w = t.getSize(find.byType(CartoonButton)).width;
    expect(w, lessThan(120)); // 글자 + 좌우 여백 정도
    expect(w, greaterThan(30));
  });

  testWidgets('expand:true 는 여전히 폭을 가득 채우고 글자는 가운데', (t) async {
    await t.binding.setSurfaceSize(const Size(300, 200));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(10),
            child: CartoonButton(onPressed: () {}, child: const Text('확인')),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(CartoonButton)).width, 280);
    final textCenter = t.getCenter(find.text('확인'));
    final buttonCenter = t.getCenter(find.byType(CartoonButton));
    expect((textCenter.dx - buttonCenter.dx).abs(), lessThan(1));
  });

  testWidgets('expand:false 를 Row 안에서 써도 이전과 같다(글자 가운데, 높이 고정)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              CartoonButton(
                expand: false,
                height: 44,
                onPressed: () {},
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('구매'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    final size = t.getSize(find.byType(CartoonButton));
    expect(size.height, greaterThanOrEqualTo(44));
    final textCenter = t.getCenter(find.text('구매'));
    final buttonRect = t.getRect(find.byType(CartoonButton));
    expect((textCenter.dx - buttonRect.center.dx).abs(), lessThan(1.5));
  });
}
