import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class ReleaseAccess {
  static bool get closedTestFullAccess =>
      dotenv.env['CLOSED_TEST_FULL_ACCESS']?.trim().toLowerCase() == 'true';
}
