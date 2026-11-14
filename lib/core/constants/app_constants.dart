/// Every external URL, product id and fixed string the app depends on.
abstract final class AppConstants {
  static const String appName = 'Bondbell';
  static const String appVersionLabel = '1.0.0';

  static const String privacyPolicyUrl =
      'https://mksoft-ltd.github.io/bondbell/privacy_policy.html';
  static const String supportUrl = 'https://bondbell.froggyeye.com';
  static const String supportEmail = 'info@froggyeye.com';

  /// NS&I's public downloads page. The app reads it at run time to find the
  /// current files rather than guessing their URLs.
  static const String nsiDownloadsPage =
      'https://www.nsandi.com/get-to-know-us/winning-bonds-downloads';
  static const String nsiPrizeCheckerPage =
      'https://www.nsandi.com/prize-checker';
  static const String nsiContactPage =
      'https://www.nsandi.com/contact-us';
  static const String nsiOrigin = 'https://www.nsandi.com';

  /// Honest identification for requests to nsandi.com.
  static String userAgent(String platform) =>
      'Bondbell/$appVersionLabel ($platform; personal bond checker; '
      '+$supportUrl)';

  static const String proProductId = 'com.froggyeye.bondbell.pro';
  static const String tipSmallId = 'com.froggyeye.bondbell.tip.small';
  static const String tipMediumId = 'com.froggyeye.bondbell.tip.medium';
  static const String tipLargeId = 'com.froggyeye.bondbell.tip.large';
  static const List<String> tipIds = <String>[
    tipSmallId,
    tipMediumId,
    tipLargeId,
  ];

  /// Word for word the first two sentences of the store disclaimer
  /// (docs/ASO.md §4, both stores' long descriptions). The marks belong to
  /// the Director of Savings, not to NS&I itself (compliance S-2).
  static const String independenceNotice =
      'Bondbell is an independent app and is not affiliated with, endorsed '
      'by or connected to NS&I (National Savings and Investments). Premium '
      'Bonds is a registered trademark of the Director of Savings.';

  static const String confirmWithNsi =
      'Always confirm results with NS&I before relying on them. Bondbell '
      'reads NS&I\'s published lists, but only NS&I can confirm a prize.';

  static const String copyright = '© 2026 Froggy Eye Ltd';
}
