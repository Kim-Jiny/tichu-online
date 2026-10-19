# 스토어 설명 이미지 만들기 (screenshots-3.3 브랜치 전용)

앱 화면을 시뮬레이터(iPhone 17 Pro, 1206×2622)에서 실제로 띄워 찍고, 문구와 폰 틀을 얹어 합친다.

1. 임시 DB 로 서버를 8190 에 띄운다 (`PORT=8190 MISSION_MIN_HUMANS=1 DATABASE_URL=.../tichu_shots node server.js`).
2. `seed.js` 로 유저를 만들고 SQL 로 전적·골드·친구를 채운다. `rooms.js` 는 로비에 보일 방을 유지한다.
3. 프로필 사진은 `python3 -m http.server 8191` 로 `p0~p6.jpg` 를 내준다(`shots_disguise.dart` 가 가리킨다).
4. `watcher.js <udid파일> build/shots` 를 켜 두면 테스트가 요청하는 순간의 시뮬레이터 화면을 simctl 로 찍는다.
5. `shoot.sh integration_test/<파일>_test.dart` 로 장면별 테스트를 돌린다.
6. `compose.py <출력폴더> ko` 로 설명 이미지를 합친다 (문구는 `captions_ko.json`).

`--dart-define=HIDE_BANNERS=true` 는 광고 배너를, `SHOTS_DISGUISE=true` 는 봇을 유저처럼 보이게 하고 시스템 권한 창을 막는다.

## 영어판
시뮬레이터 언어를 en 으로 바꾸고(`simctl spawn <udid> defaults write -g AppleLanguages -array en` 후 재부팅),
시드 유저 닉네임을 영어로 바꾼 뒤(`rooms_en.js`), `--dart-define=SHOTS_LANG=en` 으로 돌린다(`shoot_en.sh`).
`compose.py <출력폴더> en` 이 `build/shots_en` 을 `captions_en.json` 문구로 합성한다.
