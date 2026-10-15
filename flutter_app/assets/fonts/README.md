# fonts

`Jua-sub.ttf` — Jua (Google Fonts, SIL OFL 1.1), 카툰 UI 제목/버튼용 디스플레이 폰트.

앱 문자열(`lib/l10n/app_*.arb`)에 나오는 글자 + ASCII 만 남긴 서브셋이다 (원본 2.1MB → 약 450KB).
서브셋에 없는 글자는 자동으로 기본 폰트로 넘어간다. 문자열을 크게 추가했다면 다시 만들 것:

    pip install fonttools brotli
    # arb 전체 글자 + ASCII 를 text 로 subset.Subsetter.populate(text=...) 후 저장
