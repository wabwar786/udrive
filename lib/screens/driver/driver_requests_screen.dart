import 'package:flutter/material.dart';

import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../data/driver_dummy_data.dart';
import '../../models/driver_models.dart';

class DriverRequestsScreen extends StatefulWidget {
  const DriverRequestsScreen({super.key});

  @override
  State<DriverRequestsScreen> createState() => _DriverRequestsScreenState();
}

class _DriverRequestsScreenState extends State<DriverRequestsScreen> {
  final Set<int> _acceptedOffers = <int>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            S.of(context, 'requests'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Review customer prices, accept a request or send your own offer.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          ...rideRequests.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RequestCard(
                    request: entry.value,
                    accepted: _acceptedOffers.contains(entry.key),
                    onAccept: () {
                      setState(() => _acceptedOffers.add(entry.key));
                      _message('Ride accepted. Customer has been notified.');
                    },
                    onCounter: () => _counterOffer(entry.value),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _counterOffer(RideRequest request) async {
    final controller = TextEditingController(text: '${request.offer + 500}');
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context, 'counterOffer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.route, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Your price',
                prefixText: 'PKR ',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Optional message',
                hintText: 'I can arrive in 8 minutes.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send offer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (sent == true) {
      _message('Counteroffer sent to the customer.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.accepted,
    required this.onAccept,
    required this.onCounter,
  });

  final RideRequest request;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onCounter;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(request.type)),
                const Spacer(),
                Text(request.time, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              request.route,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${request.distance} · ${request.passengers} passengers · ${request.customer}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Customer offer  PKR ${request.offer}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (accepted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F7F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.primary),
                    SizedBox(width: 9),
                    Text(
                      'Accepted · waiting for customer confirmation',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCounter,
                      child: Text(S.of(context, 'counter')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      child: Text(S.of(context, 'accept')),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
