# 봇 아바타 원본

여기 있는 `bot1.png` … `bot6.png`가 **원본**(1254×1254)이고, 번들에 들어가는 것은
`assets/bots/`의 256×256 축소판입니다. 이 디렉터리는 pubspec 의 assets 목록에
없으므로 앱에 포함되지 않습니다.

아바타는 가장 큰 곳에서도 36dp(≈108px @3x)로 그려지기 때문에 256px면 충분하고,
원본 6장을 그대로 넣으면 12MB가 앱 용량에 그대로 얹힙니다.

## 수정하거나 추가할 때

원본을 이 디렉터리에서 고친 뒤 축소판을 다시 만듭니다:

```sh
cd flutter_app
for i in 1 2 3 4 5 6; do
  sips -Z 256 art/bots/bot$i.png --out assets/bots/bot$i.png
done
```

- 정사각 PNG, 주요 요소는 가운데 — 원형으로 잘립니다
- 장수를 바꾸면 `lib/widgets/bot_avatar.dart` 의 `_artCount` 도 맞춰야 합니다.
  봇 번호를 장수로 나눈 나머지로 그림을 고르므로 번호↔그림 대응은 모든 기기에서
  동일합니다 (기기별 랜덤이 아님).
