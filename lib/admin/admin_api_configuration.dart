/// Shared base URL for Admin HTTP clients. Build previews can redirect all
/// authenticated Admin calls without changing service-specific endpoints.
abstract final class AdminApiConfiguration {
  static const String baseUrl = String.fromEnvironment(
    'SERVICEPAY_API_BASE_URL',
    defaultValue: 'https://api.servicepay.ng/api',
  );
}