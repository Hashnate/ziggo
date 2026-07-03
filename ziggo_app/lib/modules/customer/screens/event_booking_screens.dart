import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../wallet_provider.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';

import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/api_client.dart';


String _money(num v) => 'LKR ${NumberFormat('#,##0').format(v)}';

double _tierPrice(Map<String, dynamic> tier) =>
    double.tryParse(tier['price']?.toString() ?? '') ?? 0.0;

bool _tierAvailable(Map<String, dynamic> tier) {
  // Backend sends `available`; fall back to true if a tier predates the field.
  final v = tier['available'];
  return v == null ? true : v == true;
}

String? _tierWindowLabel(Map<String, dynamic> tier) {
  final startRaw = tier['sale_starts_at']?.toString();
  final endRaw = tier['sale_ends_at']?.toString();
  final start = startRaw == null ? null : DateTime.tryParse(startRaw)?.toLocal();
  final end = endRaw == null ? null : DateTime.tryParse(endRaw)?.toLocal();
  final now = DateTime.now();
  if (start != null && now.isBefore(start)) {
    return 'Starting ${DateFormat('d MMM y').format(start)}';
  }
  if (end != null) {
    return 'Only available till ${DateFormat('d MMM y').format(end)}';
  }
  return null;
}

class _OfferChip extends StatelessWidget {
  final String label;
  const _OfferChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer_rounded, size: 14, color: Color(0xFF3B82F6)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF3B82F6),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String _moneyDecimal(num v) => 'LKR ${NumberFormat('#,##0.00').format(v)}';


/// ---------------------------------------------------------------------------
/// Step 2 — Cart: pick ticket quantities per tier.
/// ---------------------------------------------------------------------------
class EventCartScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  const EventCartScreen({super.key, required this.event});

  @override
  State<EventCartScreen> createState() => _EventCartScreenState();
}

class _EventCartScreenState extends State<EventCartScreen> {
  final Map<dynamic, int> _qty = {}; // tier_id -> quantity

  List<Map<String, dynamic>> get _tiers {
    final raw = widget.event['tiers'];
    if (raw is! List) return const [];
    return raw.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  }

  double get _subtotal {
    double s = 0;
    for (final t in _tiers) {
      final id = t['id'];
      s += _tierPrice(t) * (_qty[id] ?? 0);
    }
    return s;
  }

