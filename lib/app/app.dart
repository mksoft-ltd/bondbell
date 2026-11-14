import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/purchases/presentation/purchase_controller.dart';
import 'app_hooks.dart';
import 'router.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

class BondbellApp extends ConsumerWidget {
  const BondbellApp({super.key});

  static String? noticeText(PurchaseNotice n) => switch (n) {
    PurchaseNotice.proPurchased => 'Bondbell Pro is unlocked. Thank you!',
    PurchaseNotice.restored => 'Your purchase has been restored.',
    PurchaseNotice.nothingToRestore =>
      'No previous Bondbell Pro purchase was found for this account.',
    PurchaseNotice.tipThanks =>
      'Thank you so much for the tip. It really helps.',
    PurchaseNotice.tipCleared =>
      'An earlier tip hadn\'t finished and has now been cleared. Please try '
          'again.',
    PurchaseNotice.cancelled => null,
    PurchaseNotice.failed => 'The purchase didn\'t go through. Please try '
        'again.',
    PurchaseNotice.pending =>
      'Your purchase is waiting for approval. It\'ll unlock when it '
          'completes.',
    PurchaseNotice.storeUnavailable =>
      'Can\'t reach the app store right now. Please try again later.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(
      purchaseControllerProvider.select((PurchaseState s) => s.noticeSerial),
      (int? _, int _) {
        final PurchaseNotice? n = ref.read(purchaseControllerProvider).notice;
        final String? text = n == null ? null : noticeText(n);
        if (text != null) {
          messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(text)),
          );
        }
      },
    );
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (BuildContext context, Widget? child) =>
          AppHooks(child: child ?? const SizedBox.shrink()),
    );
  }
}
