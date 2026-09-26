import 'package:flutter/material.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import '../../models/business_models.dart';
import 'business_owner_add_screen.dart';

/// H-04 — everything this owner has submitted, with its approval state.
///
/// No `Scaffold` here: `main_shell` already provides the bar and background,
/// so wrapping again would render two stacked bars.
class BusinessOwnerDashboard extends StatefulWidget {
  const BusinessOwnerDashboard({super.key});

  @override
  State<BusinessOwnerDashboard> createState() => _BusinessOwnerDashboardState();
}

class _BusinessOwnerDashboardState extends State<BusinessOwnerDashboard> {
  BusinessRepository? _repository;
  bool _loading = true;
  String? _error;
  List<BusinessListing> _items = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) return;
    _repository = BusinessRepository(AppControllerScope.of(context).apiClient);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final items = await repository.myBusinesses();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([BusinessListing? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessOwnerAddScreen(existing: existing),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.navy),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 6, AppSizes.sidePadding, 40),
        children: [
          Text(
            'My business',
            style: AppType.h1.copyWith(color: AppText.primary),
          ),
          const SizedBox(height: 18),

          if (_items.isNotEmpty) ...[
            UdButton.outline(
              label: 'Add another business',
              icon: Icons.add_rounded,
              onPressed: () => _openForm(),
            ),
            const SizedBox(height: 16),
          ],

          if (_error != null) ...[
            // Says what to do about it. It used to be the error string on a
            // red block and nothing else, which tells somebody standing in
            // their own shop exactly nothing.
            UdBanner(
              tone: UdTone.err,
              icon: Icons.cloud_off_rounded,
              text: 'Unable to load some listings: $_error Pull down to '
                  'retry.',
            ),
            const SizedBox(height: 16),
          ],

          if (_items.isEmpty)
            UdEmptyState(
              icon: Icons.add_business_outlined,
              title: 'You have not listed a business yet',
              text: 'List your shop, restaurant or clinic so travellers '
                  'nearby can find you.',
              action: UdButton.primary(
                label: 'List your business',
                icon: Icons.add_rounded,
                expand: false,
                onPressed: () => _openForm(),
              ),
            )
          else
            ..._items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OwnerListingTile(
                  listing: item,
                  onEdit: () => _openForm(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One listing, and the one thing to do with it.
class _OwnerListingTile extends StatelessWidget {
  const _OwnerListingTile({required this.listing, required this.onEdit});

  final BusinessListing listing;
  final VoidCallback onEdit;

  UdTone get _tone => switch (listing.status) {
        BusinessStatus.approved => UdTone.ok,
        BusinessStatus.rejected => UdTone.err,
        BusinessStatus.suspended => UdTone.err,
        _ => UdTone.warn,
      };

  @override
  Widget build(BuildContext context) {
    return UdCard(
      onTap: onEdit,
      child: Row(
        children: [
          UdIconTile(
            icon: listing.category?.icon ?? Icons.storefront_rounded,
            tone: listing.status == BusinessStatus.approved
                ? UdIconTone.soft
                : UdIconTone.neutral,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.h3.copyWith(color: AppText.primary),
                ),
                const SizedBox(height: 3),
                Text(
                  listing.category?.label ?? 'Business',
                  style: AppType.small.copyWith(color: AppText.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          UdBadge(label: listing.status.label, tone: _tone),
          const SizedBox(width: 6),
          // The pencil was a bare icon button with a tooltip nobody on a
          // phone will ever see. The whole card opens the form now, and this
          // is the affordance that says so.
          const Icon(Icons.chevron_right_rounded,
              size: 22, color: AppText.caption),
        ],
      ),
    );
  }
}
