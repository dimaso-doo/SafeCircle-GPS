import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig._();

  static bool _forcedDemoMode = false;

  static String _fromConfig(String key, String fallback) {
    if (!dotenv.isInitialized) {
      return fallback;
    }
    final envValue = dotenv.maybeGet(key);
    return envValue != null && envValue.trim().isNotEmpty ? envValue.trim() : fallback;
  }

  static bool _toBool(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }

  static String get supabaseUrl =>
      _fromConfig('SUPABASE_URL', const String.fromEnvironment('SUPABASE_URL', defaultValue: ''));

  static String get supabaseAnonKey => _fromConfig(
        'SUPABASE_ANON_KEY',
        const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
      );

  static String get googleMapsAndroidApiKey => _fromConfig(
        'GOOGLE_MAPS_ANDROID_API_KEY',
        const String.fromEnvironment('GOOGLE_MAPS_ANDROID_API_KEY', defaultValue: ''),
      );

  static String get googleMapsIosApiKey => _fromConfig(
        'GOOGLE_MAPS_IOS_API_KEY',
        const String.fromEnvironment('GOOGLE_MAPS_IOS_API_KEY', defaultValue: ''),
      );

  static String get applePremiumSubscriptionIds => _fromConfig(
        'APPLE_PREMIUM_SUBSCRIPTION_IDS',
        const String.fromEnvironment('APPLE_PREMIUM_SUBSCRIPTION_IDS', defaultValue: ''),
      );

  static String get googlePremiumSubscriptionIds => _fromConfig(
        'GOOGLE_PREMIUM_SUBSCRIPTION_IDS',
        const String.fromEnvironment('GOOGLE_PREMIUM_SUBSCRIPTION_IDS', defaultValue: ''),
      );

  static String get supabaseOAuthRedirectScheme => _fromConfig(
        'SUPABASE_OAUTH_REDIRECT_SCHEME',
        const String.fromEnvironment('SUPABASE_OAUTH_REDIRECT_SCHEME', defaultValue: 'com.safecircle.gps'),
      );

  static bool get demoMode {
    if (_forcedDemoMode) {
      return true;
    }
    return _toBool(
      _fromConfig(
        'SAFE_CIRCLE_DEMO_MODE',
        const String.fromEnvironment('SAFE_CIRCLE_DEMO_MODE', defaultValue: 'false'),
      ),
    );
  }

  static bool get hasSupabaseConfig {
    return supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  }

  static bool get hasGoogleMapsConfig {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return googleMapsIosApiKey.isNotEmpty;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return googleMapsAndroidApiKey.isNotEmpty;
    }
    return false;
  }

  static bool get runInDemoMode {
    return demoMode;
  }

  static void forceDemoMode() {
    _forcedDemoMode = true;
  }

  static const String appName = 'SafeCircle GPS';
}
