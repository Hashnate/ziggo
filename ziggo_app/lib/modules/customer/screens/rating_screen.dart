import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/confetti.dart';
import '../booking_provider.dart';

class RatingScreen extends StatefulWidget {
  final int bookingId;

  /// The booking being rated, when the caller already has it. Only the
  /// `driver` block is read; omit it and the screen fetches the booking itself.
  final Map<String, dynamic>? booking;

  const RatingScreen({super.key, required this.bookingId, this.booking});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> with TickerProviderStateMixin {
  int _stars = 0;
  final _feedbackCtrl = TextEditingController();
  bool _busy = false;

  Map<String, dynamic>? _driver;

  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);

    _driver = _driverOf(widget.booking);
    if (_driver == null) _loadDriver();
  }

  Map<String, dynamic>? _driverOf(Map<String, dynamic>? booking) {
    final d = booking?['driver'];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// The app-open prompt and deep links hand us an id only; pull the driver in
  /// so the customer can see who they are rating.
  Future<void> _loadDriver() async {
    final booking =
        await context.read<BookingProvider>().fetchBooking(widget.bookingId);
    if (!mounted) return;
    final d = _driverOf(booking);
    if (d != null) setState(() => _driver = d);
  }

  String get _driverName => _driver?['full_name']?.toString().trim() ?? '';

  String get _driverFirstName => _driverName.split(' ').first;

  String get _vehicleLine {
    final parts = [
      _driver?['vehicle_model']?.toString().trim() ?? '',
      _driver?['vehicle_number']?.toString().trim() ?? '',
    ].where((p) => p.isNotEmpty);
    return parts.join('  ·  ');
  }

  @override
  void dispose() {
    _checkController.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    final booking = context.read<BookingProvider>();
    bool ok = false;
    String? caughtError;
    try {
      ok = await booking.rate(
        bookingId: widget.bookingId,
        rating: _stars,
        feedback: _feedbackCtrl.text.trim().isEmpty ? null : _feedbackCtrl.text.trim(),
      );
    } catch (e) {
      caughtError = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.popUntil(context, (r) => r.isFirst);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
        title: const Text('Could not submit', textAlign: TextAlign.center),
        content: Text(
          caughtError ?? booking.lastError ?? 'Failed to submit rating. Please try again.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _ratingLabel {
    switch (_stars) {
      case 1:
        return 'Terrible';
      case 2:
        return 'Bad';
      case 3:
        return 'Okay';
      case 4:
        return 'Great';
      case 5:
        return 'Amazing';
      default:
        return '';
    }
  }

  Color get _ratingColor {
    if (_stars <= 2) return AppColors.error;
    if (_stars == 3) return AppColors.warning;
    return AppColors.success;
  }

  void _dismiss() {
    // Persisted, not session-only: the booking stays unrated on the server, so
    // without a stored dismissal this screen re-opens on every app launch.
    context.read<BookingProvider>().dismissRating(widget.bookingId);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Confetti(
          trigger: true,
          particleCount: 100,
          child: SafeArea(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 28),
                              Center(
                                child: ScaleTransition(
                                  scale: _checkScale,
                                  child: _CompletionAvatar(driver: _driver),
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Text(
                                'Ride completed!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _driverName.isEmpty
                                    ? 'How was your ride? Your feedback helps everyone.'
                                    : 'How was your ride with $_driverFirstName?',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_vehicleLine.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: AppStyles.shadowSm,
                                    ),
                                    child: Text(
                                      _vehicleLine,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 36),
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: AppStyles.shadowSm,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: List.generate(5, (i) {
                                        final filled = i < _stars;
                                        return GestureDetector(
                                          onTap: () => setState(() => _stars = i + 1),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            curve: Curves.easeOutBack,
                                            padding: const EdgeInsets.all(2),
                                            child: Icon(
                                              filled ? Icons.star_rounded : Icons.star_outline_rounded,
                                              color: filled ? Colors.amber : Colors.grey.shade300,
                                              size: filled ? 44 : 40,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                    if (_stars > 0) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _ratingColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        child: Text(
                                          _ratingLabel,
                                          style: TextStyle(
                                            color: _ratingColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'FEEDBACK (OPTIONAL)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.cardBorder),
                                ),
                                child: TextField(
                                  controller: _feedbackCtrl,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'Anything we should know?',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              PrimaryButton(
                                label: 'SUBMIT',
                                icon: Icons.send_rounded,
                                gold: true,
                                busy: _busy,
                                onPressed: _stars == 0 ? null : _submit,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _dismiss,
                                child: const Text(
                                  'Skip for now',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Top-right corner close button
                Positioned(
                  top: 12,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _dismiss,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppStyles.shadowSm,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The completion badge at the top of the rating screen. With a driver it is
/// their photo (or initial) ringed by the brand gradient, with the tick moved
/// to a corner badge; with no driver it stays the plain tick it has always been.
class _CompletionAvatar extends StatelessWidget {
  final Map<String, dynamic>? driver;
  const _CompletionAvatar({this.driver});

  static const double _ring = 110;
  static const double _photo = 96;

  String? _photoUrl() {
    final raw = driver?['profile_photo']?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return raw.startsWith('/')
        ? '${ApiConfig.baseHost}$raw'
        : '${ApiConfig.baseHost}/$raw';
  }

  Widget _initial() {
    final name = driver?['full_name']?.toString().trim() ?? '';
    return Text(
      name.isEmpty ? 'D' : name[0].toUpperCase(),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 42,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ring = Container(
      width: _ring,
      height: _ring,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        shape: BoxShape.circle,
        boxShadow: AppStyles.goldGlow,
      ),
      child: driver == null
          ? const Icon(Icons.check_rounded, color: Colors.black, size: 60)
          : _avatar(),
    );

    if (driver == null) return ring;

    // Box sized so the badge sits on the ring's edge at roughly 45 degrees.
    return SizedBox(
      width: _ring + 16,
      height: _ring + 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: ring),
          Positioned(
            right: 5,
            bottom: 5,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: AppStyles.shadowSm,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final url = _photoUrl();
    if (url == null) return _initial();
    return ClipOval(
      child: Image.network(
        url,
        width: _photo,
        height: _photo,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox(
          width: _photo,
          height: _photo,
          child: Center(child: _initial()),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                width: _photo,
                height: _photo,
                child: Center(child: _initial()),
              ),
      ),
    );
  }
}
