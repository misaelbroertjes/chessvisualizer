import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  // Production Ad Unit ID created in AdMob (with official Google Test ID in debug mode)
  String get _rewardedUnitId {
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917';
    }
    return 'ca-app-pub-2418724595418305/7424811369';
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    await MobileAds.instance.initialize();
    loadRewardedAd();
  }

  void loadRewardedAd() {
    if (kIsWeb) return;
    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isRewardedAdReady = false;
        },
      ),
    );
  }

  void showRewardedAd({
    required VoidCallback onUserEarnedReward,
    VoidCallback? onAdFailed,
  }) {
    if (!_isRewardedAdReady || _rewardedAd == null) {
      loadRewardedAd();
      if (kDebugMode) {
        onUserEarnedReward();
      } else if (onAdFailed != null) {
        onAdFailed();
      }
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdReady = false;
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdReady = false;
        loadRewardedAd();
        if (kDebugMode) {
          onUserEarnedReward();
        } else if (onAdFailed != null) {
          onAdFailed();
        }
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onUserEarnedReward();
      },
    );
  }
}
