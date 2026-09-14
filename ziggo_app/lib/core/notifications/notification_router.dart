import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/auth/auth_provider.dart';
import '../../modules/common/screens/ride_chat_screen.dart';
import '../../modules/customer/booking_provider.dart';
import '../../modules/customer/notifications_provider.dart';
import '../../modules/customer/screens/food_tracking_screen.dart';
import '../../modules/customer/screens/market_tracking_screen.dart';
import '../../modules/customer/screens/notifications_screen.dart';
import '../../modules/customer/screens/promotions_screen.dart';
import '../../modules/customer/screens/ride_history_screen.dart';
import '../../modules/customer/screens/ride_tracking_screen.dart';
import '../../modules/customer/screens/wallet_screen.dart';
import '../../modules/driver/screens/driver_documents_screen.dart';
import '../../modules/driver/screens/driver_earnings_screen.dart';
import '../../modules/driver/screens/driver_history_screen.dart';
import '../../modules/driver/screens/driver_notifications_screen.dart';
import '../../modules/driver/driver_provider.dart';
import 'fcm_service.dart';

/// Global navigator key allowing navigation from notification handlers
/// without needing a local BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class NotificationRouter {
  NotificationRouter._();

  /// Handle navigation based on the FCM message or local notification data payload.
  static Future<void> handleNotification(Map<String, dynamic> data) async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final auth = navContext.read<AuthProvider>();
    final role = auth.role ?? 'customer';

    final event = (data['event'] ?? data['type'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final combinedLower = '$event $title $body'.toLowerCase();

    // ── DRIVER SPECIFIC ROUTING ──────────────────────────────────────────────
    if (role == 'driver') {
      try {
        navContext.read<NotificationsProvider>().refresh();
      } catch (_) {}

      final isRequestEvent = event == 'new_ride_request' ||
          event == 'new_ride' ||
          event == 'new_market_order' ||
          event == 'new_market_request' ||
          (data.containsKey('pickup_lat') && data.containsKey('fare'));

      if (isRequestEvent) {
        final parsed = FcmService.instance.parseFcmData(data);
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
        navContext.read<DriverProvider>().setPendingRequest(parsed);
        return;
      }

      // If it's a driver chat message
      if (event == 'chat_message' && data.containsKey('booking_id')) {
        final bookingId = int.tryParse(data['booking_id'].toString()) ?? 0;
        if (bookingId > 0 && !RideChatScreen.isOpen) {
          rootNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => RideChatScreen(
                bookingId: bookingId,
                otherParticipantName: data['sender_name']?.toString() ?? 'Customer',
                isDriver: true,
              ),
            ),
          );
          return;
        }
      }

      // Earnings / Payout / Commission / Cash / Tip
      if (combinedLower.contains('payout') ||
          combinedLower.contains('earning') ||
          combinedLower.contains('wallet') ||
          combinedLower.contains('commission') ||
          combinedLower.contains('tip') ||
          event == 'payment') {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const DriverEarningsScreen()),
        );
        return;
      }

      // KYC / Documents / Approvals
      if (combinedLower.contains('document') ||
          combinedLower.contains('kyc') ||
          combinedLower.contains('license') ||
          combinedLower.contains('approved') ||
          combinedLower.contains('rejected') ||
          combinedLower.contains('verification')) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
        );
        return;
      }

      // Ride / Trip updates
      if (event == 'ride_update' ||
          event == 'booking_update' ||
          event == 'order_update' ||
          event == 'market_order_update' ||
          combinedLower.contains('ride') ||
          combinedLower.contains('trip') ||
          combinedLower.contains('booking')) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
        );
        return;
      }

      // Fallback: Open Driver Notifications Screen
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const DriverNotificationsScreen()),
      );
      return;
    }

    // ── CUSTOMER / RIDER ROUTING ────────────────────────────────────────────

    // Refresh notifications in the background so the list and unread count are fresh
    try {
      navContext.read<NotificationsProvider>().refresh();
    } catch (_) {}

    // Extract reference codes from data or body (e.g. ZG62C3F4F7, FOA1B2C3D4, MK1A2B3C4D, etc.)
    String? ref = data['booking_ref']?.toString() ??
        data['order_ref']?.toString() ??
        data['ref']?.toString();

    if (ref == null || ref.isEmpty) {
      final match = RegExp(r'\b(ZG|CR|FL|RT|FO|MK|EV)[0-9A-Z]{8}\b').firstMatch(body);
      ref = match?.group(0);
    }

    // 1. Ride / Courier / Flash / Rental
    if (event == 'booking_update' ||
        event == 'destination_updated' ||
        event == 'ride_update' ||
        (ref != null && (ref.startsWith('ZG') || ref.startsWith('CR') || ref.startsWith('FL') || ref.startsWith('RT')))) {
      final bp = navContext.read<BookingProvider>();
      await bp.loadActive();

      if (bp.activeBooking != null &&
          (ref == null || bp.activeBooking!['booking_ref'] == ref)) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
        );
      } else {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const RideHistoryScreen()),
        );
      }
      return;
    }

    // 2. Food Order Tracking
    if (event == 'food_order_update' ||
        event == 'order_update' ||
        (ref != null && ref.startsWith('FO'))) {
      if (ref != null && ref.isNotEmpty) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => FoodTrackingScreen(orderRef: ref!)),
        );
        return;
      }
    }

    // 3. Market Order Tracking
    if (event == 'market_order_update' ||
        (ref != null && ref.startsWith('MK'))) {
      if (ref != null && ref.isNotEmpty) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => MarketTrackingScreen(orderRef: ref!)),
        );
        return;
      }
    }

    // 4. Chat Message
    if (event == 'chat_message' && data.containsKey('booking_id')) {
      final bookingId = int.tryParse(data['booking_id'].toString()) ?? 0;
      if (bookingId > 0 && !RideChatScreen.isOpen) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => RideChatScreen(
              bookingId: bookingId,
              otherParticipantName: data['sender_name']?.toString() ?? 'Driver',
              isDriver: false,
            ),
          ),
        );
        return;
      }
    }

    // 5. Promotions
    if (event == 'promo' || event == 'promotions' || event == 'discount') {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const PromotionsScreen()),
      );
      return;
    }

    // 6. Payment / Wallet
    if (event == 'payment' || event == 'wallet') {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
      return;
    }

    // 7. General Broadcast / Announcements / Default (e.g. "Thank you for choosing ZIGGO...")
    // Opens Notifications Screen directly.
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }
}
