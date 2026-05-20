// Web-only implementation. Injects the Google Maps JS SDK script tag at
// runtime using the API key loaded from .env. Conditional-imported from
// main.dart so this file never compiles on mobile/desktop where dart:html
// is unavailable.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void injectGoogleMapsJs(String apiKey) {
  if (apiKey.isEmpty) return;
  // Idempotent — don't inject twice on hot-restart.
  final existing = html.document.querySelector('script[data-ziggo-maps]');
  if (existing != null) return;

  final script = html.ScriptElement()
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=$apiKey&libraries=places'
    ..async = true
    ..defer = true;
  script.setAttribute('data-ziggo-maps', '1');
  html.document.head?.append(script);
}
