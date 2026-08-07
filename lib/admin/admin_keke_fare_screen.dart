import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminKekeFareScreen extends StatefulWidget {
  const AdminKekeFareScreen({
    super.key,
  });

  @override
  State<AdminKekeFareScreen> createState() =>
      _AdminKekeFareScreenState();
}

class _AdminKekeFareScreenState
    extends State<AdminKekeFareScreen> {
  static const String baseUrl =
      'https://api.servicepay.ng/api';

  static const Color primaryGreen =
      Color(0xFF0F766E);

  bool isLoading = true;
  bool isSaving = false;

  String? errorMessage;

  final TextEditingController baseFareController =
      TextEditingController();

  final TextEditingController minimumFareController =
      TextEditingController();

  final TextEditingController pricePerKmController =
      TextEditingController();

  final TextEditingController waitingFeeController =
      TextEditingController();

  final TextEditingController commissionController =
      TextEditingController();

  final TextEditingController searchRadiusController =
      TextEditingController();

  final TextEditingController offerSecondsController =
      TextEditingController();

  List<Map<String, dynamic>> stateSettings =
      <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    _loadSettings();
  }

  @override
  void dispose() {
    baseFareController.dispose();
    minimumFareController.dispose();
    pricePerKmController.dispose();
    waitingFeeController.dispose();
    commissionController.dispose();
    searchRadiusController.dispose();
    offerSecondsController.dispose();

    super.dispose();
  }

  Future<String?> _getToken() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    const List<String> keys = <String>[
      'auth_token',
      'token',
      'access_token',
      'accessToken',
      'jwt_token',
      'jwt',
    ];

    for (final String key in keys) {
      final String? raw =
          prefs.getString(key);

      if (raw == null ||
          raw.trim().isEmpty) {
        continue;
      }

      String token = raw.trim();

      if (token
          .toLowerCase()
          .startsWith('bearer ')) {
        token = token.substring(7).trim();
      }

      if (token.isNotEmpty) {
        return token;
      }
    }

    return null;
  }

  double _number(
    dynamic value, {
    double fallback = 0,
  }) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        fallback;
  }

  String _cleanNumber(
    dynamic value,
  ) {
    final double number =
        _number(value);

    if (number == number.roundToDouble()) {
      return number
          .round()
          .toString();
    }

    return number
        .toStringAsFixed(2);
  }

  Future<void> _loadSettings() async {
    try {
      if (mounted) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }

      final String? token =
          await _getToken();

      if (token == null) {
        throw Exception(
          'Admin login token was not found.',
        );
      }

      final http.Response response =
          await http
              .get(
        Uri.parse(
          '$baseUrl/admin/keke-fare',
        ),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      )
              .timeout(
        const Duration(
          seconds: 30,
        ),
      );

      final dynamic decoded =
          jsonDecode(response.body);

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final String message =
            decoded is Map
                ? decoded['message']
                        ?.toString() ??
                    'Unable to load Keke fare settings.'
                : 'Unable to load Keke fare settings.';

        throw Exception(message);
      }

      if (decoded is! Map) {
        throw Exception(
          'Invalid server response.',
        );
      }

      final dynamic rawSettings =
          decoded['settings'];

      if (rawSettings is! List) {
        throw Exception(
          'Keke fare settings were not received.',
        );
      }

      final List<Map<String, dynamic>> settings =
          rawSettings
              .whereType<Map>()
              .map(
                (Map item) =>
                    Map<String, dynamic>.from(item),
              )
              .toList();

      Map<String, dynamic>? global;

      final List<Map<String, dynamic>> states =
          <Map<String, dynamic>>[];

      for (final Map<String, dynamic> setting
          in settings) {
        final String scope =
            setting['scopeType']
                    ?.toString()
                    .toUpperCase() ??
                '';

        if (scope == 'GLOBAL') {
          global = setting;
        } else if (scope == 'STATE') {
          states.add(setting);
        }
      }

      if (global == null) {
        throw Exception(
          'Global Keke fare setting was not found.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        baseFareController.text =
            _cleanNumber(
          global!['baseFare'],
        );

        minimumFareController.text =
            _cleanNumber(
          global['minimumFare'],
        );

        pricePerKmController.text =
            _cleanNumber(
          global['pricePerKm'],
        );

        waitingFeeController.text =
            _cleanNumber(
          global['waitingFeePerMinute'],
        );

        commissionController.text =
            _cleanNumber(
          global['servicePayCommissionPercent'],
        );

        searchRadiusController.text =
            _cleanNumber(
          global['maxSearchDistanceKm'],
        );

        offerSecondsController.text =
            _cleanNumber(
          global['driverOfferSeconds'],
        );

        stateSettings = states;

        isLoading = false;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;

        errorMessage = error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  double? _readPositiveNumber(
    TextEditingController controller,
  ) {
    return double.tryParse(
      controller.text.trim(),
    );
  }

  Future<void> _saveGlobalSettings() async {
    if (isSaving) {
      return;
    }

    final double? baseFare =
        _readPositiveNumber(
      baseFareController,
    );

    final double? minimumFare =
        _readPositiveNumber(
      minimumFareController,
    );

    final double? pricePerKm =
        _readPositiveNumber(
      pricePerKmController,
    );

    final double? waitingFee =
        _readPositiveNumber(
      waitingFeeController,
    );

    final double? commission =
        _readPositiveNumber(
      commissionController,
    );

    final double? searchRadius =
        _readPositiveNumber(
      searchRadiusController,
    );

    final double? offerSeconds =
        _readPositiveNumber(
      offerSecondsController,
    );

    if (baseFare == null ||
        minimumFare == null ||
        pricePerKm == null ||
        waitingFee == null ||
        commission == null ||
        searchRadius == null ||
        offerSeconds == null) {
      _showMessage(
        'Please enter valid numbers in all fields.',
        error: true,
      );

      return;
    }

    if (baseFare < 0 ||
        minimumFare < 0 ||
        pricePerKm < 0 ||
        waitingFee < 0) {
      _showMessage(
        'Fare values cannot be negative.',
        error: true,
      );

      return;
    }

    if (commission < 0 ||
        commission > 100) {
      _showMessage(
        'ServicePay commission must be between 0% and 100%.',
        error: true,
      );

      return;
    }

    if (searchRadius < 1 ||
        searchRadius > 100) {
      _showMessage(
        'Search radius must be between 1km and 100km.',
        error: true,
      );

      return;
    }

    if (offerSeconds < 10 ||
        offerSeconds > 300) {
      _showMessage(
        'Driver offer time must be between 10 and 300 seconds.',
        error: true,
      );

      return;
    }

    try {
      setState(() {
        isSaving = true;
      });

      final String? token =
          await _getToken();

      if (token == null) {
        throw Exception(
          'Admin login token was not found.',
        );
      }

      final http.Response response =
          await http
              .post(
        Uri.parse(
          '$baseUrl/admin/keke-fare',
        ),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(
          <String, dynamic>{
            'scopeType': 'GLOBAL',
            'baseFare': baseFare,
            'minimumFare': minimumFare,
            'pricePerKm': pricePerKm,
            'waitingFeePerMinute':
                waitingFee,
            'servicePayCommissionPercent':
                commission,
            'maxSearchDistanceKm':
                searchRadius,
            'driverOfferSeconds':
                offerSeconds.round(),
            'active': true,
          },
        ),
      )
              .timeout(
        const Duration(
          seconds: 30,
        ),
      );

      final dynamic decoded =
          jsonDecode(response.body);

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        final String message =
            decoded is Map
                ? decoded['message']
                        ?.toString() ??
                    'Unable to save Keke fare settings.'
                : 'Unable to save Keke fare settings.';

        throw Exception(message);
      }

      _showMessage(
        decoded is Map
            ? decoded['message']
                    ?.toString() ??
                'Keke fare settings saved successfully.'
            : 'Keke fare settings saved successfully.',
      );

      await _loadSettings();
    } catch (error) {
      _showMessage(
        error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            ),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              error
                  ? Colors.red.shade700
                  : primaryGreen,
        ),
      );
  }

  double get _commissionPercent {
    return double.tryParse(
          commissionController.text.trim(),
        ) ??
        0;
  }

  double get _driverSharePercent {
    final double value =
        100 - _commissionPercent;

    if (value < 0) {
      return 0;
    }

    if (value > 100) {
      return 100;
    }

    return value;
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required IconData icon,
    String? prefix,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(
        decimal: true,
      ),
      onChanged: (_) {
        if (mounted) {
          setState(() {});
        }
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: Icon(icon),
        border:
            const OutlineInputBorder(),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(16),
          border: Border.all(
            color:
                const Color(
              0xFFE2E8F0,
            ),
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              color: primaryGreen,
              size: 25,
            ),
            const SizedBox(
              height: 7,
            ),
            Text(
              value,
              style:
                  const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              title,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Color(
                  0xFF667085,
                ),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF7F9FB,
      ),
      body: isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      24,
                    ),
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons
                              .error_outline_rounded,
                          color: Colors.red,
                          size: 55,
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        Text(
                          errorMessage!,
                          textAlign:
                              TextAlign.center,
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        FilledButton.icon(
                          onPressed:
                              _loadSettings,
                          icon:
                              const Icon(
                            Icons
                                .refresh_rounded,
                          ),
                          label:
                              const Text(
                            'Try Again',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color:
                      primaryGreen,
                  onRefresh:
                      _loadSettings,
                  child:
                      ListView(
                    padding:
                        const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      40,
                    ),
                    children: <Widget>[
                      const Text(
                        'Keke Fare Settings',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      const Text(
                        'Control ServicePay Keke pricing, driver earnings and search settings.',
                        style: TextStyle(
                          color:
                              Color(
                            0xFF667085,
                          ),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(
                        height: 20,
                      ),

                      /*
                       * COMMISSION SUMMARY
                       */
                      Row(
                        children: <Widget>[
                          _summaryCard(
                            title:
                                'ServicePay',
                            value:
                                '${_commissionPercent.toStringAsFixed(0)}%',
                            icon:
                                Icons
                                    .business_rounded,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          _summaryCard(
                            title:
                                'Driver Share',
                            value:
                                '${_driverSharePercent.toStringAsFixed(0)}%',
                            icon:
                                Icons
                                    .electric_rickshaw_rounded,
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 22,
                      ),

                      Card(
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .stretch,
                            children: <Widget>[
                              const Text(
                                'Global Fare',
                                style:
                                    TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              _numberField(
                                controller:
                                    baseFareController,
                                label:
                                    'Base Fare',
                                helper:
                                    'Starting charge before distance.',
                                icon:
                                    Icons
                                        .flag_circle_outlined,
                                prefix: '₦',
                              ),
                              const SizedBox(
                                height: 14,
                              ),
                              _numberField(
                                controller:
                                    minimumFareController,
                                label:
                                    'Minimum Fare',
                                helper:
                                    'Lowest amount a customer can pay.',
                                icon:
                                    Icons
                                        .payments_outlined,
                                prefix: '₦',
                              ),
                              const SizedBox(
                                height: 14,
                              ),
                              _numberField(
                                controller:
                                    pricePerKmController,
                                label:
                                    'Price per KM',
                                helper:
                                    'Distance charge for every kilometre.',
                                icon:
                                    Icons
                                        .route_outlined,
                                prefix: '₦',
                                suffix: '/km',
                              ),
                              const SizedBox(
                                height: 14,
                              ),
                              _numberField(
                                controller:
                                    waitingFeeController,
                                label:
                                    'Waiting Fee',
                                helper:
                                    'Charge per waiting minute.',
                                icon:
                                    Icons
                                        .timer_outlined,
                                prefix: '₦',
                                suffix: '/min',
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      Card(
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .stretch,
                            children: <Widget>[
                              const Text(
                                'Commission & Matching',
                                style:
                                    TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              _numberField(
                                controller:
                                    commissionController,
                                label:
                                    'ServicePay Commission',
                                helper:
                                    'Driver automatically receives the remaining percentage.',
                                icon:
                                    Icons
                                        .percent_rounded,
                                suffix: '%',
                              ),
                              const SizedBox(
                                height: 14,
                              ),
                              _numberField(
                                controller:
                                    searchRadiusController,
                                label:
                                    'Driver Search Radius',
                                helper:
                                    'Maximum distance for nearest-driver search.',
                                icon:
                                    Icons
                                        .radar_rounded,
                                suffix: 'km',
                              ),
                              const SizedBox(
                                height: 14,
                              ),
                              _numberField(
                                controller:
                                    offerSecondsController,
                                label:
                                    'Driver Offer Time',
                                helper:
                                    'How long a driver has to accept.',
                                icon:
                                    Icons
                                        .alarm_rounded,
                                suffix: 'seconds',
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed:
                              isSaving
                                  ? null
                                  : _saveGlobalSettings,
                          style:
                              FilledButton.styleFrom(
                            backgroundColor:
                                primaryGreen,
                          ),
                          icon: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .save_rounded,
                                ),
                          label: Text(
                            isSaving
                                ? 'Saving...'
                                : 'Save Keke Fare Settings',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      const Text(
                        'State Overrides',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      const Text(
                        'State-specific pricing will override the global fare for customers in that state.',
                        style: TextStyle(
                          color:
                              Color(
                            0xFF667085,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),

                      if (stateSettings.isEmpty)
                        Container(
                          padding:
                              const EdgeInsets.all(
                            18,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                Colors.white,
                            borderRadius:
                                BorderRadius.circular(
                              16,
                            ),
                            border:
                                Border.all(
                              color:
                                  const Color(
                                0xFFE2E8F0,
                              ),
                            ),
                          ),
                          child:
                              const Text(
                            'No state-specific Keke fare has been created yet. Global pricing is currently used everywhere.',
                            style:
                                TextStyle(
                              color:
                                  Color(
                                0xFF667085,
                              ),
                              height: 1.4,
                            ),
                          ),
                        )
                      else
                        ...stateSettings.map(
                          (
                            Map<String, dynamic>
                                setting,
                          ) {
                            final String state =
                                setting['state']
                                        ?.toString() ??
                                    'STATE';

                            return Card(
                              elevation: 0,
                              child: ListTile(
                                leading:
                                    const CircleAvatar(
                                  backgroundColor:
                                      Color(
                                    0xFFEAF7F0,
                                  ),
                                  child: Icon(
                                    Icons
                                        .location_on_rounded,
                                    color:
                                        primaryGreen,
                                  ),
                                ),
                                title: Text(
                                  state,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'Base ₦${_cleanNumber(setting['baseFare'])} • '
                                  '₦${_cleanNumber(setting['pricePerKm'])}/km • '
                                  '${_cleanNumber(setting['servicePayCommissionPercent'])}% ServicePay',
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }
}