/// Where pictures go: the Apps Script web app (submissions/Code.gs) deployment URL, and its optional submit key.
///
/// By default both come from build flags, so nothing is hard-coded:
///   flutter run --dart-define=CONTRIBUTIONS_URL=https://script.google.com/macros/s/.../exec \
///               --dart-define=CONTRIBUTIONS_KEY=<SUBMIT_KEY from setup()>
/// Register your own instance in DI to read them from AppEnv or remote config instead.
class ContributionsConfig {
  const ContributionsConfig({
    required this.endpoint,
    this.submitKey = '',
    this.appVersion = '',
    this.platform = '',
  });

  factory ContributionsConfig.fromEnvironment({String appVersion = '', String platform = ''}) =>
      ContributionsConfig(
        endpoint: const String.fromEnvironment('CONTRIBUTIONS_URL'),
        submitKey: const String.fromEnvironment('CONTRIBUTIONS_KEY'),
        appVersion: appVersion,
        platform: platform,
      );

  final String endpoint;
  final String submitKey;

  /// Sent with each submission (helps when reviewing): app version and OS.
  final String appVersion;
  final String platform;

  bool get isConfigured => endpoint.startsWith('https://');
}
