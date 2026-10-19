import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

/// 스크린샷을 SHOTS_DIR(기본 build/shots)에 PNG 로 쓴다.
///
/// 앱 안에서 찍은 이미지는 시뮬레이터에서 지난 프레임이 나오는 일이 있어, SIM_UDID 가
/// 주어지면 그 순간의 시뮬레이터 화면을 simctl 로 직접 찍어 쓴다(상태 표시줄 포함).
Future<void> main() async {
  final dir = Directory(Platform.environment['SHOTS_DIR'] ?? 'build/shots')
    ..createSync(recursive: true);
  final udid = Platform.environment['SIM_UDID'];
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final path = '${dir.path}/$name.png';
      if (udid != null && udid.isNotEmpty) {
        final r = Process.runSync(
            'xcrun', ['simctl', 'io', udid, 'screenshot', '--type=png', path]);
        return r.exitCode == 0;
      }
      File(path).writeAsBytesSync(bytes);
      return true;
    },
  );
}
