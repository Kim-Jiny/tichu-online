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
    # 2026-10-20 다시 만듦(문의 사진 첨부 문구의 '첨' 추가, 기존 글자는 유지하는
    #            합집합으로 생성 / 936자 약 446KB)

**문구를 바꿨으면 반드시 다시 만든다.** 서브셋에 없는 글자는 기본 폰트로
넘어가 그 글자만 모양이 달라진다 — 한 글자라서 "깨졌다" 로 보인다
(예: "그대로 뒀어요" 의 '뒀'). 아래로 빠진 글자를 먼저 확인할 수 있다:

```sh
cd flutter_app && python3 - <<'EOF'
import glob, json, io, re
from fontTools.ttLib import TTFont
have = set()
for t in TTFont('assets/fonts/Jua-sub.ttf')['cmap'].tables:
    have |= {chr(c) for c in t.cmap}
need = set()
# ARB 값 — UI 문구의 출처
for p in glob.glob('lib/l10n/app_*.arb'):
    for k, v in json.load(io.open(p, encoding='utf-8')).items():
        if not k.startswith('@') and isinstance(v, str): need |= set(v)
# Dart 문자열 리터럴 — l10n 을 거치지 않고 박아 둔 문구.
# 주석 줄은 뺀다. 주석의 한글은 화면에 나가지 않으므로, 넣으면 쫓을 필요
# 없는 글자가 섞여 나온다(그걸 글리프로 채우면 폰트만 커진다).
# 따옴표 두 종류를 따로 찾는다. 하나의 정규식에 양쪽 따옴표를 넣으면
# 그 정규식을 감싸는 문자열에서 끝 따옴표가 붙어 버린다.
dq = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
sq = re.compile(r"'((?:[^'\\\n]|\\.)*)'")
for p in glob.glob('lib/**/*.dart', recursive=True):
    src = io.open(p, encoding='utf-8').read()
    src = '\n'.join(l for l in src.split('\n')
                     if not l.lstrip().startswith(('//', '///', '*')))
    for pat in (dq, sq):
        for m in pat.finditer(src):
            need |= set(m.group(1))
need |= set(chr(c) for c in range(32, 127))
miss = sorted(c for c in need if c not in have and c.strip())
print('빠진 한글:', ''.join(c for c in miss if '가' <= c <= '힣') or '없음')
print('그 외:', ''.join(c for c in miss if not ('가' <= c <= '힣')))
EOF
```

이모지와 일부 기호(♠ ← ✓ 🃏 …)는 Jua 원본에 없다. 그건 빠진 채로 두는 게
맞고, 시스템 이모지 폰트가 그린다.
