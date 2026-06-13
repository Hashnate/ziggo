import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/motion.dart';
import '../market_provider.dart';
import 'market_home_screen.dart';

class MarketGroupScreen extends StatelessWidget {
  final String groupName;

  const MarketGroupScreen({super.key, required this.groupName});

  List<Map<String, dynamic>> _getFilteredVendors(List<Map<String, dynamic>> allVendors) {
    // Copy the list to avoid modifying the provider's original list
    final List<Map<String, dynamic>> list = List.from(allVendors);

    if (groupName == 'Popular') {
      // Sort by rating descending
      list.sort((a, b) {
        final rA = (a['rating'] as num?)?.toDouble() ?? 0.0;
        final rB = (b['rating'] as num?)?.toDouble() ?? 0.0;
        return rB.compareTo(rA);
      });
      // Try to only show rating >= 4.0, fallback if none
      final popularList = list.where((v) => ((v['rating'] as num?)?.toDouble() ?? 0.0) >= 4.0).toList();
      return popularList.isNotEmpty ? popularList : list;
    } else if (groupName == 'Newly Joined') {
      // Sort by ID descending (newer vendors have higher IDs)
      list.sort((a, b) {
        final idA = a['id'] as int? ?? 0;
        final idB = b['id'] as int? ?? 0;
        return idB.compareTo(idA);
      });
      return list;
    } else if (groupName == 'Featured Outlets') {
      // Filter by is_featured == true
      final featuredList = list.where((v) => v['is_featured'] == true).toList();
      if (featuredList.isNotEmpty) {
        return featuredList;
      }
      // Fallback: sort by rating/id desc
      list.sort((a, b) {
        final rA = (a['rating'] as num?)?.toDouble() ?? 0.0;
        final rB = (b['rating'] as num?)?.toDouble() ?? 0.0;
        return rB.compareTo(rA);
      });
      return list;
    } else if (groupName == 'Trending') {
      // Sort by rating desc
      list.sort((a, b) {
        final rA = (a['rating'] as num?)?.toDouble() ?? 0.0;
        final rB = (b['rating'] as num?)?.toDouble() ?? 0.0;
        return rB.compareTo(rA);
      });
      final trendingList = list.where((v) => ((v['rating'] as num?)?.toDouble() ?? 0.0) >= 3.5).toList();
      return trendingList.isNotEmpty ? trendingList : list;
    }

    return list;
  }

  String _getSubtitle() {
    switch (groupName) {
      case 'Popular':
        return 'Top rated outlets loved by everyone';
      case 'Newly Joined':
        return 'Fresh new stores in your neighborhood';
      case 'Featured Outlets':
        return 'Handpicked premium stores for you';
      case 'Trending':
        return 'Most ordered and popular right now';
      default:
        return 'Handpicked stores for you';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MarketProvider>();
    final allVendors = provider.vendors;
    final filtered = _getFilteredVendors(allVendors);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _getSubtitle(),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: provider.loading && allVendors.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => provider.refreshVendors(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      return EntranceSlide(
                        delay: Duration(milliseconds: 45 * i),
                        child: MarketOutletCard(vendor: filtered[i]),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No outlets found for $groupName',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Please try again later',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
