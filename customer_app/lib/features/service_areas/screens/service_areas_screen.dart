import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/service_areas_providers.dart';

export '../providers/service_areas_providers.dart'
    show ServiceAreaModel, serviceAreasProvider;

// ── Screen ────────────────────────────────────────────────────────────────────

class ServiceAreasScreen extends ConsumerWidget {
  const ServiceAreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(serviceAreasProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    final isTablet = width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Hero banner ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _ServiceAreasBanner(isDesktop: isDesktop),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32 : 16,
                    vertical: 32,
                  ),
                  child: areasAsync.when(
                    loading: () => _LoadingGrid(isTablet: isTablet),
                    error: (e, _) => _ErrorView(
                      onRetry: () => ref.invalidate(serviceAreasProvider),
                    ),
                    data: (areas) => areas.isEmpty
                        ? const _EmptyView()
                        : _AreasContent(
                            areas: areas,
                            isDesktop: isDesktop,
                            isTablet: isTablet,
                          ),
                  ),
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 64)),
        ],
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _ServiceAreasBanner extends StatelessWidget {
  final bool isDesktop;
  const _ServiceAreasBanner({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.textPrimary,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 48 : 24,
        vertical: isDesktop ? 56 : 40,
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gold accent bar
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Service Areas',
                style: TextStyle(
                  fontSize: isDesktop ? 42 : 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                  letterSpacing: isDesktop ? -1.0 : -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'DODO Booker is available in these cities and areas.\nWe\'re growing — more locations coming soon.',
                style: TextStyle(
                  fontSize: isDesktop ? 15 : 13.5,
                  color: Colors.white.withAlpha(178),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Content — grouped by city ─────────────────────────────────────────────────

class _AreasContent extends StatelessWidget {
  final List<ServiceAreaModel> areas;
  final bool isDesktop;
  final bool isTablet;

  const _AreasContent({
    required this.areas,
    required this.isDesktop,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    // Group by city
    final Map<String, List<ServiceAreaModel>> byCityOrdered = {};
    for (final a in areas) {
      byCityOrdered.putIfAbsent(a.city, () => []).add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // City count summary
        _SummaryBar(
          cityCount: byCityOrdered.length,
          areaCount: areas.length,
        ),
        const SizedBox(height: 28),

        // Per-city sections
        for (final entry in byCityOrdered.entries) ...[
          _CitySection(
            city: entry.key,
            areas: entry.value,
            isDesktop: isDesktop,
            isTablet: isTablet,
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int cityCount;
  final int areaCount;

  const _SummaryBar({required this.cityCount, required this.areaCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.goldLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Currently serving ',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: '$areaCount area${areaCount != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' across ',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: '$cityCount cit${cityCount != 1 ? 'ies' : 'y'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── City section ──────────────────────────────────────────────────────────────

class _CitySection extends StatelessWidget {
  final String city;
  final List<ServiceAreaModel> areas;
  final bool isDesktop;
  final bool isTablet;

  const _CitySection({
    required this.city,
    required this.areas,
    required this.isDesktop,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final crossCount = isDesktop ? 3 : isTablet ? 2 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // City header
        Row(
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              city,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${areas.length} area${areas.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Area grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isDesktop ? 3.2 : isTablet ? 2.8 : 3.8,
          ),
          itemCount: areas.length,
          itemBuilder: (_, i) => _AreaCard(area: areas[i]),
        ),
      ],
    );
  }
}

// ── Area card ─────────────────────────────────────────────────────────────────

class _AreaCard extends StatefulWidget {
  final ServiceAreaModel area;
  const _AreaCard({required this.area});

  @override
  State<_AreaCard> createState() => _AreaCardState();
}

class _AreaCardState extends State<_AreaCard> {
  bool _hovered = false;

  String get _radius {
    final km = widget.area.radiusKm;
    if (km < 1) return '${(km * 1000).round()} m radius';
    return '${km % 1 == 0 ? km.toInt() : km} km radius';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.goldLight : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? AppColors.gold.withAlpha(120)
                : AppColors.border,
            width: _hovered ? 1.5 : 0.8,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.gold.withAlpha(18),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _hovered
                    ? AppColors.gold.withAlpha(30)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.place_rounded,
                size: 17,
                color: _hovered ? AppColors.gold : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.area.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _radius,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingGrid extends StatelessWidget {
  final bool isTablet;
  const _LoadingGrid({required this.isTablet});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary bar skeleton
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 28),
        // Cards skeleton
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isTablet ? 2 : 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isTablet ? 2.8 : 3.8,
          ),
          itemCount: 6,
          itemBuilder: (_, $i) => Container(
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text(
              'Could not load service areas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty ─────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_searching_rounded,
                  size: 30, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            const Text(
              'Service areas coming soon',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'We\'re expanding our coverage. Stay tuned!',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
