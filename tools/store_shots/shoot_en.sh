#!/bin/bash
cd /Users/jiny/Documents/Jiny/godot/tichu/flutter_app
U=$(cat /private/tmp/claude-501/-Users-jiny-Documents-Jiny-godot-tichu/de966dec-3887-41ce-9d7c-648aff6928e5/scratchpad/udid)
xcrun simctl uninstall $U com.jiny.tichuOnline >/dev/null 2>&1
flutter drive --driver=test_driver/integration_test.dart --target=${1:-integration_test/store_shots_test.dart} -d $U --dart-define=WS_URL=ws://127.0.0.1:8190 --dart-define=HIDE_BANNERS=true --dart-define=SHOTS_DISGUISE=true --dart-define=SHOTS_LANG=en 2>&1 | tee /private/tmp/claude-501/-Users-jiny-Documents-Jiny-godot-tichu/de966dec-3887-41ce-9d7c-648aff6928e5/scratchpad/last_en.log | grep -E "^flutter: (\[SHOT.*|.*(Exception|Error|not found|FAILED)|[0-9:+ ]*(All tests|Some tests))|Error:|error:" | head -40
