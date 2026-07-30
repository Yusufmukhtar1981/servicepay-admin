import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState
    extends State<AdminSettingsScreen> {
  static const Color primaryColor =
      Color(0xFF0F766E);

  static const String baseUrl =
      'https://api.servicepay.ng/api';

  bool airtimeEnabled = true;
  bool dataEnabled = true;
  bool electricityEnabled = true;
  bool ninVerificationEnabled = true;
  bool maintenanceMode = false;

  bool isLoading = true;
  bool isSaving = false;
  bool hasError = false;

  String errorMessage = '';

  final TextEditingController
      supportPhoneController =
      TextEditingController();

  final TextEditingController
      supportEmailController =
      TextEditingController();

  final TextEditingController
      minimumElectricityController =
      TextEditingController();

  final TextEditingController
      maximumElectricityController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    supportPhoneController.dispose();
    supportEmailController.dispose();
    minimumElectricityController.dispose();
    maximumElectricityController.dispose();
    super.dispose();
  }

  Future<String?> getAdminToken() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    return prefs.getString('auth_token') ??
        prefs.getString('token');
  }

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : primaryColor,
        ),
      );
  }

  String formatAmount(dynamic value) {
    if (value == null) {
      return '';
    }

    final double? amount =
        double.tryParse(value.toString());

    if (amount == null) {
      return value.toString();
    }

    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }

    return amount.toString();
  }

  Future<void> loadSettings() async {
    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = '';
    });

    try {
      final String? token =
          await getAdminToken();

      if (token == null || token.isEmpty) {
        throw Exception(
          'Admin session has expired. Please sign in again.',
        );
      }

      final http.Response response =
          await http
              .get(
                Uri.parse(
                  '$baseUrl/settings/admin',
                ),
                headers: {
                  'Accept': 'application/json',
                  'Authorization':
                      'Bearer $token',
                },
              )
              .timeout(
                const Duration(
                  seconds: 30,
                ),
              );

      final dynamic decoded =
          jsonDecode(response.body);

      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          decoded['success'] != true) {
        final String message =
            decoded is Map<String, dynamic>
                ? decoded['message']
                        ?.toString() ??
                    'Unable to load settings.'
                : 'Unable to load settings.';

        throw Exception(message);
      }

      final Map<String, dynamic>
          settings =
          Map<String, dynamic>.from(
        decoded['settings'] as Map,
      );

      final Map<String, dynamic>
          services =
          Map<String, dynamic>.from(
        settings['services'] as Map? ??
            <String, dynamic>{},
      );

      final Map<String, dynamic>
          electricity =
          Map<String, dynamic>.from(
        settings['electricity'] as Map? ??
            <String, dynamic>{},
      );

      final Map<String, dynamic>
          platform =
          Map<String, dynamic>.from(
        settings['platform'] as Map? ??
            <String, dynamic>{},
      );

      final Map<String, dynamic>
          support =
          Map<String, dynamic>.from(
        settings['support'] as Map? ??
            <String, dynamic>{},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        airtimeEnabled =
            services['airtimeEnabled'] !=
                false;

        dataEnabled =
            services['dataEnabled'] != false;

        electricityEnabled =
            services[
                    'electricityEnabled'] !=
                false;

        ninVerificationEnabled =
            services[
                    'ninVerificationEnabled'] !=
                false;

        maintenanceMode =
            platform['maintenanceMode'] ==
                true;

        minimumElectricityController.text =
            formatAmount(
          electricity['minimumAmount'] ??
              1000,
        );

        maximumElectricityController.text =
            formatAmount(
          electricity['maximumAmount'] ??
              200000,
        );

        supportPhoneController.text =
            support['phone']?.toString() ??
                '08000000000';

        supportEmailController.text =
            support['email']?.toString() ??
                'support@servicepay.ng';

        isLoading = false;
        hasError = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final String message = error
          .toString()
          .replaceFirst(
            'Exception: ',
            '',
          );

      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = message;
      });
    }
  }

  Future<void> saveSettings() async {
    FocusScope.of(context).unfocus();

    final double? minimumElectricity =
        double.tryParse(
      minimumElectricityController.text
          .trim(),
    );

    final double? maximumElectricity =
        double.tryParse(
      maximumElectricityController.text
          .trim(),
    );

    final String supportPhone =
        supportPhoneController.text.trim();

    final String supportEmail =
        supportEmailController.text
            .trim()
            .toLowerCase();

    if (minimumElectricity == null ||
        minimumElectricity < 0) {
      showMessage(
        'Enter a valid minimum electricity amount.',
        isError: true,
      );
      return;
    }

    if (maximumElectricity == null ||
        maximumElectricity <=
            minimumElectricity) {
      showMessage(
        'Maximum electricity amount must be greater than the minimum amount.',
        isError: true,
      );
      return;
    }

    if (supportPhone.isEmpty) {
      showMessage(
        'Support phone number is required.',
        isError: true,
      );
      return;
    }

    if (supportEmail.isEmpty ||
        !supportEmail.contains('@')) {
      showMessage(
        'Enter a valid support email.',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final String? token =
          await getAdminToken();

      if (token == null || token.isEmpty) {
        throw Exception(
          'Admin session has expired. Please sign in again.',
        );
      }

      final Map<String, dynamic> body = {
        'services': {
          'airtimeEnabled':
              airtimeEnabled,
          'dataEnabled':
              dataEnabled,
          'electricityEnabled':
              electricityEnabled,
          'ninVerificationEnabled':
              ninVerificationEnabled,
        },
        'electricity': {
          'minimumAmount':
              minimumElectricity,
          'maximumAmount':
              maximumElectricity,
        },
        'platform': {
          'maintenanceMode':
              maintenanceMode,
        },
        'support': {
          'phone':
              supportPhone,
          'email':
              supportEmail,
        },
      };

      final http.Response response =
          await http
              .put(
                Uri.parse(
                  '$baseUrl/settings/admin',
                ),
                headers: {
                  'Accept': 'application/json',
                  'Content-Type':
                      'application/json',
                  'Authorization':
                      'Bearer $token',
                },
                body: jsonEncode(body),
              )
              .timeout(
                const Duration(
                  seconds: 30,
                ),
              );

      final dynamic decoded =
          jsonDecode(response.body);

      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          decoded['success'] != true) {
        final String message =
            decoded is Map<String, dynamic>
                ? decoded['message']
                        ?.toString() ??
                    'Unable to save settings.'
                : 'Unable to save settings.';

        throw Exception(message);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      showMessage(
        decoded['message']?.toString() ??
            'Settings saved successfully.',
      );

      await loadSettings();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      showMessage(
        error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            ),
        isError: true,
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Admin Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed:
                isLoading || isSaving
                    ? null
                    : loadSettings,
            tooltip: 'Refresh Settings',
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(
                  color: primaryColor,
                ),
              )
            : hasError
                ? _buildErrorState()
                : _buildSettingsContent(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons
                  .cloud_off_rounded,
              color:
                  Color(0xFFDC2626),
              size: 58,
            ),
            const SizedBox(
              height: 16,
            ),
            const Text(
              'Unable to load settings',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    Color(0xFF0F172A),
                fontSize: 20,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              errorMessage,
              textAlign:
                  TextAlign.center,
              style: const TextStyle(
                color:
                    Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            FilledButton.icon(
              onPressed: loadSettings,
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    primaryColor,
              ),
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContent() {
    return RefreshIndicator(
      color: primaryColor,
      onRefresh: loadSettings,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        children: [
          const _SettingsHeader(),

          const SizedBox(
            height: 20,
          ),

          const _SectionTitle(
            title:
                'Service Availability',
          ),

          const SizedBox(
            height: 10,
          ),

          _SettingsCard(
            children: [
              _SettingSwitchTile(
                icon:
                    Icons.phone_android_rounded,
                title: 'Airtime',
                subtitle:
                    'Allow customers to buy airtime',
                value:
                    airtimeEnabled,
                onChanged:
                    isSaving
                        ? null
                        : (value) {
                            setState(() {
                              airtimeEnabled =
                                  value;
                            });
                          },
              ),
              _SettingSwitchTile(
                icon:
                    Icons.wifi_rounded,
                title: 'Data',
                subtitle:
                    'Allow customers to buy data',
                value: dataEnabled,
                onChanged:
                    isSaving
                        ? null
                        : (value) {
                            setState(() {
                              dataEnabled =
                                  value;
                            });
                          },
              ),
              _SettingSwitchTile(
                icon:
                    Icons.electric_bolt_rounded,
                title: 'Electricity',
                subtitle:
                    'Allow electricity bill payments',
                value:
                    electricityEnabled,
                onChanged:
                    isSaving
                        ? null
                        : (value) {
                            setState(() {
                              electricityEnabled =
                                  value;
                            });
                          },
              ),
              _SettingSwitchTile(
                icon:
                    Icons.verified_user_rounded,
                title:
                    'NIN Verification',
                subtitle:
                    'Allow customers to verify NIN',
                value:
                    ninVerificationEnabled,
                showDivider: false,
                onChanged:
                    isSaving
                        ? null
                        : (value) {
                            setState(() {
                              ninVerificationEnabled =
                                  value;
                            });
                          },
              ),
            ],
          ),

          const SizedBox(
            height: 20,
          ),

          const _SectionTitle(
            title:
                'Electricity Limits',
          ),

          const SizedBox(
            height: 10,
          ),

          _SettingsCard(
            children: [
              Padding(
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller:
                          minimumElectricityController,
                      enabled: !isSaving,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Minimum Amount',
                        prefixText: '₦ ',
                        prefixIcon: Icon(
                          Icons
                              .arrow_downward_rounded,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller:
                          maximumElectricityController,
                      enabled: !isSaving,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Maximum Amount',
                        prefixText: '₦ ',
                        prefixIcon: Icon(
                          Icons
                              .arrow_upward_rounded,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 20,
          ),

          const _SectionTitle(
            title:
                'Platform Control',
          ),

          const SizedBox(
            height: 10,
          ),

          _SettingsCard(
            children: [
              _SettingSwitchTile(
                icon:
                    Icons.construction_rounded,
                iconColor:
                    const Color(
                  0xFFF59E0B,
                ),
                title:
                    'Maintenance Mode',
                subtitle:
                    'Temporarily disable customer services',
                value:
                    maintenanceMode,
                showDivider: false,
                onChanged:
                    isSaving
                        ? null
                        : (value) {
                            setState(() {
                              maintenanceMode =
                                  value;
                            });
                          },
              ),
            ],
          ),

          const SizedBox(
            height: 20,
          ),

          const _SectionTitle(
            title:
                'Customer Support',
          ),

          const SizedBox(
            height: 10,
          ),

          _SettingsCard(
            children: [
              Padding(
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller:
                          supportPhoneController,
                      enabled: !isSaving,
                      keyboardType:
                          TextInputType.phone,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Support Phone',
                        prefixIcon: Icon(
                          Icons.phone_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    TextField(
                      controller:
                          supportEmailController,
                      enabled: !isSaving,
                      keyboardType:
                          TextInputType
                              .emailAddress,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Support Email',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                        ),
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 24,
          ),

          SizedBox(
            height: 54,
            child:
                FilledButton.icon(
              onPressed:
                  isSaving
                      ? null
                      : saveSettings,
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    primaryColor,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              icon: isSaving
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2.3,
                        color:
                            Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.save_rounded,
                    ),
              label: Text(
                isSaving
                    ? 'Saving...'
                    : 'Save Settings',
                style:
                    const TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          const Text(
            'Provider API keys and secret credentials remain securely stored in Render Environment Variables.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  Color(0xFF64748B),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader
    extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
          colors: [
            Color(0xFF0F766E),
            Color(0xFF14B8A6),
          ],
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor:
                Colors.white24,
            child: Icon(
              Icons.settings_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          SizedBox(
            width: 14,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'ServicePay Controls',
                  style: TextStyle(
                    color:
                        Colors.white,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  'Manage customer services and platform settings.',
                  style: TextStyle(
                    color:
                        Colors.white,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  final String title;

  const _SectionTitle({
    required this.title,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Text(
      title,
      style: const TextStyle(
        color:
            Color(0xFF0F172A),
        fontSize: 16,
        fontWeight:
            FontWeight.w800,
      ),
    );
  }
}

class _SettingsCard
    extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({
    required this.children,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color:
              const Color(
            0xFFE2E8F0,
          ),
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingSwitchTile
    extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  const _SettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.iconColor,
    this.showDivider = true,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final Color effectiveColor =
        iconColor ??
            const Color(
              0xFF0F766E,
            );

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom:
                    BorderSide(
                  color:
                      Color(
                    0xFFE2E8F0,
                  ),
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color:
                  effectiveColor.withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                13,
              ),
            ),
            child: Icon(
              icon,
              color: effectiveColor,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Color(
                      0xFF0F172A,
                    ),
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color:
                        Color(
                      0xFF64748B,
                    ),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor:
                const Color(
              0xFF0F766E,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
