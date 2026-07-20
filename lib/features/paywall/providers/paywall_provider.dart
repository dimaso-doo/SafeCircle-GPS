import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/constants/app_strings.dart';

final inAppPurchaseProvider = Provider<InAppPurchase>((_) => InAppPurchase.instance);

final rawSubscriptionProductIdsProvider = Provider<Set<String>>((_) {
  final raw = Platform.isIOS ? AppConfig.applePremiumSubscriptionIds : AppConfig.googlePremiumSubscriptionIds;
  return raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
});

final storeAvailabilityProvider = FutureProvider<bool>((_) async {
  return InAppPurchase.instance.isAvailable();
});

final premiumProductsProvider = FutureProvider.autoDispose<List<ProductDetails>>((ref) async {
  final ids = ref.watch(rawSubscriptionProductIdsProvider);
  if (ids.isEmpty) {
    return const <ProductDetails>[];
  }

  final response = await InAppPurchase.instance.queryProductDetails(ids);
  if (response.error != null) {
    throw StateError(response.error!.message);
  }

  return response.productDetails;
});

final paywallControllerProvider = Provider((ref) => PaywallController(ref));

class PaywallController {
  PaywallController(this.ref);

  final Ref ref;

  Future<void> purchase(ProductDetails product) async {
    final isAvailable = await ref.read(storeAvailabilityProvider.future);
    if (!isAvailable) {
      throw StateError('Store is currently unavailable.');
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    final launched = await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: purchaseParam,
    );

    if (!launched) {
      throw StateError('Unable to open purchase flow.');
    }
  }

  Future<void> restore() async {
    final isAvailable = await ref.read(storeAvailabilityProvider.future);
    if (!isAvailable) {
      throw StateError('Store is currently unavailable.');
    }

    await InAppPurchase.instance.restorePurchases();
  }
}