  int get _count => _qty.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final ev = widget.event;
    final startsAt = DateTime.tryParse(ev['starts_at']?.toString() ?? '')?.toLocal();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Cart',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _eventStrip(ev, startsAt),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _OfferChip(label: 'NTB Offer'),
              _OfferChip(label: 'Save Up to 5000'),
            ],
          ),
          const SizedBox(height: 20),
          Text('Available Tickets',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          for (final t in _tiers) _tierCard(t),
        ],
      ),
      bottomNavigationBar: _count > 0 ? _checkoutBar() : null,
    );
  }

  Widget _eventStrip(Map<String, dynamic> ev, DateTime? startsAt) {
    final image = ev['image_url']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: image != null && image.isNotEmpty
                    ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200))
                    : Container(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ev['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary, letterSpacing: -0.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                if (startsAt != null)
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text('${DateFormat('d MMM').format(startsAt)}  •  ${DateFormat('h:mm a').format(startsAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
                    ],
                  ),
                if ((ev['venue']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(ev['venue'].toString(),
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierCard(Map<String, dynamic> t) {
    final id = t['id'];
    final available = _tierAvailable(t);
    final qty = _qty[id] ?? 0;
    final window = _tierWindowLabel(t);
    final isSelected = qty > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 16, offset: const Offset(0, 4))
          else
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!available)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Not Available',
                        style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                Text(t['name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.2)),
                const SizedBox(height: 4),
                Text(_money(_tierPrice(t)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                if (window != null) ...[
                  const SizedBox(height: 4),
                  Text(window,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (!available)
            Opacity(
              opacity: 0.5,
              child: _addButton(onTap: null),
            )
          else if (qty == 0)
            _addButton(onTap: () => setState(() => _qty[id] = 1))
          else
            _stepper(
              qty: qty,
              onRemove: () => setState(() {
                final n = (_qty[id] ?? 0) - 1;
                if (n <= 0) {
                  _qty.remove(id);
                } else {
                  _qty[id] = n;
                }
              }),
              onAdd: () => setState(() => _qty[id] = (_qty[id] ?? 0) + 1),
            ),
        ],
      ),
    );
  }

  Widget _addButton({VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('ADD',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white)),
              SizedBox(width: 6),
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepper({required int qty, required VoidCallback onRemove, required VoidCallback onAdd}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_rounded, size: 20, color: Colors.white),
            onPressed: onRemove,
          ),
          SizedBox(
            width: 24,
            child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }

  Widget _checkoutBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subtotal',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
                  Text(_moneyDecimal(_subtotal),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final selected = <Map<String, dynamic>>[];
                for (final t in _tiers) {
                  final id = t['id'];
                  final q = _qty[id] ?? 0;
                  if (q > 0) selected.add({...t, 'quantity': q});
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventSummaryScreen(event: widget.event, selected: selected),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 0),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              ),
              child: const Text('Checkout',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Step 3 — Summary: countdown, fee breakdown, payment, terms, Purchase.
/// ---------------------------------------------------------------------------
class EventSummaryScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  final List<Map<String, dynamic>> selected; // tiers with a 'quantity' key
  const EventSummaryScreen({super.key, required this.event, required this.selected});

  @override
  State<EventSummaryScreen> createState() => _EventSummaryScreenState();
}

class _EventSummaryScreenState extends State<EventSummaryScreen> {
  static const _windowSeconds = 5 * 60;
  late int _remaining;
  Timer? _timer;

  String _paymentMethod = 'card'; // card | wallet
  String? _promoCode;
  bool _agreed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _remaining = _windowSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Booking session expired'),
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _subtotal {
    double s = 0;
    for (final t in widget.selected) {
      s += _tierPrice(t) * (t['quantity'] as int);
    }
    return s;
  }

  // Mirror the backend: 1% convenience fee on the (discounted) subtotal.
  double get _convenienceFee => (_subtotal * 0.01);
  double get _total => _subtotal + _convenienceFee;

  String get _timerLabel {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _purchase() async {
    if (!_agreed || _busy) return;
    setState(() => _busy = true);
    
    if (_paymentMethod == 'card') {
      final wallet = context.read<WalletProvider>();
      final err = await wallet.topUpViaPayHere(context, _total);
      if (!mounted) return;
      if (err != null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
        ));
        return;
      }
    }
    try {
      final resp = await ApiClient.instance.dio.post(
        '/events/${widget.event['id']}/book',
        data: {
          'items': widget.selected
              .map((t) => {'tier_id': t['id'], 'quantity': t['quantity']})
              .toList(),
          'payment_method': 'wallet',
          if (_promoCode != null && _promoCode!.isNotEmpty) 'promo_code': _promoCode,
        },
      );
      if (!mounted) return;
      final order = Map<String, dynamic>.from(resp.data as Map);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EventTicketScreen(order: order)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.response?.data?['detail']?.toString() ?? 'Could not complete purchase';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFEF4444),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ev = widget.event;
    final startsAt = DateTime.tryParse(ev['starts_at']?.toString() ?? '')?.toLocal();
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F2F4),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Summary',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text.rich(
              TextSpan(
                text: 'Complete booking in ',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                children: [
                  TextSpan(text: '$_timerLabel mins',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _eventStrip(ev, startsAt),
                const SizedBox(height: 16),
                _ticketStubBreakdown(),
                const SizedBox(height: 16),
                _paymentCard(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _purchaseBar(),
    );
  }

  Widget _eventStrip(Map<String, dynamic> ev, DateTime? startsAt) {
    final image = ev['image_url']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: image != null && image.isNotEmpty
                    ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200))
                    : Container(color: Colors.grey.shade200),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ev['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary, letterSpacing: -0.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                if (startsAt != null)
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text('${DateFormat('d MMM').format(startsAt)}  •  ${DateFormat('h:mm a').format(startsAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
                    ],
                  ),
                if ((ev['venue']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(ev['venue'].toString(),
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticketStubBreakdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (final t in widget.selected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${t['quantity']}x',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(t['name']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                        Text(NumberFormat('#,##0.00').format(_tierPrice(t) * (t['quantity'] as int)),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                _row('Subtotal', NumberFormat('#,##0.00').format(_subtotal)),
                const SizedBox(height: 8),
                _row('Convenience Fee', '+${NumberFormat('#,##0.00').format(_convenienceFee)}', info: true),
              ],
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Container(width: 10, height: 20, decoration: const BoxDecoration(color: Color(0xFFF1F2F4), borderRadius: BorderRadius.horizontal(right: Radius.circular(20)))),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final count = (constraints.constrainWidth() / 8).floor();
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(count, (_) => const SizedBox(width: 4, height: 2, child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey)))),
                          );
                        },
                      ),
                    ),
                    Container(width: 10, height: 20, decoration: const BoxDecoration(color: Color(0xFFF1F2F4), borderRadius: BorderRadius.horizontal(left: Radius.circular(20)))),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total (LKR)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(NumberFormat('#,##0.00').format(_total),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool info = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700, fontSize: 13)),
            if (info) ...[
              const SizedBox(width: 4),
              const Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
            ],
          ],
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ],
    );
  }

  Widget _paymentCard() {
    final isWallet = _paymentMethod == 'wallet';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isWallet ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded,
                      color: const Color(0xFF22C55E), size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isWallet ? 'Ziggo Wallet' : 'Card',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      if (!isWallet)
                        const Text('Pay securely with your card',
                            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickPayment,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 0),
                  ),
                  child: const Text('Change',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F2F4)),
          InkWell(
            onTap: _enterPromo,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_offer_rounded, color: Colors.black54, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Promo Code', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            Text(
                              _promoCode == null || _promoCode!.isEmpty
                                  ? '4 promotions available'
                                  : 'Applied: $_promoCode',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _promoCode == null || _promoCode!.isEmpty
                                    ? const Color(0xFF22C55E)
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: const [
                      _OfferChip(label: 'NTB Offer'),
                      _OfferChip(label: 'Save Up to 5000'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pickPayment() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Payment method',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.credit_card_rounded, color: AppColors.textPrimary),
              title: const Text('Card', style: TextStyle(fontWeight: FontWeight.w800)),
              trailing: _paymentMethod == 'card'
                  ? Icon(Icons.check_circle_rounded, color: AppColors.textPrimary)
                  : null,
              onTap: () {
                setState(() => _paymentMethod = 'card');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF22C55E)),
              title: const Text('Ziggo Wallet', style: TextStyle(fontWeight: FontWeight.w800)),
              trailing: _paymentMethod == 'wallet'
                  ? Icon(Icons.check_circle_rounded, color: AppColors.textPrimary)
                  : null,
              onTap: () {
                setState(() => _paymentMethod = 'wallet');
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _enterPromo() {
    final ctrl = TextEditingController(text: _promoCode ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promo code'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. ZIGGO50'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() => _promoCode = ctrl.text.trim().toUpperCase());
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _purchaseBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, -8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the terms and conditions of the ',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      children: [
                        const TextSpan(
                          text: 'Ziggo',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' and the '),
                        const TextSpan(
                          text: 'Event',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: _agreed && !_busy ? AppColors.primaryGradient : null,
                color: _agreed && !_busy ? null : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
                boxShadow: _agreed && !_busy
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: _agreed && !_busy ? _purchase : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Purchase',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Step 4 — Ticket: confirmation + QR, fed by the real backend order.
/// ---------------------------------------------------------------------------
class EventTicketScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool fromHistory;
  const EventTicketScreen({super.key, required this.order, this.fromHistory = false});

  @override
  Widget build(BuildContext context) {
    final ev = (order['event'] as Map?) ?? const {};
    final name = ev['name']?.toString() ?? 'Event';
    final startsAt = DateTime.tryParse(ev['starts_at']?.toString() ?? '')?.toLocal();
    final ref = order['order_ref']?.toString() ?? '';
    final qrData = order['qr_payload']?.toString() ?? ref;
    final items = (order['items'] as List?) ?? const [];
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final paid = order['payment_status']?.toString() == 'paid';

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: fromHistory,
        actions: [
          IconButton(
            icon: Icon(fromHistory ? Icons.arrow_back_ios_new_rounded : Icons.close_rounded, color: Colors.white),
            onPressed: () => fromHistory
                ? Navigator.of(context).pop()
                : Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 20),
              Text(paid ? 'Payment Successful!' : 'Booking Confirmed!',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 6),
              Text(paid ? 'Here is your digital ticket. Have fun!' : 'Pay with cash at the venue. See you there!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  children: [
                    Text(name, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    if (startsAt != null)
                      Text(DateFormat('EEEE, d MMMM y · h:mm a').format(startsAt),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(thickness: 2, height: 2, color: Color(0xFFE2E8F0)),
                    ),
                    QrImageView(data: qrData, version: QrVersions.auto, size: 180),
                    const SizedBox(height: 12),
                    Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    const Text('SCAN AT ENTRANCE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(thickness: 2, height: 2, color: Color(0xFFE2E8F0)),
                    ),
                    for (final it in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${it['quantity']}x ${it['tier_name']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            Icon(Icons.check_circle_rounded, color: AppColors.textPrimary, size: 16),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total paid', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey)),
                        Text(_money(total), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => fromHistory
                      ? Navigator.of(context).pop()
                      : Navigator.of(context).popUntil((r) => r.isFirst),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.textPrimary, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(fromHistory ? 'BACK' : 'BACK TO HOME',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
