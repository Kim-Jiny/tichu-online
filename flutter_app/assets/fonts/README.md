# fonts

`Jua-sub.ttf` — Jua (Google Fonts, SIL OFL 1.1), 카툰 UI 제목/버튼용 디스플레이 폰트.

앱 문자열(`lib/l10n/app_*.arb`)에 나오는 글자 + ASCII 만 남긴 서브셋이다 (원본 2.1MB → 약 450KB).
서브셋에 없는 글자는 자동으로 기본 폰트로 넘어가는데, 글꼴이 달라져 글자가 깨져 보인다(예: '분홍리본'의 '홍'). 문자열을 추가했다면 다시 만들 것 — `lib/**/*.dart` 에 직접 적은 글자도 같이 넣는다:

    pip install fonttools brotli
    # arb 전체 글자 + ASCII 를 text 로 subset.Subsetter.populate(text=...) 후 저장

    # 원본: https://github.com/google/fonts/raw/main/ofl/jua/Jua-Regular.ttf (SIL OFL 1.1)
    # 글자 = arb 값 + ASCII + lib/**/*.dart 의 비 ASCII 글자. layout_features=['*'], hinting=False
    # 2026-10-18 마지막으로 다시 만듦(해적 능력 문구·루트 표기 변경분 포함,
    #            1001자 요청 중 원본에 있는 935자 / 약 445KB)

**문구를 바꿨으면 반드시 다시 만든다.** 서브셋에 없는 글자는 기본 폰트로
넘어가 그 글자만 모양이 달라진다 — 한 글자라서 "깨졌다" 로 보인다
(예: "그대로 뒀어요" 의 '뒀'). 아래로 빠진 글자를 먼저 확인할 수 있다:

```sh
cd flutter_app && python3 - <<'EOF'
import glob, json, io
from fontTools.ttLib import TTFont
have = set()
for t in TTFont('assets/fonts/Jua-sub.ttf')['cmap'].tables:
    have |= {chr(c) for c in t.cmap}
need = set()
for p in glob.glob('lib/l10n/app_*.arb'):
    for k, v in json.load(io.open(p, encoding='utf-8')).items():
        if not k.startswith('@') and isinstance(v, str): need |= set(v)
for p in glob.glob('lib/**/*.dart', recursive=True):
    need |= {c for c in io.open(p, encoding='utf-8').read() if ord(c) > 127}
need |= set(chr(c) for c in range(32, 127))
print(''.join(sorted(c for c in need if c not in have and c.strip())))
EOF
```

이모지와 일부 기호(♠ ← ✓ 🃏 …)는 Jua 원본에 없다. 그건 빠진 채로 두는 게
맞고, 시스템 이모지 폰트가 그린다.
