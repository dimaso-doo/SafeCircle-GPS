import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/empty_states.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../providers/paywall_provider.dart';

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productIds = ref.watch(rawSubscriptionProductIdsProvider);
    final productsState = ref.watch(premiumProductsProvider);
    final availability = ref.watch(storeAvailabilityProvider);
    final subscription = ref.watch(subscriptionStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade to Premium')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Unlock Premium for family safety features and performance.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            _planCard(context, subscription),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Priority live updates'),
              subtitle: const Text('Faster location intervals and tighter movement thresholds.'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Safe zones + alerts'),
              subtitle: const Text('Geofences, zone events, and SOS event workflow.'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Extended location history'),
              subtitle: const Text('Keep 7/30 day history with higher-tier retention.'),
            ),
            const SizedBox(height: 12),
            availability.when(
              data: (isAvailable) => isAvailable
                  ? productsState.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => ErrorState(message: error.toString()),
                      data: (products) => _productBlock(context, ref, products, productIds),
                    )
                  : ErrorState(message: 'Store is unavailable on this device.'),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorState(message: error.toString()),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _restore(ref, context),
              icon: const Icon(Icons.restore),
              label: const Text('Restore purchases'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Important: Purchase IDs come from app store configuration and are intentionally not hardcoded.\n'
              'This screen prepares the flow; entitlement verification should be completed in backend webhooks and a trusted entitlement source.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context, AsyncValue subscription) {
    return subscription.when(
      data: (subscriptionState) => Card(
        child: ListTile(
          title: Text(subscriptionState.planName),
          subtitle: Text(
            'Current plan: ${subscriptionState.planDescription()}. Free users can manage one circle, up to 2 members, and 24h history.',
          ),
          trailing: subscriptionState.isPremium ? const Icon(Icons.star, color: Colors.orange) : null,
        ),
      ),
      loading: () => const Card(child: SizedBox(height: 72, child: Center(child: CircularProgressIndicator()))),
      error: (error, _) => const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Subscription state unavailable. You can still open the plan picker below.'),
        ),
      ),
    );
  }

  Widget _productBlock(
    BuildContext context,
    WidgetRef ref,
    List<ProductDetails> products,
    Set<String> productIds,
  ) {
    if (products.isEmpty) {
      return AppConfig.googlePremiumSubscriptionIds.isEmpty && AppConfig.applePremiumSubscriptionIds.isEmpty
          ? const ErrorState(message: 'No store IDs configured yet.')
          : const EmptyState(message: 'No matching products found. Verify app-store setup in the product list.');
    }

    final visibleProducts = products
        .where((product) => productIds.isEmpty || productIds.contains(product.id))
        .toList(growable: false)
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));

    if (visibleProducts.isEmpty) {
      return const EmptyState(message: 'No configured premium product IDs matched Store products.');
    }

    return Column(
      children: visibleProducts.map((product) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(product.title),
            subtitle: Text(product.description),
            trailing: ElevatedButton(
              onPressed: () => _purchase(ref, context, product),
              child: Text('Upgrade ${product.price}'),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Future<void> _purchase(WidgetRef ref, BuildContext context, ProductDetails product) async {
    try {
      await ref.read(paywallControllerProvider).purchase(product);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase requested. Apply entitlement update after backend webhook sync.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purchase failed: ${error.toString()}')));
      }
    }
  }

  Future<void> _restore(WidgetRef ref, BuildContext context) async {
    try {
      await ref.read(paywallControllerProvider).restore();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore requested. Entitlement may take a few seconds to appear.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: ${error.toString()}')));
      }
    }
  }
}
