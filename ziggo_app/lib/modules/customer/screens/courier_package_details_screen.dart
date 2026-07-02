import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../app/app_colors.dart';
import '../booking_provider.dart';
import 'courier_confirm_details_screen.dart';

class PackageDetail {
  final TextEditingController weightController = TextEditingController();
  String? itemType;

  Map<String, dynamic> toMap() {
    return {
      'weight_kg': double.tryParse(weightController.text) ?? 1.0,
      'type': itemType ?? 'Parcel',
    };
  }
}

class CourierPackageDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> pickupDetails;
  final Map<String, dynamic> dropDetails;

  const CourierPackageDetailsScreen({
    super.key,
    required this.pickupDetails,
    required this.dropDetails,
  });

  @override
  State<CourierPackageDetailsScreen> createState() => _CourierPackageDetailsScreenState();
}

class _CourierPackageDetailsScreenState extends State<CourierPackageDetailsScreen> {
  final List<PackageDetail> _packages = [PackageDetail()];
  double? _maxWeight = 15.0; // Default until fetched, null means no limit
  bool _isLoadingTiers = true;

  @override
  void initState() {
    super.initState();
    _fetchMaxWeight();
  }

  Future<void> _fetchMaxWeight() async {
    // Tiers are shared for both flash and courier
    try {
      // Using provider pattern although we don't strictly need it in the tree here
      final provider = Provider.of<BookingProvider>(context, listen: false);
      final tiers = await provider.fetchFlashTiers();
      if (tiers.isNotEmpty) {
        bool hasOpenEnded = false;
        double highestMax = 0;
        for (var t in tiers) {
          if (t['max_weight_kg'] == null) {
            hasOpenEnded = true;
            break;
          }
          final maxW = (t['max_weight_kg'] as num).toDouble();
          if (maxW > highestMax) highestMax = maxW;
        }
        if (mounted) {
          setState(() {
            _maxWeight = hasOpenEnded ? null : highestMax;
            _isLoadingTiers = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingTiers = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTiers = false);
      }
    }
  }

  void _addPackage() {
    if (_packages.length < 20) {
      setState(() {
        _packages.add(PackageDetail());
      });
    }
  }

  void _removeItem(int index) {
    if (_packages.length > 1) {
      setState(() {
        _packages.removeAt(index);
      });
    }
  }

  void _selectItemType(PackageDetail pkg) {
    final types = ['Documents', 'Parcel', 'Clothing', 'Food', 'Electronics', 'Other'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Select item type',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              ...types.map((t) => ListTile(
                title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: pkg.itemType == t ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                onTap: () {
                  setState(() => pkg.itemType = t);
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        );
      },
    );
  }

  bool _isReady() {
    for (var pkg in _packages) {
      if (pkg.weightController.text.trim().isEmpty) return false;
      if (pkg.itemType == null) return false;
    }
    return true;
  }

  void _onNext() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourierConfirmDetailsScreen(
          pickupDetails: widget.pickupDetails,
          dropDetails: widget.dropDetails,
          packages: _packages.map((e) => e.toMap()).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDEDED),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Courier',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // Progress bar (step 2 active)
          Container(
            color: const Color(0xFFEDEDED),
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: List.generate(3, (i) {
                final done = i <= 1;
                return Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: done ? AppColors.primary : const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const Text(
                  'Package details',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter the correct package details to calculate the estimated fare.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Illustration
                Center(
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: 140,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B), // scale base
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary, width: 3),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        child: Icon(Icons.inventory_2_rounded, size: 80, color: const Color(0xFFC48658)),
                      ),
                      Positioned(
                        bottom: 80,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 3),
                          ),
                          child: const Center(
                            child: Icon(Icons.access_time_rounded, size: 24, color: AppColors.primary), // makeshift scale dial
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                ...List.generate(_packages.length, (index) {
                  final pkg = _packages[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.inventory_2_rounded, color: Color(0xFFC48658)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Package ${index + 1}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            if (_isLoadingTiers)
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            else if (_maxWeight != null)
                              Text(
                                'Max: ${_maxWeight!.toStringAsFixed(0)}Kg',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                              ),
                            if (_packages.length > 1) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _removeItem(index),
                                child: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Weight input
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: pkg.weightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                    TextInputFormatter.withFunction((oldValue, newValue) {
                                      if (newValue.text.isEmpty) return newValue;
                                      final double? val = double.tryParse(newValue.text);
                                      if (val == null || (_maxWeight != null && val > _maxWeight!) || val < 0) {
                                        return oldValue;
                                      }
                                      return newValue;
                                    }),
                                  ],
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '0',
                                    hintStyle: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textTertiary),
                                  ),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const Text(
                                '(Kg)',
                                style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Item type selector
                        GestureDetector(
                          onTap: () => _selectItemType(pkg),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.shopping_bag_outlined, color: AppColors.textPrimary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Item type',
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                      ),
                                      Text(
                                        pkg.itemType ?? 'Select item type',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: pkg.itemType != null ? AppColors.textPrimary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                
                // Add more packages row
                if (_packages.length < 20)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Got more packages? (Max 20)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                        ),
                        GestureDetector(
                          onTap: _addPackage,
                          child: const Text(
                            'Add package',
                            style: TextStyle(
                              color: Color(0xFFF59E0B), // orange-ish color as per screenshot
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 100),
              ],
            ),
          ),
          
          // Next button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isReady() ? _onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCFD5DF),
                    disabledBackgroundColor: const Color(0xFFCFD5DF),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return const Color(0xFFCFD5DF);
                      }
                      return AppColors.primary;
                    }),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: _isReady() ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: _isReady() ? Colors.white : AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
