# zipapp

A new Flutter project.

## Local setup — API keys / secrets

No API key should ever be hardcoded in source. All of them are injected at build time from
gitignored local files. To set up a new dev environment:

1. Copy `.env.example` -> `.env` and fill in real values (Google Maps key, Stripe test/live
   publishable keys). Run/build the Dart side with:
   ```
   flutter run --dart-define-from-file=.env
   ```
2. Copy `android/secrets.properties.example` -> `android/secrets.properties` and fill in
   `GOOGLE_MAPS_KEY`. Picked up automatically by Gradle for Android builds.
3. Copy `ios/Flutter/Secrets.xcconfig.example` -> `ios/Flutter/Secrets.xcconfig` and fill in
   `GOOGLE_MAPS_API_KEY`. Picked up automatically for iOS builds.

None of `.env`, `android/secrets.properties`, or `ios/Flutter/Secrets.xcconfig` are tracked by
git — verify with `git check-ignore -v <file>` if ever unsure.

The Stripe **secret** key is backend-only and lives in Firebase Secret Manager
(`functions.runWith({secrets: [...]})`); it never belongs in client code or any of the files
above.

Firebase config (`firebase_options.dart`, `GoogleService-Info.plist`) is intentionally excluded
from this — Firebase API keys are meant to ship in client apps and are restricted by Firebase
Security Rules / App Check, not by secrecy. Restrict what APIs each key can call in Google Cloud
Console instead of trying to hide these values.
