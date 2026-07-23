import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'models.dart';

const services = [
  ServiceItem(id: 'local', titleKey: 'localRide', icon: Icons.local_taxi_rounded, color: AppColors.primary),
  ServiceItem(id: 'intercity', titleKey: 'intercity', icon: Icons.route_rounded, color: AppColors.secondary),
  ServiceItem(id: 'day', titleKey: 'fullDay', icon: Icons.today_rounded, color: AppColors.accent),
  ServiceItem(id: 'jeep', titleKey: 'jeep', icon: Icons.directions_car_filled_rounded, color: Color(0xFF7C3AED)),
  ServiceItem(id: 'shared', titleKey: 'sharedRide', icon: Icons.groups_rounded, color: Color(0xFFEA580C)),
  ServiceItem(id: 'airport', titleKey: 'airport', icon: Icons.flight_takeoff_rounded, color: Color(0xFF0284C7)),
];

const destinations = [
  DestinationItem(name: 'Neelum Valley', location: 'Azad Kashmir', image: 'assets/images/neelum.png', rating: 4.9, travelTime: '4h 20m', description: 'A spectacular valley of rivers, forests and mountain villages.'),
  DestinationItem(name: 'Arang Kel', location: 'Kel, Neelum', image: 'assets/images/arang_kel.png', rating: 4.8, travelTime: '6h 10m', description: 'A green hilltop village reached through a scenic chairlift and hike.'),
  DestinationItem(name: 'Banjosa Lake', location: 'Rawalakot', image: 'assets/images/banjosa.png', rating: 4.7, travelTime: '2h 40m', description: 'A peaceful artificial lake surrounded by pine forests.'),
  DestinationItem(name: 'Pir Chinasi', location: 'Muzaffarabad', image: 'assets/images/pir_chinasi.png', rating: 4.8, travelTime: '1h 35m', description: 'A panoramic mountain viewpoint above Muzaffarabad.'),
];

const vehicleCategories = [
  VehicleCategory(name: 'Economy', icon: Icons.directions_car_rounded, seats: 4, luggage: 2, baseFare: 2600, description: 'Affordable city and highway travel'),
  VehicleCategory(name: 'Comfort', icon: Icons.airline_seat_recline_extra_rounded, seats: 4, luggage: 3, baseFare: 3400, description: 'Newer cars with added comfort'),
  VehicleCategory(name: 'SUV', icon: Icons.directions_car_filled_rounded, seats: 6, luggage: 4, baseFare: 5200, description: 'Families and mountain routes'),
  VehicleCategory(name: '4×4 Jeep', icon: Icons.terrain_rounded, seats: 5, luggage: 3, baseFare: 6800, description: 'Rough roads and remote valleys'),
  VehicleCategory(name: 'Hiace', icon: Icons.airport_shuttle_rounded, seats: 14, luggage: 8, baseFare: 11000, description: 'Groups and tour parties'),
];

const driverOffers = [
  DriverOffer(id: 'd1', name: 'Adeel Khan', vehicle: 'Toyota Corolla 2022', registration: 'AJK-4821', rating: 4.9, trips: 846, eta: 4, price: 5200, verified: true),
  DriverOffer(id: 'd2', name: 'Noman Abbasi', vehicle: 'Honda BR-V 2021', registration: 'ICT-2190', rating: 4.8, trips: 512, eta: 7, price: 5600, verified: true),
  DriverOffer(id: 'd3', name: 'Rashid Mughal', vehicle: 'Toyota Prado 2018', registration: 'AJK-9044', rating: 4.7, trips: 329, eta: 10, price: 6500, verified: true),
];

final rideRequests = [
  RideRequest(id: 'R-1041', pickup: 'Srinagar Highway, Islamabad', destination: 'Muzaffarabad', customer: 'Hassan Ali', distance: '126 km', passengers: 3, offer: 7200, time: 'Today · 4:30 PM', category: 'SUV'),
  RideRequest(id: 'R-1042', pickup: 'Muzaffarabad', destination: 'Keran, Neelum Valley', customer: 'Ayesha Noor', distance: '95 km', passengers: 4, offer: 8500, time: 'Tomorrow · 8:00 AM', category: '4×4 Jeep'),
  RideRequest(id: 'R-1043', pickup: 'Rawalpindi Saddar', destination: 'Banjosa Lake', customer: 'Waqar Ahmed', distance: '115 km', passengers: 5, offer: 9000, time: '18 Jul · 7:00 AM', category: 'Hiace'),
];

