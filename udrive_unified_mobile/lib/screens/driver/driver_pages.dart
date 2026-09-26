import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models.dart';

// Three screens were here and all three were mock-ups that the real screens
// had already replaced:
//
//   DriverRequestsScreen   — read `controller.requests`, the dummy list.
//   DriverPackagesScreen   — dummy packages under a hardcoded "Views 248 ·
//                            Offers 12 · Bookings 5" for every package.
//   DriverEarningsScreen   — "PKR 42,850" over "17 trips" and "4.9" for every
//                            driver, three invented journeys, and a chart
//                            hand-painted from a fixed curve. It was also the
//                            last AppColors.inkDeep in the app.
//
// Each one shared a public class name with the real screen in its own file,
// which is an ambiguous import — main_shell was carrying
// `hide DriverEarningsScreen` to keep the build alive. That is gone with them.
//
// ActiveDriverTripScreen was here too. Hardcoded "18 min · 12.4 km", a Message
// button that opened nothing, an "I have arrived" button that notified
// nobody, and an emergency button whose entire behaviour was a snackbar
// reading "Driver safety alert demo activated". The real one is
// LiveTripNavigationScreen, reached from the driver dashboard.
//
// The older CreatePackageScreen was here, superseded by
// live_create_package_screen.dart.
//
// The mock DriverWalletScreen and DriverDocumentsScreen that used to sit here
// have been removed. The real screens live in driver_wallet_screen.dart and
// driver_documents_screen.dart.
//
// DriverReviewsScreen was here. It showed every driver the same invented
// "4.9" over "846 trips" and three fabricated passenger reviews. The real
// figures live on DriverEarningsScreen.

class DriverAvailabilityScreen extends StatefulWidget {
  const DriverAvailabilityScreen({super.key});

  @override
  State<DriverAvailabilityScreen> createState() => _DriverAvailabilityScreenState();
}

class _DriverAvailabilityScreenState extends State<DriverAvailabilityScreen> {
  final Set<int> selected = {1, 2, 3, 4, 5};
  bool nights = false;
  bool multi = true;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (i) {
                    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                    return FilterChip(
                      label: Text(names[i]),
                      selected: selected.contains(i + 1),
                      onSelected: (value) => setState(() {
                        if (value) {
                          selected.add(i + 1);
                        } else {
                          selected.remove(i + 1);
                        }
                      }),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PremiumCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: nights,
                  onChanged: (value) => setState(() => nights = value),
                  title: const Text('Night driving', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: multi,
                  onChanged: (value) => setState(() => multi = value),
                  title: const Text('Multi-day tours', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const PremiumCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.location_on_rounded, color: AppColors.primaryDark),
              title: Text('Operating areas', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('Islamabad · Rawalpindi · Muzaffarabad · Neelum Valley'),
              trailing: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Availability saved.')),
            ),
            child: Text(context.tr('save')),
          ),
        ],
      );
}

// DriverReviewsScreen was here. It showed every driver the same invented
// "4.9" over "846 trips" and three fabricated passenger reviews. The real
// figures live on DriverEarningsScreen.

class DriverProfileScreen extends StatelessWidget { const DriverProfileScreen({required this.onNavigate,super.key}); final ValueChanged<String> onNavigate; @override Widget build(BuildContext context){final c=AppControllerScope.of(context);return ListView(padding:const EdgeInsets.all(18),children:[PremiumCard(color:AppColors.navy,child:Column(children:[const CircleAvatar(radius:38,backgroundColor:Colors.white,child:Icon(Icons.person_rounded,size:42,color:AppColors.primaryDark)),const SizedBox(height:12),Text(c.currentUserName,style:const TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(c.currentUserPhone,style:const TextStyle(color:Colors.white70,fontSize:11)),const SizedBox(height:13),StatusPill(label:c.driverVerificationStatus,color:c.driverApproved?AppColors.success:AppColors.warning)])),const SizedBox(height:15),FilledButton.icon(onPressed:()=>c.switchMode(UserMode.customer),icon:const Icon(Icons.person_rounded),label:Text(context.tr('switchCustomer'))),const SizedBox(height:13),for(final item in [('vehicles',Icons.directions_car_filled_rounded,context.tr('vehicles')),('documents',Icons.fact_check_rounded,context.tr('documents')),('availability',Icons.calendar_month_rounded,context.tr('availability')),('reviews',Icons.star_rounded,context.tr('reviews')),('settings',Icons.settings_rounded,context.tr('settings'))]) Padding(padding:const EdgeInsets.only(bottom:9),child:PremiumCard(onTap:()=>onNavigate(item.$1),child:Row(children:[Icon(item.$2,color:AppColors.primaryDark),const SizedBox(width:13),Expanded(child:Text(item.$3,style:const TextStyle(fontWeight:FontWeight.w900))),const Icon(Icons.chevron_right_rounded)]))) ]);}}
