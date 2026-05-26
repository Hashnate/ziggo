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
import 'modules/driver/driver_provider.dart';
import 'modules/driver/screens/driver_home_screen.dart';
import 'modules/market_vendor/market_vendor_provider.dart';
import 'modules/market_vendor/screens/market_vendor_home_screen.dart';
import 'modules/restaurant/restaurant_provider.dart';
import 'modules/restaurant/screens/restaurant_home_screen.dart';

Future<void> main() async {
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
  await ApiClient.init().timeout(
    const Duration(seconds: 4),
    onTimeout: () {},
  );
  // Initialise Firebase / FCM. Safe no-op when google-services.json /
  // GoogleService-Info.plist aren't present yet — the rest of the app boots
  // unaffected. registerWithBackend() is called from AuthProvider after a
  // successful login (we don't know the user yet here).
  await FcmService.instance.init();
  runApp(const ZiggoApp());
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
      ],
      child: MaterialApp(
        title: 'Ziggo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
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
