import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../restaurant_provider.dart';

class RestaurantOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const RestaurantOrderDetailScreen({super.key, required this.order});

  @override
  State<RestaurantOrderDetailScreen> createState() =>
      _RestaurantOrderDetailScreenState();
}

class _RestaurantOrderDetailScreenState
    extends State<RestaurantOrderDetailScreen> {
  late Map<String, dynamic> _order;
  String _initialStatus = '';
  List<Map<String, dynamic>> _lineItems = const [];
  bool _busy = false;
  bool _loadingDetail = true;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    _initialStatus = _order['status']?.toString() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDetail());
  }

  Future<void> _fetchDetail() async {
    final id = _order['id'] as int?;
    if (id == null) {
      setState(() => _loadingDetail = false);
      return;
    }
    final detail = await context.read<RestaurantProvider>().fetchOrderDetail(id);
    if (!mounted) return;
    setState(() {
      if (detail != null) {
        _order = detail;
        final raw = detail['items'];
        if (raw is List) {
          _lineItems = raw.cast<Map<String, dynamic>>();
        }
      }
      _loadingDetail = false;
    });
  }

  Map<String, dynamic>? _latestFromProvider(RestaurantProvider r) {
    final id = _order['id'];
    for (final list in [r.pendingOrders, r.activeOrders, r.historyOrders]) {
      for (final o in list) {
        if (o['id'] == id) return o;
      }
    }
    return null;
  }

  Future<void> _callCustomer() async {
    final phone = _order['customer_phone']?.toString();
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _accept() async {
    final id = _order['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    final err = await context.read<RestaurantProvider>().acceptOrder(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    _toast('Order accepted — start preparing');
  }

  Future<void> _markPreparing() async {
    final id = _order['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    final err = await context.read<RestaurantProvider>().markPreparing(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    _toast('Kitchen has started — tap Mark Ready once packed');
  }

  Future<void> _markReady() async {
    final id = _order['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    final err = await context.read<RestaurantProvider>().markReady(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    _toast('Marked ready — finding a rider');
  }

  Future<void> _rebroadcast() async {
    final id = _order['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    final err = await context.read<RestaurantProvider>().rebroadcast(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    _toast('Looking for a rider again…');
  }

  Future<void> _reject() async {
    final id = _order['id'] as int?;
    if (id == null) return;
    final reason = await _askReason();
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final err = await context
        .read<RestaurantProvider>()
        .rejectOrder(id, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    _toast('Order rejected. Customer refunded if wallet-paid.');
    Navigator.pop(context);
  }

  static const List<String> _kReasonTemplates = [
    'Item out of stock',
    'Kitchen too busy right now',
    'Closing early today',
    'Restaurant is closed',
    'Cannot reach customer',
    'Other',
  ];

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        String selected = '';
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Reject order'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick a reason — customer is refunded automatically if they paid by wallet.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                StatefulBuilder(builder: (ctx, setChips) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in _kReasonTemplates)
                        GestureDetector(
                          onTap: () => setChips(() {
                            selected = r;
                            if (r != 'Other') ctrl.text = r;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected == r
                                  ? AppColors.error.withOpacity(0.12)
                                  : AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: selected == r
                                    ? AppColors.error
                                    : AppColors.cardBorder,
                                width: selected == r ? 1.4 : 1,
                              ),
                            ),
                            child: Text(
                              r,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: selected == r
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Custom note (optional)',
                    hintText: 'Add a short message for the customer',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final txt = ctrl.text.trim();
                if (txt.isEmpty) return;
                Navigator.pop(ctx, txt);
              },
              child: const Text('Reject'),
            ),
          ],
        );
      }),
    );
    return reason;
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RestaurantProvider>();
    final latest = _latestFromProvider(r);
    if (latest != null) _order = latest;
    final status = _order['status']?.toString() ?? '';

    if (_initialStatus != 'delivered' && status == 'delivered') {
      _initialStatus = 'delivered'; // Prevent multiple pops
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          _order['order_ref']?.toString() ?? 'Order',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: staggered([
          _HeroStatus(order: _order),
          const SizedBox(height: 14),
          _Section(
            title: 'CUSTOMER',
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _order['customer_name']?.toString() ?? 'Customer',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _order['customer_phone']?.toString() ?? '',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if ((_order['customer_phone']?.toString() ?? '').isNotEmpty)
                  GestureDetector(
                    onTap: _callCustomer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'DELIVERY ADDRESS',
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.location_on_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _order['delivery_address']?.toString() ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if ((_order['instructions']?.toString() ?? '').isNotEmpty)
            _Section(
              title: 'CUSTOMER NOTES',
              child: Text(
                _order['instructions'].toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          _Section(
            title: 'ITEMS TO COOK',
            child: _loadingDetail
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  )
                : _lineItems.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No items found on this order.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (final it in _lineItems)
                            _LineItemRow(line: it),
                        ],
                      ),
          ),
          _Section(
            title: 'BILL',
            child: Column(
              children: [
                _kv(
                  'Order Value',
                  'Rs.${(_order['final_amount'] as num? ?? 0).toStringAsFixed(0)}',
                ),
                _kv(
                  'Delivery Fee',
                  '-Rs.${(_order['delivery_fee'] as num? ?? 0).toStringAsFixed(0)}',
                ),
                _kv(
                  'Items total',
                  'Rs.${((_order['final_amount'] as num? ?? 0) - (_order['delivery_fee'] as num? ?? 0)).toStringAsFixed(0)}',
                ),
                _kv(
                  'App usage charge',
                  '-Rs.${(((_order['final_amount'] as num? ?? 0) - (_order['delivery_fee'] as num? ?? 0)) * ((_order['commission_percentage'] as num? ?? 20) / 100)).toStringAsFixed(0)}',
                ),
                const Divider(height: 18),
                _kv(
                  'Net Earnings',
                  'Rs.${(((_order['final_amount'] as num? ?? 0) - (_order['delivery_fee'] as num? ?? 0)) * (1 - ((_order['commission_percentage'] as num? ?? 20) / 100))).toStringAsFixed(0)}',
                  bold: true,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (_order['payment_method'] ?? '').toString().toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _paymentTone(_order['payment_status']?.toString())
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (_order['payment_status'] ?? '').toString().toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1,
                          color: _paymentTone(
                              _order['payment_status']?.toString()),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
      bottomNavigationBar: _ActionBar(
        status: status,
        busy: _busy,
        driverAssigned: _order['driver_id'] != null,
        onAccept: _accept,
        onReject: _reject,
        onMarkPreparing: _markPreparing,
        onMarkReady: _markReady,
        onRebroadcast: _rebroadcast,
      ),
    );
  }

  Color _paymentTone(String? s) {
    switch (s) {
      case 'paid':
        return AppColors.success;
      case 'refunded':
        return AppColors.info;
      case 'pending':
        return AppColors.warning;
    }
    return AppColors.textSecondary;
  }

  Future<void> _downloadInvoice() async {
    final pdf = pw.Document();

    final imageBytes = await rootBundle.load('assets/images/light.png');
    final logoImage = pw.MemoryImage(imageBytes.buffer.asUint8List());

    final fmt = NumberFormat.currency(symbol: 'Rs.', decimalDigits: 2);
    final orderRef = _order['order_ref']?.toString() ?? 'Invoice';
    final date = _order['created_at']?.toString().substring(0, 16) ?? '';
    
    final finalAmount = (_order['final_amount'] as num?)?.toDouble() ?? 0.0;
    final deliveryFee = (_order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final itemTotal = finalAmount - deliveryFee;
    final commPct = (_order['commission_percentage'] as num?)?.toDouble() ?? 20.0;
    final commission = itemTotal * (commPct / 100.0);
    final netEarnings = itemTotal - commission;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Image(logoImage, height: 60)),
              pw.SizedBox(height: 20),
              pw.Header(
                level: 0,
                child: pw.Text(
                  'ZIGGO RESTAURANT INVOICE',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Order Ref: $orderRef',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Date: $date'),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Text(
                'Financial Details',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gross Items Total'),
                  pw.Text(fmt.format(itemTotal)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Delivery Fee'),
                  pw.Text(fmt.format(deliveryFee)),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('App usage charge (${commPct.toStringAsFixed(1)}%)'),
                  pw.Text('-${fmt.format(commission)}'),
                ],
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Net Earnings',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    fmt.format(netEarnings),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'ziggo_restaurant_invoice_$orderRef.pdf',
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            k,
            style: TextStyle(
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 14 : 13,
            ),
          ),
          const Spacer(),
          Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: bold ? 20 : 14,
              color: bold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatus extends StatelessWidget {
  final Map<String, dynamic> order;
  const _HeroStatus({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? '';
    final label = _label(status);
    final hint = _hint(status);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172554), Color(0xFF1E40AF), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'ORDER STATUS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _label(String s) {
    switch (s) {
      case 'pending':
        return 'New order';
      case 'confirmed':
        return 'Preparing';
      case 'preparing':
        return 'Preparing';
      case 'ready_for_pickup':
        return 'Ready for pickup';
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
    }
    return s.toUpperCase();
  }

  String _hint(String s) {
    switch (s) {
      case 'pending':
        return 'Accept to start preparing this order';
      case 'confirmed':
      case 'preparing':
        return 'Tap Mark Ready when the food is packed';
      case 'ready_for_pickup':
        return 'Looking for a rider to pick up your order';
      case 'out_for_delivery':
        return 'Rider is on the way to the customer';
      case 'delivered':
        return 'Completed — thanks for cooking with Ziggo';
      case 'cancelled':
        return 'This order will not be fulfilled';
    }
    return '';
  }
}

class _ActionBar extends StatelessWidget {
  final String status;
  final bool busy;
  final bool driverAssigned;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onMarkPreparing;
  final VoidCallback onMarkReady;
  final VoidCallback onRebroadcast;

  const _ActionBar({
    required this.status,
    required this.busy,
    required this.driverAssigned,
    required this.onAccept,
    required this.onReject,
    required this.onMarkPreparing,
    required this.onMarkReady,
    required this.onRebroadcast,
  });

  @override
  Widget build(BuildContext context) {
    Widget? body;
    if (status == 'pending') {
      body = Row(
        children: [
          Expanded(
            child: _BarBtn(
              label: 'REJECT',
              icon: Icons.close_rounded,
              color: AppColors.error,
              outlined: true,
              busy: false,
              onPressed: onReject,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _BarBtn(
              label: 'ACCEPT',
              icon: Icons.check_rounded,
              color: AppColors.primary,
              busy: busy,
              onPressed: onAccept,
            ),
          ),
        ],
      );
    } else if (status == 'confirmed') {
      body = Row(
        children: [
          Expanded(
            child: _BarBtn(
              label: 'START COOKING',
              icon: Icons.local_fire_department_rounded,
              color: AppColors.warning,
              outlined: true,
              busy: false,
              onPressed: onMarkPreparing,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BarBtn(
              label: 'MARK READY',
              icon: Icons.shopping_bag_rounded,
              color: AppColors.primary,
              busy: busy,
              onPressed: onMarkReady,
            ),
          ),
        ],
      );
    } else if (status == 'preparing') {
      body = _BarBtn(
        label: 'MARK READY FOR PICKUP',
        icon: Icons.shopping_bag_rounded,
        color: AppColors.primary,
        busy: busy,
        onPressed: onMarkReady,
      );
    } else if (status == 'ready_for_pickup' && !driverAssigned) {
      body = _BarBtn(
        label: 'FIND A RIDER AGAIN',
        icon: Icons.delivery_dining_rounded,
        color: AppColors.warning,
        busy: busy,
        onPressed: onRebroadcast,
      );
    }
    if (body == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: body,
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final bool busy;
  final VoidCallback onPressed;

  const _BarBtn({
    required this.label,
    required this.icon,
    required this.color,
    this.outlined = false,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bg = outlined ? Colors.white : color;
    final fg = outlined ? color : Colors.white;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(outlined ? 0.15 : 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shadowColor: Colors.transparent,
          side: outlined
              ? BorderSide(color: color.withOpacity(0.4), width: 1.4)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: fg, strokeWidth: 3),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  final Map<String, dynamic> line;
  const _LineItemRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final qty = line['quantity'] as int? ?? 1;
    final isVeg = line['is_veg'] == true;
    final notes = line['notes']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${qty}x',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isVeg ? AppColors.success : AppColors.error,
                          width: 1.4,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isVeg ? AppColors.success : AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 18),
                    child: Text(
                      'Note: $notes',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Rs.${(line['line_total'] as num? ?? 0).toStringAsFixed(0)}',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
