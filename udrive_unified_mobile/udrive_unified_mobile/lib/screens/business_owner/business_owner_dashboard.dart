import 'package:flutter/material.dart';

import '../../core/businesses/business_repository.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/business_models.dart';
import 'business_owner_add_screen.dart';

/// Lists everything this owner has submitted, with its approval state.
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
    // No Scaffold here: MainShell already provides the app bar and background,
    // so wrapping again would render two stacked app bars.
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
                children: [
                  if (_items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add another business'),
                      ),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppTint.danger,
                        borderRadius: AppRadii.all(AppRadii.card),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 34, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppRadii.all(AppRadii.card),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.add_business_outlined,
                              size: 32, color: AppText.disabled),
                          const SizedBox(height: 12),
                          const Text(
                            'You have not listed a business yet',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppText.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'List your shop, restaurant or clinic so travellers '
                            'nearby can find you.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: AppText.secondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => _openForm(),
                              child: const Text('List your business'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _OwnerListingTile(
                          listing: item,
                          onEdit: () => _openForm(item),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _OwnerListingTile extends StatelessWidget {
  const _OwnerListingTile({required this.listing, required this.onEdit});

  final BusinessListing listing;
  final VoidCallback onEdit;

  (Color background, Color text) get _statusColors => switch (listing.status) {
        BusinessStatus.approved => (AppTint.success, AppTint.successText),
        BusinessStatus.rejected => (AppTint.danger, AppColors.danger),
        BusinessStatus.suspended => (AppTint.danger, AppColors.danger),
        _ => (AppTint.warning, AppTint.warningText),
      };

  @override
  Widget build(BuildContext context) {
    final (background, text) = _statusColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  listing.category?.label ?? 'Business',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppText.secondary),
                ),
                const SizedBox(height: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    listing.status.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 19),
            tooltip: 'Edit listing',
          ),
        ],
      ),
    );
  }
}
