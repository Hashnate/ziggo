import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Events',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.help_outline_rounded, size: 20),
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.confirmation_number_outlined, size: 20),
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
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
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Black Header + Search Bar
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EventSearchScreen(allEvents: _events ?? [])),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.grey, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Not sure what to do? 🤔 Let your curiosity guide you. 🧭',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Featured Carousel (mocking with first event or a static banner if empty)
          Container(
            color: Colors.black,
            height: 220,
            width: double.infinity,
            child: events.isNotEmpty
                ? _FeaturedEventHero(event: events.first)
                : Container(
                    color: Colors.grey[900],
                    child: const Center(child: Text('No featured event', style: TextStyle(color: Colors.white54))),
                  ),
          ),

          // Categories
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CategoryTile(title: 'Sports', icon: Icons.sports_soccer_rounded, isSelected: false, onTap: () => _openCategory('Sports', Icons.sports_soccer_rounded)),
                    _CategoryTile(title: 'Bank Offers', icon: Icons.credit_card_rounded, isSelected: false, onTap: () => _openCategory('Bank Offers', Icons.credit_card_rounded)),
                    _CategoryTile(title: 'Experience', icon: Icons.local_activity_rounded, isSelected: false, onTap: () => _openCategory('Experience', Icons.local_activity_rounded)),
                    _CategoryTile(title: 'Charity', icon: Icons.favorite_rounded, isSelected: false, onTap: () => _openCategory('Charity', Icons.favorite_rounded)),
                  ],
                ),
              ],
            ),
          ),

          // Promo Banner
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: AppStyles.shadowSm,
              ),
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
                          child: const Text('GOT AN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.red,
                          child: const Text('EVENT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.white,
                          child: const Text('COMING UP?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
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
                        const Text('REACH MORE FANS &\nFILL MORE SEATS, WITH', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('Ziggo Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text('Reach us: events@ziggo.lk', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF57F17),
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                      ),
                      child: const Text(
                        'MUSIC | NIGHTLIFE | SPORTS | EXHIBITIONS & MORE',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),

          // All Events Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
            child: const Text('All Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
          ),

          // Events List
          if (events.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No events available')))
          else
            Container(
              color: Colors.white,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: events.length,
                itemBuilder: (_, i) => _EventCard(event: events[i]),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null && image.isNotEmpty)
          Image.network(image, fit: BoxFit.cover)
        else
          Container(color: Colors.grey[800]),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black.withOpacity(0.8), Colors.transparent, Colors.black.withOpacity(0.9)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('EXCLUSIVE TICKETING PARTNER', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              const Text('Ziggo Events', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
        )
      ],
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        height: 90,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD54F).withOpacity(0.2) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD54F) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: isSelected ? Colors.black : Colors.black87),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isSelected ? Colors.black : Colors.black87)),
          ],
        ),
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
    final city = event['city']?.toString();
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1, // PickMe's event card is highly square
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image != null && image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imageFallback(),
                        )
                      : _imageFallback(),
                  // "Hottest Pick" border frame mock
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFF57F17), width: 6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateLabel.isEmpty ? 'Date TBD' : dateLabel.split('·').first.trim(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (venue != null && venue.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                venue,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              from != null ? 'LKR ${from.toStringAsFixed(0)} upwards' : 'Price TBD',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'View More',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
  final Map<int, int> _selectedQuantities = {};

  double _calculateTotal(List<Map<String, dynamic>> tiers) {
    double total = 0;
    _selectedQuantities.forEach((index, qty) {
      if (index < tiers.length) {
        final price = double.tryParse(tiers[index]['price']?.toString() ?? '') ?? 0.0;
        total += price * qty;
      }
    });
    return total;
  }
  
  int get _totalItems => _selectedQuantities.values.fold(0, (a, b) => a + b);

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

  Future<void> _contactOrganizer() async {
    final phone = _event?['organizer_phone']?.toString();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No organizer phone on file'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
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
    debugPrint('EventDetailScreen: event data is $ev');
    final name = ev['name']?.toString() ?? '';
    final description = ev['description']?.toString();
    final venue = ev['venue']?.toString();
    final city = ev['city']?.toString();
    final image = ev['image_url']?.toString();
    final organizer = ev['organizer_name']?.toString();
    final startsAtRaw = ev['starts_at']?.toString();
    final endsAtRaw = ev['ends_at']?.toString();
    final startsAt = startsAtRaw == null ? null : DateTime.tryParse(startsAtRaw)?.toLocal();
    final endsAt = endsAtRaw == null ? null : DateTime.tryParse(endsAtRaw)?.toLocal();
    final List<Map<String, dynamic>> tiers = [];
    try {
      if (ev['tiers'] != null) {
        for (final t in ev['tiers'] as List) {
          tiers.add(Map<String, dynamic>.from(t as Map));
        }
      }
    } catch (e, stack) {
      debugPrint('EventDetailScreen: Error parsing tiers: $e\n$stack');
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  image != null && image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imageFallback(),
                        )
                      : _imageFallback(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.6), Colors.transparent, Colors.black.withOpacity(0.8)],
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (startsAt != null) _iconRow(Icons.calendar_today_rounded, DateFormat('E, d MMM y · h:mm a').format(startsAt)),
                  if (endsAt != null) ...[
                    const SizedBox(height: 8),
                    _iconRow(Icons.schedule_rounded, 'Ends ${DateFormat('h:mm a').format(endsAt)}'),
                  ],
                  if (venue != null) ...[
                    const SizedBox(height: 8),
                    _iconRow(Icons.place_rounded, '$venue${city != null ? " · $city" : ""}'),
                  ],
                  if (organizer != null) ...[
                    const SizedBox(height: 8),
                    _iconRow(Icons.person_outline_rounded, 'Organized by $organizer'),
                  ],
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('ABOUT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text('TICKETS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5)),
                  const SizedBox(height: 16),
                  for (int i = 0; i < tiers.length; i++)
                    _InteractiveTierRow(
                      tier: tiers[i],
                      quantity: _selectedQuantities[i] ?? 0,
                      onAdd: () {
                        setState(() {
                          _selectedQuantities[i] = (_selectedQuantities[i] ?? 0) + 1;
                        });
                      },
                      onRemove: () {
                        if ((_selectedQuantities[i] ?? 0) > 0) {
                          setState(() {
                            _selectedQuantities[i] = (_selectedQuantities[i] ?? 0) - 1;
                          });
                        }
                      },
                    ),
                  if (tiers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('No tickets configured yet.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 100), // padding for bottom bar
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _totalItems > 0
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_totalItems Ticket${_totalItems > 1 ? 's' : ''}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('LKR ${_calculateTotal(tiers).toStringAsFixed(0)}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final selectedTiers = <Map<String, dynamic>>[];
                      _selectedQuantities.forEach((index, qty) {
                        if (qty > 0 && index < tiers.length) {
                          selectedTiers.add({
                            ...tiers[index],
                            'quantity': qty,
                          });
                        }
                      });
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventCheckoutScreen(
                            event: ev,
                            selectedTiers: selectedTiers,
                            totalPrice: _calculateTotal(tiers),
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    ),
                    child: const Text('PROCEED TO CHECKOUT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  void _showComingSoon() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.confirmation_number_rounded,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tickets launching soon',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'For now, contact the organizer directly to reserve your ticket.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('CONTACT ORGANIZER'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _contactOrganizer();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
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

class _InteractiveTierRow extends StatelessWidget {
  final Map<String, dynamic> tier;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  
  const _InteractiveTierRow({required this.tier, required this.quantity, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final name = tier['name']?.toString() ?? '';
    final price = double.tryParse(tier['price']?.toString() ?? '') ?? 0.0;
    final desc = tier['description']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black)),
                Text('LKR ${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.grey)),
                if (desc != null && desc.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(desc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  color: quantity > 0 ? Colors.black : Colors.grey,
                  onPressed: onRemove,
                ),
                Text('$quantity', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  color: Colors.black,
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EventCheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  final List<Map<String, dynamic>> selectedTiers;
  final double totalPrice;

  const EventCheckoutScreen({super.key, required this.event, required this.selectedTiers, required this.totalPrice});

  @override
  State<EventCheckoutScreen> createState() => _EventCheckoutScreenState();
}

class _EventCheckoutScreenState extends State<EventCheckoutScreen> {
  bool _isProcessing = false;

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);
    // Mock network delay for payment
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => TicketSuccessScreen(event: widget.event, selectedTiers: widget.selectedTiers)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Checkout', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: Colors.black),
                  SizedBox(height: 16),
                  Text('Processing Payment...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Order Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: widget.selectedTiers.map((t) {
                      final name = t['name'] ?? 'Ticket';
                      final qty = t['quantity'] as int;
                      final price = double.tryParse(t['price']?.toString() ?? '') ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${qty}x $name', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text('LKR ${(price * qty).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Platform Fee', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                    Text('LKR 0', style: TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(color: Color(0xFFE2E8F0)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    Text('LKR ${widget.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.black)),
                  ],
                ),
                const SizedBox(height: 40),
                const Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFD54F), width: 2),
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFFFD54F).withOpacity(0.1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Colors.orange),
                      const SizedBox(width: 16),
                      const Expanded(child: Text('Ziggo Wallet', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      const Icon(Icons.check_circle_rounded, color: Colors.orange),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _isProcessing ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: _processPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text('PAY NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
          ),
        ),
      ),
    );
  }
}

class TicketSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> event;
  final List<Map<String, dynamic>> selectedTiers;

  const TicketSuccessScreen({super.key, required this.event, required this.selectedTiers});

  @override
  Widget build(BuildContext context) {
    final name = event['name'] ?? 'Event';
    final startsAtRaw = event['starts_at']?.toString();
    final startsAt = startsAtRaw == null ? null : DateTime.tryParse(startsAtRaw)?.toLocal();
    final qrData = 'ziggo_ticket_${DateTime.now().millisecondsSinceEpoch}';

    return Scaffold(
      backgroundColor: const Color(0xFFFFD54F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.black),
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
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
                decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              const Text('Payment Successful!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black)),
              const SizedBox(height: 8),
              const Text('Here is your digital ticket. Have fun!', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  children: [
                    Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    if (startsAt != null)
                      Text(DateFormat('EEEE, d MMMM y · h:mm a').format(startsAt), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 2, height: 2),
                    ),
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                    const SizedBox(height: 24),
                    const Text('SCAN AT ENTRANCE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.grey)),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: selectedTiers.map((t) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${t['quantity']}x ${t['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('BACK TO HOME', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(categoryName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
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
                          const Text("No events found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
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
