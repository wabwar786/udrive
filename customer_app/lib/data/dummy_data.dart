import '../models/models.dart';

const driverOffers = [
  DriverOffer(name: 'Usman Khan', vehicle: 'Toyota Corolla · LEA-219', rating: 4.9, trips: 834, price: 5200, etaMinutes: 6, verified: true),
  DriverOffer(name: 'Adeel Mir', vehicle: 'Honda BR-V · AJK-704', rating: 4.8, trips: 501, price: 5600, etaMinutes: 4, verified: true),
  DriverOffer(name: 'Naveed Ahmed', vehicle: 'Suzuki Ertiga · RIH-882', rating: 4.7, trips: 292, price: 4900, etaMinutes: 9, verified: false),
];

const tourPackages = [
  TourPackage(title: 'Neelum Valley Escape', route: 'Muzaffarabad · Keran · Sharda', driver: 'Usman Khan', days: 3, price: 58000, rating: 4.9, vehicle: 'SUV', imageColor: 0xFF0F766E),
  TourPackage(title: 'Rawalakot Family Weekend', route: 'Rawalakot · Banjosa · Toli Pir', driver: 'Adeel Mir', days: 2, price: 36000, rating: 4.8, vehicle: '7-Seater', imageColor: 0xFF2563EB),
  TourPackage(title: 'Leepa Valley Adventure', route: 'Muzaffarabad · Reshian · Leepa', driver: 'Naveed Ahmed', days: 4, price: 76000, rating: 4.7, vehicle: '4×4 Jeep', imageColor: 0xFFF59E0B),
];

const tripRecords = [
  TripRecord(route: 'Islamabad → Muzaffarabad', date: '18 Jul 2026 · 08:00', driver: 'Usman Khan', price: 12500, status: 'upcoming'),
  TripRecord(route: 'Muzaffarabad → Pir Chinasi', date: '03 Jul 2026 · 10:30', driver: 'Adeel Mir', price: 6800, status: 'completed'),
  TripRecord(route: 'Rawalakot → Banjosa Lake', date: '25 Jun 2026 · 09:15', driver: 'Naveed Ahmed', price: 4200, status: 'completed'),
];
