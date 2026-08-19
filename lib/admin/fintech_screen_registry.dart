import 'package:flutter/material.dart';
import 'admin_platform_configuration_screen.dart';

import 'admin_airtime_to_cash_screen.dart';
import 'admin_amana_screen.dart';
import 'admin_data_pricing_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_empowerment_screen.dart';
import 'admin_kyc_screen.dart';
import 'admin_manual_funding_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_product_commission_screen.dart';
import 'admin_riders_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_transactions_screen.dart';
import 'users_screen.dart';
import 'staff_management_screen.dart';
import 'admin_control_center_screen.dart';
import 'admin_partner_screen.dart';
import 'admin_business_withdrawals_screen.dart';

import 'admin_bank_reconciliation_screen.dart';
import 'admin_transaction_requery_screen.dart';
// AUTO-GENERATED SAFE REGISTRY.
// Generated only from ServicePay strict verified screens.
// Do not manually add unverified screens here.

Widget? fintechScreenForTitle(String title) {
  switch (title) {
    case 'Transaction Requery':
      return const AdminTransactionRequeryScreen();

    case 'Bank Reconciliation':
      return const AdminBankReconciliationScreen();

    case 'Agent Commissions':
      return AdminProductCommissionScreen();
    case 'Airtime To Cash':
      return AdminAirtimeToCashScreen();
    case 'All Transactions':
      return AdminTransactionsScreen();
    case 'Amana':
      return AdminAmanaScreen();
    case 'Commissions':
      return AdminProductCommissionScreen();
    case 'Commissions Setup':
      return AdminProductCommissionScreen();
    case 'Customers':
      return AdminUsersScreen();

    case 'Customer Wallets':
      return AdminUsersScreen();
    case 'Deliveries':
      return AdminDeliveryScreen();
    case 'Empowerment':
      return AdminEmpowermentScreen();

    case 'Beneficiaries':
      return AdminEmpowermentScreen();
    case 'Feature Toggles':
      return AdminSettingsScreen();
    case 'General Settings':
      return AdminSettingsScreen();
    case 'KYC Management':
      return AdminKycScreen();
    case 'Notifications':
      return AdminNotificationsScreen();
    case 'Riders':
      return AdminRidersScreen();
    case 'Roles & Permissions':
      return StaffManagementScreen();
    case 'Service Pricing':
      return AdminDataPricingScreen();
    case 'Staff Management':
      return StaffManagementScreen();
    case 'Wallet Funding':
      return AdminManualFundingScreen();
    case 'Maintenance Mode':
      return AdminPlatformConfigurationScreen(
          initialSection: 'Maintenance Mode');
    case 'Service Limits':
      return AdminPlatformConfigurationScreen(initialSection: 'Service Limits');
    case 'Transaction Fees':
      return AdminPlatformConfigurationScreen(
          initialSection: 'Transaction Fees');
    case 'Legal & Policies':
      return AdminPlatformConfigurationScreen(
          initialSection: 'Legal & Policies');
    case 'Core Ledger':
      return AdminTransactionsScreen();

    case 'General Ledger':
      return AdminTransactionsScreen();

    case 'Business Wallets':
      return AdminPartnerScreen();

    case 'Wallet Credit / Debit':
      return AdminControlCenterScreen();

    case 'Balance Adjustments':
      return AdminControlCenterScreen();

    case 'Settlement Accounts':
      return AdminBusinessWithdrawalsScreen();

    default:
      return null;
  }
}
