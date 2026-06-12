import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app/app_theme.dart';
import 'core/map/maps_web_loader_stub.dart'
    if (dart.library.html) 'core/map/maps_web_loader.dart';
import 'core/network/api_client.dart';
import 'core/notifications/fcm_service.dart';
import 'modules/auth/auth_provider.dart';
import 'modules/auth/screens/role_selection_screen.dart';
import 'modules/common/screens/splash_screen.dart';
import 'modules/customer/addresses_provider.dart';
import 'modules/customer/booking_provider.dart';
import 'modules/customer/food_provider.dart';
import 'modules/customer/market_provider.dart';
import 'modules/customer/notifications_provider.dart';
import 'modules/customer/promos_provider.dart';
import 'modules/customer/screens/customer_shell.dart';
import 'modules/customer/wallet_provider.dart';
import 'modules/customer/payment_methods_provider.dart';
import 'modules/driver/driver_provider.dart';
import 'modules/driver/screens/driver_home_screen.dart';
import 'modules/market_vendor/market_vendor_provider.dart';
import 'modules/market_vendor/screens/market_vendor_home_screen.dart';
import 'modules/restaurant/restaurant_provider.dart';
import 'modules/restaurant/screens/restaurant_home_screen.dart';

Future<void> main() async {
  // TEMP DIAGNOSTIC (remove once the iOS white screen is fixed): turn any
  // uncaught error into a visible red screen instead of a blank white one, so a
  // release/TestFlight build is debuggable without a console.
  ErrorWidget.builder =
      (FlutterErrorDetails details) => _DiagError('build', details.exceptionAsString());

  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Load .env into dotenv.env BEFORE anything reads it (MapsService etc.).
    // If the file is missing we keep going with empty values rather than
    // crashing the whole app — the maps will just no-op.
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // ignore — runs with empty env
    }
    // On web, inject the Google Maps JS SDK now that we have the key. No-op on
    // mobile/desktop where the SDK comes from native config.
    injectGoogleMapsJs(dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '');
    // Best-effort backend host discovery. This must NEVER prevent runApp:
    // .timeout() only guards the *duration* — a thrown error (MissingPluginException,
    // SharedPreferences, a failed probe) would otherwise crash main() before the
    // first frame and leave the app stuck on the white launch screen. ApiConfig
    // falls back to its default host, so screens still render and work.
    try {
      await ApiClient.init().timeout(const Duration(seconds: 4));
    } catch (_) {}
    runApp(const ZiggoApp());
    // Initialise Firebase (FCM) AFTER the first frame. APNs/token retrieval must
    // never gate runApp — on iOS getToken() blocks until APNs registration
    // completes, which would white-screen the app. FcmService.init() guards its
    // own failures internally.
    unawaited(FcmService.instance.init());
  }, (error, stack) {
    // Any error escaping main() before the first frame lands here — show it.
    runApp(_DiagError('startup', '$error'));
  });
}

class _DiagError extends StatelessWidget {
  final String phase;
  final String message;
  const _DiagError(this.phase, this.message);
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF7F1D1D),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'ZIGGO_DIAG $phase error\n\n$message',
          style: const TextStyle(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class ZiggoApp extends StatelessWidget {
  const ZiggoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..bootstrap()),
        ChangeNotifierProvider(create: (_) => BookingProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => FoodProvider()),
        ChangeNotifierProvider(create: (_) => MarketProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider(create: (_) => PromosProvider()),
        ChangeNotifierProvider(create: (_) => AddressesProvider()),
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => RestaurantProvider()),
        ChangeNotifierProvider(create: (_) => MarketVendorProvider()),
        ChangeNotifierProvider(create: (_) => PaymentMethodsProvider()..fetchCards()),
      ],
      child: MaterialApp(
        title: 'Ziggo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.unknown},
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _splashed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashed) return const SplashScreen();
    final auth = context.watch<AuthProvider>();
    if (auth.status != AuthStatus.authenticated) {
      return const RoleSelectionScreen();
    }
    // Bootstrap booking realtime once authenticated
    final booking = context.read<BookingProvider>();
    if (auth.token != null && !booking.ws.isConnected) {
      booking.connectRealtime(auth.token!);
      booking.loadActive();
    }
    if (auth.role == 'driver') return const DriverHomeScreen();
    if (auth.role == 'restaurant_owner') return const RestaurantHomeScreen();
    if (auth.role == 'market_owner') return const MarketVendorHomeScreen();
    return const CustomerShell();
  }
}
