import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class LegalLinks {
  static String get privacyPolicyUrl =>
      dotenv.env['PRIVACY_POLICY_URL']?.trim() ?? '';

  static String get accountDeletionUrl =>
      dotenv.env['ACCOUNT_DELETION_URL']?.trim() ?? '';
}
