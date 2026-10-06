import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/ud_kit.dart';
import 'driver_wallet_screen.dart';

/// "Top-up kaise karein" — the three steps from a low wallet back to rides.
///
/// Opened from the red low-wallet banner and the popup on the driver home.
/// The account number comes from settings, the same place the wallet screen
/// reads it, and can be copied from here. The last button opens the wallet
/// screen itself, where the top-up is entered.
class WalletTopupGuideScreen extends StatefulWidget {
  const WalletTopupGuideScreen({this.balance, super.key});

  /// The balance that brought the driver here, when known.
  final double? balance;

  @override
  State<WalletTopupGuideScreen> createState() => _WalletTopupGuideScreenState();
}

class _WalletTopupGuideScreenState extends State<WalletTopupGuideScreen> {
  String? _number;
  String? _name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccount());
  }

  Future<void> _loadAccount() async {
    try {
      final response = await AppControllerScope.of(context)
          .apiClient
          .getJson('/api/v1/driver/wallet/topup-account');
      final data = response['data'];
      if (!mounted || data is! Map) return;
      setState(() {
        _number = '${data['easypaisaNumber'] ?? ''}'.trim();
        _name = '${data['accountName'] ?? ''}'.trim();
      });
    } catch (_) {
      // The steps still read correctly without the number; the wallet screen
      // shows it too.
    }
  }

  void _copy() {
    final number = _number;
    if (number == null || number.isEmpty) return;
    Clipboard.setData(ClipboardData(text: number));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Number copy ho gaya.')));
  }

  Future<void> _openWallet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.surface,
          appBar: UdTopBar(
            title: 'Wallet',
            onBack: () => Navigator.maybePop(routeContext),
          ),
          body: const DriverWalletScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final number = _number;
    final balance = widget.balance;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: UdTopBar(
        title: 'Top-up kaise karein',
        onBack: () => Navigator.maybePop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.sidePadding, 8, AppSizes.sidePadding, 32),
        children: [
          if (balance != null) ...[
            UdBanner(
              tone: UdTone.err,
              icon: Icons.account_balance_wallet_rounded,
              text: 'Aap ka wallet abhi PKR ${balance.round()} hai.',
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Har ride shuru hone par UDrive ki commission wallet se katti hai. '
            'Wallet khatam ho to nayi rides aana band ho jati hain — yeh teen '
            'kaam karein:',
            style: AppType.body2.copyWith(height: 1.5, color: AppText.secondary),
          ),
          const SizedBox(height: 18),
          _Step(
            number: 1,
            title: 'UDrive account mein paise bhejein',
            text: 'EasyPaisa se neeche wale number par jitni raqam chahein '
                'bhejein. Receipt ka transaction ID aur screenshot sambhal kar '
                'rakhein.',
            child: number == null || number.isEmpty
                ? null
                : UdCard(
                    tone: UdCardTone.lime,
                    onTap: _copy,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                number,
                                style: AppType.h2.copyWith(
                                  letterSpacing: 0.5,
                                  color: AppText.onBrand,
                                ),
                              ),
                              if ((_name ?? '').isNotEmpty)
                                Text(
                                  _name!,
                                  style: AppType.small
                                      .copyWith(color: AppText.onBrand),
                                ),
                            ],
                          ),
                        ),
                        UdIconButton(
                          icon: Icons.copy_rounded,
                          tooltip: 'Copy number',
                          iconColor: AppText.onBrand,
                          onPressed: _copy,
                        ),
                      ],
                    ),
                  ),
          ),
          const _Step(
            number: 2,
            title: 'Wallet → Top up',
            text: 'App mein Wallet kholein. Raqam, EasyPaisa transaction ID '
                'aur receipt ka screenshot daal kar bhej dein.',
          ),
          const _Step(
            number: 3,
            title: 'UDrive approve karega',
            text: 'Office paise milne ki tasdeeq karta hai, phir raqam aap ke '
                'wallet mein aa jati hai aur rides dobara milne lagti hain.',
            last: true,
          ),
          const SizedBox(height: 8),
          UdButton.primary(
            label: 'Wallet kholein',
            icon: Icons.account_balance_wallet_rounded,
            onPressed: _openWallet,
          ),
        ],
      ),
    );
  }
}

/// One numbered step, with an optional block under it.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.text,
    this.child,
    this.last = false,
  });

  final int number;
  final String title;
  final String text;
  final Widget? child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 18 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.navy,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppType.listTitle.copyWith(color: AppText.onInk),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: AppType.listTitle.copyWith(color: AppText.primary)),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: AppType.small
                      .copyWith(height: 1.5, color: AppText.secondary),
                ),
                if (child != null) ...[
                  const SizedBox(height: 12),
                  child!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
