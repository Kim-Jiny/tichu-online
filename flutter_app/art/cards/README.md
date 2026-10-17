# 스컬킹 카드 원본

여기 있는 PNG(1024×1536)가 **원본**이고, 번들에 들어가는 것은
`assets/cards/`의 500×750 webp 입니다. 이 디렉터리는 pubspec 의 assets 목록에
없으므로 앱에 포함되지 않습니다.

원본을 `assets/cards/` 에 두면 안 됩니다. pubspec 이 그 디렉터리를 통째로
(`- assets/cards/`) 선언하므로, 아무 코드도 참조하지 않는 PNG 라도 13장
17MB 가 앱 용량에 그대로 얹힙니다.

## 파일 이름 ↔ 번들 이름

원본 이름과 번들 이름이 다릅니다. 코드가 보는 건 오른쪽입니다
(`sk_game_screen.dart` 의 카드 → 에셋 표, `rules_screen.dart` 의 안내 그림).

| 원본 | 번들 | 카드 |
| --- | --- | --- |
| `escape.png` | `sk_escape.webp` | 탈출(백기) |
| `kraken.png` | `sk_kraken.webp` | 크라켄 |
| `mermaid.png` | `sk_mermaid.webp` | 인어 |
| `pirate1.png` | `sk_pirate1.webp` | 해적 1 — 라스칼 |
| `pirate2.png` | `sk_pirate2.webp` | 해적 2 — 로지 |
| `pirate3.png` | `sk_pirate3.webp` | 해적 3 — 벤트 |
| `pirate4.png` | `sk_pirate4.webp` | 해적 4 — 해리 |
| `pirate5.png` | `sk_pirate5.webp` | 해적 5 — 후아니타 |
| `pirate.png` | `sk_pirate.webp` | 일반 해적 — 티그리스를 해적으로 냈을 때 |
| `root.png` | `sk_loot.webp` | **루트(Loot)** — 이름이 유일하게 어긋납니다 |
| `skull_king.png` | `sk_skull_king.webp` | 스컬킹 |
| `tigress.png` | `sk_tigress.webp` | 티그리스 |
| `white_whale.png` | `sk_white_whale.webp` | 흰고래 |

`pirate.png` → `sk_pirate.webp` 는 **이름 없는 일반 해적**입니다. 덱에 그런
카드가 있는 건 아니고, 두 곳에서 씁니다:

- **티그리스를 해적으로 냈을 때** 테이블에 놓이는 그림. 손패에서는 티그리스
  그림(칼+백기)이고, 내는 순간 고른 모양으로 바뀝니다. 이름 있는 다섯 장
  중 하나를 쓰면 그 해적을 낸 것으로 오해하므로 반드시 이 그림이어야 합니다.
- 티그리스를 낼 때 뜨는 **선택 다이얼로그**의 '해적' 쪽 그림.

`sk_card_back.webp`(카드 뒷면)는 여기 원본이 없습니다. 다른 경로로 만들어진
그림이라 이번 교체에서 건드리지 않았습니다.

## 다시 만들 때

원본을 고친 뒤 번들용 webp 를 다시 뽑습니다. 변환은 서버가 이미 쓰는
`sharp` 로 합니다(별도 설치 없음 — cwebp 나 ImageMagick 은 이 저장소에 없고,
macOS 의 `sips` 는 webp 를 쓰지 못합니다).

```sh
cd server && node -e "
const sharp=require('sharp'), fs=require('fs');
const A='../flutter_app/assets/cards/', S='../flutter_app/art/cards/';
const MAP={escape:'sk_escape',kraken:'sk_kraken',mermaid:'sk_mermaid',pirate:'sk_pirate',
  pirate1:'sk_pirate1',pirate2:'sk_pirate2',pirate3:'sk_pirate3',
  pirate4:'sk_pirate4',pirate5:'sk_pirate5',root:'sk_loot',
  skull_king:'sk_skull_king',tigress:'sk_tigress',white_whale:'sk_white_whale'};
(async()=>{ for(const [f,t] of Object.entries(MAP)){
  const b=await sharp(S+f+'.png').resize(500,750,{fit:'fill',kernel:'lanczos3'})
    .webp({quality:90,effort:6,smartSubsample:true}).toBuffer();
  fs.writeFileSync(A+t+'.webp',b);
  console.log(t, (b.length/1024).toFixed(1)+' KB');
}})();
"
```

- **500×750** — 2:3. 화면에서 가장 큰 카드가 이 안에 들어옵니다.
- **quality 90** — 평면 카툰이라 무손실(장당 280KB)은 과하고, q85 와 q90 은
  1:1 로 봐도 거의 같지만 굵은 검은 외곽선의 여유를 위해 90 을 씁니다.
  13장 합계 473KB 입니다.
