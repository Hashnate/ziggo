# Secrets in the Ziggo Flutter app

No API keys live in committed source. Every platform reads the Google Maps key
from a **gitignored** file. If you clone fresh, you must populate these 3
files before the maps work.

| Platform           | File (gitignored)                              | Key to set                       |
| ------------------ | ---------------------------------------------- | -------------------------------- |
| Dart code (Places, Directions, Geocoding) | [`ziggo_app/.env`](.env.example)         | `GOOGLE_MAPS_API_KEY=AIza...`   |
| Android (Maps SDK)         | [`ziggo_app/android/local.properties`](android/local.properties) | `MAPS_API_KEY=AIza...`          |
| iOS (Maps SDK)             | `ziggo_app/ios/Flutter/Secrets.xcconfig`       | `MAPS_API_KEY=AIza...`           |
| Web (Maps JS SDK)          | same `ziggo_app/.env` — injected at runtime by `lib/main.dart` | reuses `GOOGLE_MAPS_API_KEY` |

## First-time setup

```bash
cd ziggo_app

# Dart-side .env
cp .env.example .env
nano .env                              # paste your key

# Android
echo "MAPS_API_KEY=AIzaSyXXXXXXXX..." >> android/local.properties

# iOS
cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
nano ios/Flutter/Secrets.xcconfig      # paste your key

flutter pub get
```

## How each platform picks up the key

- **Dart code (`lib/core/map/maps_service.dart`)** — `dotenv.env['GOOGLE_MAPS_API_KEY']`. Loaded by `flutter_dotenv` at startup in [main.dart](lib/main.dart). The `.env` is registered as an asset in [`pubspec.yaml`](pubspec.yaml).
- **Android** — Gradle reads `MAPS_API_KEY` from `android/local.properties`, injects it as a `manifestPlaceholders` entry, and `AndroidManifest.xml` references it as `${MAPS_API_KEY}`.
- **iOS** — `Debug.xcconfig` and `Release.xcconfig` both `#include? "Secrets.xcconfig"`. The key flows into `Info.plist` as `$(MAPS_API_KEY)`, and `AppDelegate.swift` reads it via `Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY")` before calling `GMSServices.provideAPIKey`.
- **Web** — `web/index.html` no longer hardcodes the key. `lib/main.dart` injects the `<script src="maps.googleapis.com/maps/api/js?key=...">` tag at runtime using the value from `.env`, via the conditional-import `core/map/maps_web_loader.dart`.

## Restrict the key in Google Cloud Console

Even though the key isn't in source, it still ships in the app binary (which anyone can decompile). **Restrict it** at https://console.cloud.google.com/google/maps-apis/credentials:

- **Application restrictions** — set all that apply:
  - Android apps: package name (from `android/app/build.gradle.kts → applicationId`) + SHA-1 fingerprint
  - iOS apps: bundle ID (from `ios/Runner.xcodeproj → PRODUCT_BUNDLE_IDENTIFIER`)
  - HTTP referrers: your web domain
- **API restrictions** — tick only what you use: Maps SDK Android, Maps SDK iOS, Maps JavaScript, Places API, Directions API, Geocoding API.

With restrictions in place, a leaked key is useless to anyone else.

## Troubleshooting

**Map shows a grey "for development purposes only" watermark**
The key reached the SDK but is missing the right API restriction (or quota is exhausted). Check Google Cloud Console → APIs & Services.

**`flutter run` on Android shows "Authorization failure" in logcat**
`MAPS_API_KEY` is empty in `local.properties` — Gradle substituted an empty string into the manifest. Add the key, then `flutter clean && flutter run`.

**iOS build error: "MAPS_API_KEY undefined"**
You skipped creating `ios/Flutter/Secrets.xcconfig`. Copy from `.example` and fill in.

**Web: `google is not defined` in browser console**
`.env` is missing the key, or the `<script>` injection ran before the page registered `google`. Check the Network tab — the `maps.googleapis.com/...` request should be there. If not, your `.env` is empty.
