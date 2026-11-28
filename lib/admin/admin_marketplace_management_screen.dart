import 'package:flutter/material.dart';

import 'admin_marketplace_operations_api.dart';
import 'admin_marketplace_operations_screens.dart';
import 'admin_marketplace_screen.dart';
import 'admin_permissions.dart';

const marketplaceAdminRoutes = <String>[
  '/marketplace',
  '/marketplace/merchants',
  '/marketplace/orders',
  '/marketplace/products',
  '/marketplace/settings',
  '/marketplace/delivery',
  '/marketplace/analytics',
  '/marketplace/commissions',
];

/// Navigation authorization is presentation only; the API enforces every grant.
bool canViewMarketplace(AdminAccess access) =>
    access.has(AdminPermissions.marketplaceView);

class AdminMarketplaceManagementScreen extends StatefulWidget {
  const AdminMarketplaceManagementScreen({
    super.key,
    this.initialAccess,
    this.destination = '/marketplace',
    this.api,
  });

  final AdminAccess? initialAccess;
  final String destination;
  final AdminMarketplaceOperationsApi? api;

  @override
  State<AdminMarketplaceManagementScreen> createState() =>
      _MarketplaceManagementState();
}

class _MarketplaceManagementState
    extends State<AdminMarketplaceManagementScreen> {
  late final Future<AdminAccess> _access = widget.initialAccess == null
      ? AdminSessionStore.loadAccess()
      : Future.value(widget.initialAccess!);

  @override
  Widget build(BuildContext context) => FutureBuilder<AdminAccess>(
        future: _access,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('Unable to verify Marketplace access. Sign in again.');
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final access = snapshot.data!;
          if (!canViewMarketplace(access)) {
            return _message(
                'Your role does not have permission to view Marketplace Management.');
          }
          switch (widget.destination) {
            case '/marketplace/merchants':
              return AdminMarketplaceMerchantsScreen(api: widget.api);
            case '/marketplace/orders':
              return AdminMarketplaceOrdersScreen(api: widget.api);
            case '/marketplace/products':
              return const AdminMarketplaceScreen();
            case '/marketplace/settings':
            case '/marketplace/delivery':
              return AdminMarketplaceSettingsScreen(api: widget.api);
            case '/marketplace/analytics':
              return AdminMarketplaceAnalyticsScreen(api: widget.api);
            case '/marketplace/commissions':
              return AdminMarketplaceOrdersScreen(
                api: widget.api,
                commissionHistory: true,
              );
            default:
              return _overview(context);
          }
        },
      );

  Widget _message(String message) => Scaffold(
        appBar: AppBar(title: const Text('Marketplace Management')),
        body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24), child: Text(message)),
        ),
      );

  Widget _overview(BuildContext context) {
    const entries = <({String title, String detail, String route, IconData icon})>[
      (
        title: 'Merchant Management',
        detail: 'Profiles, business information, KYC, products, sales and status.',
        route: '/marketplace/merchants',
        icon: Icons.storefront_outlined,
      ),
      (
        title: 'Order Management',
        detail: 'Buyers, merchants, items, payments, fulfillment and financial details.',
        route: '/marketplace/orders',
        icon: Icons.shopping_bag_outlined,
      ),
      (
        title: 'Products & Moderation',
        detail: 'Review submitted products and their existing moderation actions.',
        route: '/marketplace/products',
        icon: Icons.inventory_2_outlined,
      ),
      (
        title: 'Commission Settings',
        detail: 'Review the 3% starting rate and existing overrides. Changes require Head Office policy authority.',
        route: '/marketplace/settings',
        icon: Icons.percent_outlined,
      ),
      (
        title: 'Delivery Settings',
        detail: 'Optional delivery, pickup availability and the supported global delivery fee.',
        route: '/marketplace/delivery',
        icon: Icons.local_shipping_outlined,
      ),
      (
        title: 'Analytics & Commission Reports',
        detail: 'Orders, sales, merchants, commission, merchant earnings and delivery fees.',
        route: '/marketplace/analytics',
        icon: Icons.analytics_outlined,
      ),
      (
        title: 'Commission Transaction History',
        detail: 'Stored commission amounts for settled orders, with their financial snapshots and timelines.',
        route: '/marketplace/commissions',
        icon: Icons.receipt_long_outlined,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace Management')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Manage Marketplace',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'These pages use the live Marketplace APIs. Opening them does not activate '
            'Marketplace policy or change any balance. Policy activation requires '
            'separate, explicit Head Office approval.',
          ),
          const SizedBox(height: 16),
          for (final entry in entries)
            Card(
              child: InkWell(
                key: ValueKey(entry.route),
                onTap: () => Navigator.of(context).pushNamed(entry.route),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(entry.icon,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(entry.detail),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Regional state/LGA delivery tariffs are not exposed by the current '
            'Marketplace API; this screen uses its existing global fee configuration. '
            'Commission history shows stored order amounts, not invented payouts.',
          ),
        ],
      ),
    );
  }
}
