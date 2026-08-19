import 'package:flutter/material.dart';

import 'admin_transactions_screen.dart';
import 'admin_business_withdrawals_screen.dart';

class AdminBankReconciliationScreen extends StatefulWidget {
  const AdminBankReconciliationScreen({super.key});

  @override
  State<AdminBankReconciliationScreen> createState() =>
      _AdminBankReconciliationScreenState();
}

class _AdminBankReconciliationScreenState
    extends State<AdminBankReconciliationScreen> {
  int selectedIndex = 0;

  static const Color primaryGreen = Color(0xFF08783E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('Bank Reconciliation'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF08783E),
                  Color(0xFF18A558),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_outlined,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'SERVICEPAY RECONCILIATION CONTROL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Text(
                  'Bank Reconciliation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Compare ServicePay transaction records with settlement and payout records.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE5EAE7),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _tabButton(
                      index: 0,
                      icon: Icons.receipt_long_outlined,
                      label: 'Transactions',
                    ),
                  ),
                  Expanded(
                    child: _tabButton(
                      index: 1,
                      icon: Icons.account_balance_outlined,
                      label: 'Settlements',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: const [
                AdminTransactionsScreen(),
                AdminBusinessWithdrawalsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool active = selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() => selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: active
              ? primaryGreen.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: active ? primaryGreen : Colors.black54,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? primaryGreen : Colors.black54,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
