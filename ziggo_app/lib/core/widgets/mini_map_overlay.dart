import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';
import '../../modules/customer/booking_provider.dart';
import '../map/ziggo_map.dart';

/// BRD: Picture-in-picture mini-map.
///
/// True OS-level PIP needs native Android `enterPictureInPictureMode()` and
/// an iOS PIPController — both are platform-channel work. Until that lands,
/// this widget is the in-app substitute: a small draggable map tile that
/// floats over whichever screen the customer has navigated to, as long as
/// they have an active booking. Tapping it returns them to the full ride
/// tracking screen.
///
/// Wrap a Navigator (or your top-level Scaffold body) with [MiniMapHost]
/// to enable it app-wide. The widget renders nothing when there's no active
/// booking, so it's safe to leave on globally.
class MiniMapHost extends StatefulWidget {
  final Widget child;
  final void Function(BuildContext)? onTap;
  const MiniMapHost({super.key, required this.child, this.onTap});

  @override
  State<MiniMapHost> createState() => _MiniMapHostState();
}

class _MiniMapHostState extends State<MiniMapHost> {
  // Position in screen coords. Persists across rebuilds in this host's state.
  Offset _offset = const Offset(20, 120);

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingProvider>();
    final active = booking.activeBooking;
    final shouldShow = active != null &&
        active['status'] != 'completed' &&
        active['status'] != 'cancelled' &&
        // Only show when the user is NOT already on the tracking screen; the
        // tracking screen wraps itself in MiniMapHost too but uses
        // ModalRoute.isFirst to check we're somewhere else. Simpler proxy
        // is the `widget.onTap` field — if no tap handler, we hide.
        widget.onTap != null;

    return Stack(
      children: [
        widget.child,
        if (shouldShow)
          Positioned(
            left: _offset.dx, top: _offset.dy,
            child: GestureDetector(
              onTap: () => widget.onTap!(context),
              onPanUpdate: (d) => setState(() => _offset += d.delta),
              child: _MiniTile(active: active!),
            ),
          ),
      ],
    );
  }
}

class _MiniTile extends StatelessWidget {
  final Map<String, dynamic> active;
  const _MiniTile({required this.active});

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(
      (active['pickup_lat'] as num).toDouble(),
      (active['pickup_lng'] as num).toDouble(),
    );
    final drop = LatLng(
      (active['drop_lat'] as num).toDouble(),
      (active['drop_lng'] as num).toDouble(),
    );
    final ref = active['booking_ref']?.toString() ?? '';
    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 150, height: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppStyles.shadowLg,
          border: Border.all(color: AppColors.cardBorder, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Static (no controller — non-interactive) tile of the route.
              IgnorePointer(
                child: ZiggoMap(
                  controller: ZiggoMapController(),
                  center: LatLng(
                    (pickup.latitude + drop.latitude) / 2,
                    (pickup.longitude + drop.longitude) / 2,
                  ),
                  zoom: 12,
                  showMyLocation: false,
                  markers: [
                    pinMarker(point: pickup,
                        icon: Icons.my_location_rounded, color: AppColors.flash),
                    pinMarker(point: drop,
                        icon: Icons.location_on_rounded, color: AppColors.error),
                  ],
                ),
              ),
              Positioned(
                left: 6, right: 6, bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car_rounded,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          ref,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
