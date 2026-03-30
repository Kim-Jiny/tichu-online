import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  // 디버그 빌드면 테스트 광고, 릴리스면 실제 광고
  static const bool _useTestAds = kDebugMode;

  // --- 배너 광고 ID ---
  static String get lobbyBannerId => _useTestAds
      ? _testBannerId
      : (Platform.isIOS ? 'ca-app-pub-2707874353926722/5998930812' : 'ca-app-pub-2707874353926722/5799887160');

  static String get settingsBannerId => _useTestAds
      ? _testBannerId
      : (Platform.isIOS ? 'ca-app-pub-2707874353926722/6681590547' : 'ca-app-pub-2707874353926722/6490018856');

  static String get rankingBannerId => _useTestAds
      ? _testBannerId
      : (Platform.isIOS ? 'ca-app-pub-2707874353926722/4685849144' : 'ca-app-pub-2707874353926722/4486805490');

  // --- 보상형 광고 ID ---
  static String get rewardedAdId => _useTestAds
      ? _testRewardedId
      : (Platform.isIOS ? 'ca-app-pub-2707874353926722/9523376308' : 'ca-app-pub-2707874353926722/7360113945');

  // Google 공식 테스트 광고 ID
  static String get _testBannerId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';

  static String get _testRewardedId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  static const int maxDailyRewards = 5;
  static const String _rewardCountKey = 'ad_reward_count';
  static const String _rewardDateKey = 'ad_reward_date';

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
          debugPrint('[AdService] Banner FAILED: $adUnitId / code=${error.code} message=${error.message}');
          onAdFailedToLoad?.call(ad as BannerAd, error);
          ad.dispose();
        },
      ),
    );
  }

  /// 오늘 보상 횟수 조회
  static Future<int> getTodayRewardCount() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_rewardDateKey) ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (savedDate != today) return 0;
    return prefs.getInt(_rewardCountKey) ?? 0;
  }

  /// 보상 횟수 증가
  static Future<void> incrementRewardCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_rewardDateKey) ?? '';
    int count = 0;
    if (savedDate == today) {
      count = prefs.getInt(_rewardCountKey) ?? 0;
    }
    await prefs.setString(_rewardDateKey, today);
    await prefs.setInt(_rewardCountKey, count + 1);
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
              onError('광고를 표시할 수 없습니다');
            },
          );
          ad.show(
            onUserEarnedReward: (ad, reward) {
              onRewardEarned();
            },
          );
        },
        onAdFailedToLoad: (error) {
          onError('광고를 불러올 수 없습니다');
        },
      ),
    );
  }
}
