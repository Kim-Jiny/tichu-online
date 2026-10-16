# fonts

`Jua-sub.ttf` — Jua (Google Fonts, SIL OFL 1.1), 카툰 UI 제목/버튼용 디스플레이 폰트.

앱 문자열(`lib/l10n/app_*.arb`)에 나오는 글자 + ASCII 만 남긴 서브셋이다 (원본 2.1MB → 약 450KB).
서브셋에 없는 글자는 자동으로 기본 폰트로 넘어가는데, 글꼴이 달라져 글자가 깨져 보인다(예: '분홍리본'의 '홍'). 문자열을 추가했다면 다시 만들 것 — `lib/**/*.dart` 에 직접 적은 글자도 같이 넣는다:

    pip install fonttools brotli
    # arb 전체 글자 + ASCII 를 text 로 subset.Subsetter.populate(text=...) 후 저장

    # 원본: https://github.com/google/fonts/raw/main/ofl/jua/Jua-Regular.ttf (SIL OFL 1.1)
    # 글자 = arb 값 + ASCII + lib/**/*.dart 의 비 ASCII 글자. layout_features=['*'], hinting=False
    # 2026-10-16 마지막으로 다시 만듦(방 목록 강조 이름 추가분 포함, 미션·토큰 상점 문구 추가분 포함, 981자 요청 / 약 443KB)