const trips = [
  TripRecord(id: 'T-9001', route: 'Islamabad → Muzaffarabad', date: '15 Jul 2026 · 9:30 AM', status: 'Upcoming', driver: 'Adeel Khan', vehicle: 'Toyota Corolla', price: 7200),
  TripRecord(id: 'T-8987', route: 'Muzaffarabad → Pir Chinasi', date: '08 Jul 2026 · 11:00 AM', status: 'Completed', driver: 'Noman Abbasi', vehicle: 'Honda BR-V', price: 4800),
  TripRecord(id: 'T-8940', route: 'Islamabad → Neelum Valley', date: '29 Jun 2026 · 7:00 AM', status: 'Completed', driver: 'Rashid Mughal', vehicle: 'Toyota Prado', price: 18500),
];

final tourPackages = [
  TourPackage(id: 'P-101', title: '3-Day Neelum Escape', route: 'Islamabad · Muzaffarabad · Keran · Sharda', days: 3, price: 58000, image: 'assets/images/neelum.png', driver: 'Adeel Khan', rating: 4.9, maxGuests: 6, vehicle: 'Honda BR-V', description: 'A private three-day road trip through the most scenic parts of Neelum Valley with flexible stops.', inclusions: ['Private vehicle', 'Fuel & tolls', 'Driver services', 'Flexible sightseeing'], itinerary: ['Day 1: Islamabad to Keran', 'Day 2: Sharda and Upper Neelum', 'Day 3: Return via Muzaffarabad']),
  TourPackage(id: 'P-102', title: 'Rawalakot Family Weekend', route: 'Islamabad · Toli Pir · Banjosa Lake', days: 2, price: 36000, image: 'assets/images/banjosa.png', driver: 'Noman Abbasi', rating: 4.8, maxGuests: 5, vehicle: 'Toyota Corolla', description: 'A relaxed weekend package designed for families, with comfortable driving and scenic stops.', inclusions: ['Private vehicle', 'Fuel', 'Pickup and drop-off', 'Child-friendly stops'], itinerary: ['Day 1: Islamabad to Toli Pir', 'Day 2: Banjosa Lake and return']),
  TourPackage(id: 'P-103', title: 'Arang Kel Adventure', route: 'Muzaffarabad · Sharda · Kel · Arang Kel', days: 4, price: 76000, image: 'assets/images/arang_kel.png', driver: 'Rashid Mughal', rating: 4.7, maxGuests: 5, vehicle: 'Toyota Prado', description: 'A premium 4×4 trip to Kel and Arang Kel with route guidance and local sightseeing.', inclusions: ['4×4 vehicle', 'Fuel and tolls', 'Driver accommodation', 'Route assistance'], itinerary: ['Day 1: Muzaffarabad to Sharda', 'Day 2: Kel and Arang Kel', 'Day 3: Local sightseeing', 'Day 4: Return']),
];

const notifications = [
  AppNotificationItem(title: 'Driver offer received', body: 'Adeel Khan offered PKR 5,200 for your requested trip.', time: '2 min ago', icon: Icons.local_offer_rounded, color: AppColors.primary),
  AppNotificationItem(title: 'Road advisory', body: 'Light rain is expected on the Muzaffarabad–Keran route.', time: '45 min ago', icon: Icons.warning_amber_rounded, color: AppColors.warning),
  AppNotificationItem(title: 'Package approved', body: 'Your “Neelum Family Tour” package is now active.', time: 'Yesterday', icon: Icons.verified_rounded, color: AppColors.info, unread: false),
];

const walletTransactions = [
  WalletTransaction(title: 'Ride payment', date: '08 Jul 2026', amount: 4800, credit: false),
  WalletTransaction(title: 'Wallet top-up', date: '05 Jul 2026', amount: 10000, credit: true),
  WalletTransaction(title: 'Referral reward', date: '01 Jul 2026', amount: 500, credit: true),
];

const driverDocuments = [
  DriverDocument(title: 'CNIC', number: '61101-1234567-1', expiry: 'Permanent', status: VerificationStatus.verified),
  DriverDocument(title: 'Driving licence', number: 'AJK-DL-904821', expiry: '12 Dec 2028', status: VerificationStatus.verified),
  DriverDocument(title: 'Police verification', number: 'PV-2026-4492', expiry: '04 Mar 2027', status: VerificationStatus.pending),
];
