import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/curved_navbar.dart';
import 'fare_estimate_screen.dart';
import 'home_screen.dart';
import 'market_home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

/// 5-tab shell wrapping the customer experience with a Foodix-style floating
/// navbar. Slots: 0 Mart · 1 Rides · 2 Home (raised center) · 3 Alerts · 4 Profile.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => CustomerShellState();
}

class CustomerShellState extends State<CustomerShell> {
  // Home is the center slot and the default landing tab.
  int _index = 2;

  void goToTab(int i) => setState(() => _index = i);

  final _screens = const [
    MarketHomeScreen(),
    FareEstimateScreen(),
    HomeScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLocationReady());
  }

  Future<void> _ensureLocationReady() async {
    if (!mounted) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return;
      final open = await _showLocationDialog(
        title: 'Turn on location',
        message:
            'Ziggo needs your location to find nearby rides, restaurants and shops. Please turn on Location services.',
        actionLabel: 'Open settings',
      );
      if (open == true) {
        await Geolocator.openLocationSettings();
      }
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      final open = await _showLocationDialog(
        title: 'Location permission needed',
        message:
            'You have permanently denied location access. Open app settings to allow Ziggo to use your location.',
        actionLabel: 'Open app settings',
      );
      if (open == true) {
        await Geolocator.openAppSettings();
      }
    }
  }

  Future<bool?> _showLocationDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.location_on, color: AppColors.primary, size: 36),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: CurvedNavbar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
