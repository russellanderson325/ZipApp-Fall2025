import 'package:flutter/foundation.dart';

/// API keys injected at compile time via `--dart-define-from-file=.env`.
/// Never hardcode real key values here — see .env.example for local setup.
class Keys {
  static const String map = String.fromEnvironment('GOOGLE_MAPS_KEY');
}

class StripeKeys {
  static const String _testPublishable =
      String.fromEnvironment('STRIPE_PUB_KEY_TEST');
  static const String _livePublishable =
      String.fromEnvironment('STRIPE_PUB_KEY_LIVE');

  static String get publishable =>
      kDebugMode ? _testPublishable : _livePublishable;
}
