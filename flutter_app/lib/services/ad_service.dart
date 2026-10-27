import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ads are mobile-only: google_mobile_ads has no web implementation, and the
/// `Platform` reads below throw outright in a browser. Guarding the ids keeps
/// the failure on the load callback, where every caller already handles it.
class AdService {
  // 디버그 빌드면 테스트 광고, 릴리스면 실제 광고
  static const bool _useTestAds = kDebugMode;

  // --- 배너 광고 ID ---
  static String get lobbyBannerId => _useTestAds
      ? _testBannerId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/5998930812'
            : 'ca-app-pub-2707874353926722/5799887160');

  static String get settingsBannerId => _useTestAds
      ? _testBannerId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/6681590547'
            : 'ca-app-pub-2707874353926722/6490018856');

  static String get rankingBannerId => _useTestAds
      ? _testBannerId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/4685849144'
            : 'ca-app-pub-2707874353926722/4486805490');

  static String get skWaitingBannerId => _useTestAds
      ? _testBannerId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/7335043650'
            : 'ca-app-pub-2707874353926722/4010771110');

  // --- 보상형 광고 ID ---
  // 상점의 "광고 보고 골드" 버튼 전용.
  static String get rewardedAdId => _useTestAds
      ? _testRewardedId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/9523376308'
            : 'ca-app-pub-2707874353926722/7360113945');

  // 출석 체크(7일 사이클) 전용 보상형 광고. rewardedAdId와 분리해서
  // 둘이 같은 인스턴스를 경쟁하지 않도록 하고, AdMob 쪽 노출/수익 통계도
  // 채널별로 끊어 볼 수 있게 한다.
  static String get attendanceRewardedAdId => _useTestAds
      ? _testRewardedId
      : ((!kIsWeb && Platform.isIOS)
            ? 'ca-app-pub-2707874353926722/2526925712'
            : 'ca-app-pub-2707874353926722/3456864004');

  // Google 공식 테스트 광고 ID
  static String get _testBannerId => (!kIsWeb && Platform.isIOS)
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';

  static String get _testRewardedId => (!kIsWeb && Platform.isIOS)
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  /// 하루에 받을 수 있는 광고 보상 횟수. 서버(claimAdReward)와 같은 값이어야 한다.
  /// 오늘 몇 번 받았는지는 기기가 세지 않는다 — 서버가 알려 준 값(GameService.adRewardUsedToday)만 쓴다.
  /// 기기 날짜와 서버 날짜(UTC)가 달라서, 기기가 세면 밤~오전에 어긋나고,
  /// 서버가 거절해도 횟수만 줄었다.
  static const int maxDailyRewards = 5;

  /// 배너 광고 생성 (로드 성공/실패 콜백 포함)
  static BannerAd createBannerAd(
    String adUnitId, {
    void Function(BannerAd)? onAdLoaded,
    void Function(BannerAd, LoadAdError)? onAdFailedToLoad,
  }) {
    return BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('[AdService] Banner loaded: $adUnitId');
          onAdLoaded?.call(ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
            '[AdService] Banner FAILED: $adUnitId / code=${error.code} message=${error.message}',
          );
          onAdFailedToLoad?.call(ad as BannerAd, error);
          ad.dispose();
        },
      ),
    );
  }

  /// 보상형 광고 로드 & 표시
  static void loadAndShowRewardedAd({
    required void Function() onRewardEarned,
    required void Function(String error) onError,
  }) {
    RewardedAd.load(
      adUnitId: rewardedAdId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              onError('ad_show_failed');
            },
          );
          ad.show(
            onUserEarnedReward: (ad, reward) {
              onRewardEarned();
            },
          );
        },
        onAdFailedToLoad: (error) {
          onError('ad_load_failed');
        },
      ),
    );
  }
}
