import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import 'event_booking_screens.dart';
import 'my_tickets_screen.dart';

/// Events / ticketing — browse concerts, shows, festivals. Purchase pipeline
/// is not wired yet; tapping Buy on a tier surfaces a "contact organizer" CTA.
class EventHomeScreen extends StatefulWidget {
  const EventHomeScreen({super.key});

  @override
  State<EventHomeScreen> createState() => _EventHomeScreenState();
}

class _EventHomeScreenState extends State<EventHomeScreen> {
  List<Map<String, dynamic>>? _events;
  String? _error;
  bool _loading = true;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiClient.instance.dio.get('/events');
      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(resp.data as List);
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['detail']?.toString() ??
              e.message ??
              'Could not load events';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? _skeleton()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                )
              : _content(),
    );
  }

  Widget _skeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF8FAFC),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppStyles.radiusLg),
            ),
          ),
        ),
      ),
    );
  }

  void _openCategory(String cat, IconData icon) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventCategoryScreen(
          categoryName: cat,
          icon: icon,
          allEvents: _events ?? [],
        ),
      ),
    );
  }

  Widget _content() {
    final allEvents = _events ?? const [];
    final events = allEvents.where((e) {
      final cat = e['category']?.toString().toLowerCase() ?? '';
      final name = e['name']?.toString().toLowerCase() ?? '';
      
      bool matchesCategory = true;
      if (_selectedCategory != null) {
        final searchCat = _selectedCategory!.toLowerCase();
        matchesCategory = cat.contains(searchCat) || name.contains(searchCat);
      }
      
      return matchesCategory;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.primary,
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
              ),
            ),
            title: const Text(
              'Discover Events',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.confirmation_number_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyTicketsScreen()),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EventSearchScreen(allEvents: _events ?? [])),
                        );
                      },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Not sure what to do? 🤔 Let your curiosity guide you.',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

      SliverToBoxAdapter(
            child: Column(
              children: [
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: PageView(
                      controller: PageController(viewportFraction: 0.93),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _FeaturedEventHero(event: events.first),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: _PromoBanner(),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: PageView(
                      controller: PageController(viewportFraction: 0.93),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: _PromoBanner(),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Categories
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CategoryTile(title: 'Sports', icon: Icons.sports_soccer_rounded, isSelected: false, onTap: () => _openCategory('Sports', Icons.sports_soccer_rounded)),
                          _CategoryTile(title: 'Offers', icon: Icons.credit_card_rounded, isSelected: false, onTap: () => _openCategory('Bank Offers', Icons.credit_card_rounded)),
                          _CategoryTile(title: 'Experience', icon: Icons.local_activity_rounded, isSelected: false, onTap: () => _openCategory('Experience', Icons.local_activity_rounded)),
                          _CategoryTile(title: 'Charity', icon: Icons.favorite_rounded, isSelected: false, onTap: () => _openCategory('Charity', Icons.favorite_rounded)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('All Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          if (events.isEmpty)
            const SliverToBoxAdapter(
              child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No events available'))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _EventCard(event: events[i]),
                  childCount: events.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeaturedEventHero extends StatelessWidget {
  final Map<String, dynamic> event;
  const _FeaturedEventHero({required this.event});

  @override
  Widget build(BuildContext context) {
    final image = event['image_url']?.toString();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null && image.isNotEmpty)
            Image.network(image, fit: BoxFit.cover)
          else
            Container(color: Colors.grey[800]),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.4), Colors.transparent, Colors.black.withOpacity(0.9)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('FEATURED EVENT', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(event['name']?.toString() ?? 'Special Event', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  
  const _CategoryTile({required this.title, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppColors.primary : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: isSelected ? AppColors.primary.withOpacity(0.4) : Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(
              icon,
              size: 26,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final name = event['name']?.toString() ?? 'Untitled';
    final venue = event['venue']?.toString();
    final image = event['image_url']?.toString();
    final startsAtRaw = event['starts_at']?.toString() ?? '';
    final startsAt = DateTime.tryParse(startsAtRaw)?.toLocal();
    final from = (event['from_price'] as num?)?.toDouble();
    final dateLabel = startsAt == null
        ? ''
        : DateFormat('E, d MMM · h:mm a').format(startsAt);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: event['id'] as int),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image != null && image.isNotEmpty
                ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imageFallback())
                : _imageFallback(),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.toUpperCase(),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dateLabel.isEmpty ? 'Date TBD' : dateLabel.split('·').first.trim(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                              if (venue != null && venue.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  venue,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              from != null ? 'LKR ${from.toStringAsFixed(0)}' : 'TBD',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                            ),
                            const Text('upwards', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: AppColors.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: const Icon(Icons.music_note_rounded,
          color: AppColors.primary, size: 48),
    );
  }
}

class EventDetailScreen extends StatefulWidget {
  final int eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  Map<String, dynamic>? _event;
  String? _error;
  bool _loading = true;
  bool _aboutExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiClient.instance.dio.get('/events/${widget.eventId}');
      if (mounted) {
        setState(() {
          _event = Map<String, dynamic>.from(resp.data as Map);
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['detail']?.toString() ??
              e.message ??
              'Could not load event';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openMaps() async {
    final venue = _event?['venue']?.toString() ?? '';
    final city = _event?['city']?.toString() ?? '';
    final query = Uri.encodeComponent([venue, city].where((s) => s.isNotEmpty).join(', '));
    if (query.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _event == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF8FAFC), elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? 'Event unavailable',
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      );
    }

    final ev = _event!;
    final name = ev['name']?.toString() ?? '';
    final description = ev['description']?.toString();
    final venue = ev['venue']?.toString();
    final city = ev['city']?.toString();
    final image = ev['image_url']?.toString();
    final startsAtRaw = ev['starts_at']?.toString();
    final startsAt = startsAtRaw == null ? null : DateTime.tryParse(startsAtRaw)?.toLocal();
    final fromPrice = (ev['from_price'] as num?)?.toDouble();
    final hasTiers = ev['tiers'] is List && (ev['tiers'] as List).isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  image != null && image.isNotEmpty
                      ? Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imageFallback())
                      : _imageFallback(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.4), Colors.transparent, AppColors.background],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5),
                        ),
                        if (fromPrice != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'LKR ${fromPrice.toStringAsFixed(0)} upwards',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: const [
                            _OfferChip(label: 'NTB Offer'),
                            SizedBox(width: 12),
                            _OfferChip(label: 'Save Up to 5000'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (startsAt != null)
                          _iconRow(Icons.calendar_month_rounded, '${DateFormat('d MMM').format(startsAt)}   |   ${DateFormat('h:mm a').format(startsAt)} onwards'),
                        if (startsAt != null && venue != null)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                        if (venue != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.place_rounded, size: 20, color: AppColors.primary),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$venue${city != null ? " · $city" : ""}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: _openMaps,
                                      child: const Text('Open Venue in Maps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary, decoration: TextDecoration.underline)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  if (ev['additional_fields'] is List && (ev['additional_fields'] as List).isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Event Info',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 12),
                          for (var item in ev['additional_fields'] as List) ...[
                            if (item is Map && item['label'] != null && item['value'] != null) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${item['label']}: ",
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                                    ),
                                    Expanded(
                                      child: Text(
                                        "${item['value']}",
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (item != (ev['additional_fields'] as List).last)
                                const Divider(height: 12, thickness: 0.5),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                  
                  if (description != null && description.isNotEmpty) ...[
                    const Text('About Event', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final span = TextSpan(
                          text: description,
                          style: TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                        );
                        final tp = TextPainter(
                          text: span,
                          maxLines: 4,
                          textDirection: TextDirection.ltr,
                        );
                        tp.layout(maxWidth: constraints.maxWidth);
                        final isExceeded = tp.didExceedMaxLines;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              alignment: Alignment.topCenter,
                              child: Text(
                                description,
                                maxLines: _aboutExpanded ? null : 4,
                                overflow: _aboutExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                              ),
                            ),
                            if (isExceeded)
                              GestureDetector(
                                onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                                  child: Text(
                                    _aboutExpanded ? 'Read less' : 'Read more',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: hasTiers
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white.withOpacity(0.5)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventCartScreen(event: ev))),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                        ),
                        child: const Text('Buy Now', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _iconRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() {
    return Container(
      color: AppColors.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: const Icon(Icons.music_note_rounded,
          color: AppColors.primary, size: 48),
    );
  }
}


class EventSearchScreen extends StatefulWidget {
  final List<Map<String, dynamic>> allEvents;

  const EventSearchScreen({super.key, required this.allEvents});

  @override
  State<EventSearchScreen> createState() => _EventSearchScreenState();
}

class _EventSearchScreenState extends State<EventSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _filter();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _results = widget.allEvents.where((e) {
        final name = e['name']?.toString().toLowerCase() ?? '';
        final venue = e['venue']?.toString().toLowerCase() ?? '';
        final desc = e['description']?.toString().toLowerCase() ?? '';
        return name.contains(query) || venue.contains(query) || desc.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Container(
          height: 44,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.search_rounded, color: Colors.grey, size: 20),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search for events',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                  },
                ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: _searchController.text.isEmpty
          ? _buildEmptyState()
          : _results.isEmpty
              ? _buildNoResults()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    return _EventCard(event: _results[index]);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(Icons.manage_search_rounded, size: 80, color: Colors.blueGrey.shade700),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              "Let's find your next favorite event!",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "From live shows to local hangouts, discover events that match your vibe — all in one place.",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            const Text(
              "No events found",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              "We couldn't find any events matching \"${_searchController.text}\"",
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class EventCategoryScreen extends StatelessWidget {
  final String categoryName;
  final IconData icon;
  final List<Map<String, dynamic>> allEvents;

  const EventCategoryScreen({
    super.key,
    required this.categoryName,
    required this.icon,
    required this.allEvents,
  });

  @override
  Widget build(BuildContext context) {
    final searchCat = categoryName.toLowerCase();
    final events = allEvents.where((e) {
      final cat = e['category']?.toString().toLowerCase() ?? '';
      final name = e['name']?.toString().toLowerCase() ?? '';
      return cat.contains(searchCat) || name.contains(searchCat);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(categoryName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 32),
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Icon(icon, size: 80, color: Colors.blueGrey.shade700),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 2, endIndent: 16)),
              Text('All $categoryName Events', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 2, indent: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text("No events found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          Text("There are no upcoming events in the $categoryName category right now.", textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      return _EventCard(event: events[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Decorative bank/promo offer pill shown on the event detail page
/// (dashed outline, matching the Ziggo "NTB Offer" / "Save Up to" chips).
class _OfferChip extends StatelessWidget {
  final String label;
  const _OfferChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.black.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sell_rounded, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.8), AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppStyles.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.white,
                  child: const Text('GOT AN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textPrimary)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: AppColors.textPrimary,
                  child: const Text('EVENT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.white,
                  child: const Text('COMING UP?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('REACH MORE FANS &\nFILL MORE SEATS, WITH', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Ziggo Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('events@ziggo.lk', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
              ),
              child: const Text(
                'MUSIC | NIGHTLIFE | SPORTS | EXHIBITIONS & MORE',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
          )
        ],
      ),
    );
  }
}
