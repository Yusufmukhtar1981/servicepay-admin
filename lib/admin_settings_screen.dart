import 'package:flutter/material.dart';

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

  bool airtimeEnabled = true;
  bool dataEnabled = true;
  bool electricityEnabled = true;
  bool ninVerificationEnabled = true;

  bool maintenanceMode = false;

  final TextEditingController supportPhoneController =
      TextEditingController(
    text: '08000000000',
  );

  final TextEditingController supportEmailController =
      TextEditingController(
    text: 'support@servicepay.ng',
  );

  final TextEditingController minimumElectricityController =
      TextEditingController(
    text: '1000',
  );

  final TextEditingController maximumElectricityController =
      TextEditingController(
    text: '200000',
  );

  bool isSaving = false;

  @override
  void dispose() {
    supportPhoneController.dispose();
    supportEmailController.dispose();
    minimumElectricityController.dispose();
    maximumElectricityController.dispose();
    super.dispose();
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

  Future<void> saveSettings() async {
    FocusScope.of(context).unfocus();

    final double? minimumElectricity =
        double.tryParse(
      minimumElectricityController.text.trim(),
    );

    final double? maximumElectricity =
        double.tryParse(
      maximumElectricityController.text.trim(),
    );

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

    if (supportPhoneController.text.trim().isEmpty) {
      showMessage(
        'Support phone number is required.',
        isError: true,
      );
      return;
    }

    if (supportEmailController.text.trim().isEmpty) {
      showMessage(
        'Support email is required.',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    await Future.delayed(
      const Duration(
        milliseconds: 700,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isSaving = false;
    });

    showMessage(
      'Settings saved locally. Backend connection will be added next.',
    );
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
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
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
              title: 'Service Availability',
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
                  value: airtimeEnabled,
                  onChanged: (value) {
                    setState(() {
                      airtimeEnabled = value;
                    });
                  },
                ),
                _SettingSwitchTile(
                  icon: Icons.wifi_rounded,
                  title: 'Data',
                  subtitle:
                      'Allow customers to buy data',
                  value: dataEnabled,
                  onChanged: (value) {
                    setState(() {
                      dataEnabled = value;
                    });
                  },
                ),
                _SettingSwitchTile(
                  icon:
                      Icons.electric_bolt_rounded,
                  title: 'Electricity',
                  subtitle:
                      'Allow electricity bill payments',
                  value: electricityEnabled,
                  onChanged: (value) {
                    setState(() {
                      electricityEnabled = value;
                    });
                  },
                ),
                _SettingSwitchTile(
                  icon:
                      Icons.verified_user_rounded,
                  title: 'NIN Verification',
                  subtitle:
                      'Allow customers to verify NIN',
                  value: ninVerificationEnabled,
                  showDivider: false,
                  onChanged: (value) {
                    setState(() {
                      ninVerificationEnabled = value;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(
              height: 20,
            ),

            const _SectionTitle(
              title: 'Electricity Limits',
            ),

            const SizedBox(
              height: 10,
            ),

            _SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextField(
                        controller:
                            minimumElectricityController,
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
              title: 'Platform Control',
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
                      const Color(0xFFF59E0B),
                  title: 'Maintenance Mode',
                  subtitle:
                      'Temporarily disable customer services',
                  value: maintenanceMode,
                  showDivider: false,
                  onChanged: (value) {
                    setState(() {
                      maintenanceMode = value;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(
              height: 20,
            ),

            const _SectionTitle(
              title: 'Customer Support',
            ),

            const SizedBox(
              height: 10,
            ),

            _SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextField(
                        controller:
                            supportPhoneController,
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
              child: FilledButton.icon(
                onPressed:
                    isSaving ? null : saveSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
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
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.save_rounded,
                      ),
                label: Text(
                  isSaving
                      ? 'Saving...'
                      : 'Save Settings',
                  style: const TextStyle(
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
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
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
                    color: Colors.white,
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
                    color: Colors.white,
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
        color: Color(0xFF0F172A),
        fontSize: 16,
        fontWeight: FontWeight.w800,
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
  final ValueChanged<bool> onChanged;
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
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(
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
                  style: const TextStyle(
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
                  style: const TextStyle(
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