import '../models/driver_models.dart';

const rideRequests = [
  RideRequest(
    customer: 'Sarah Malik',
    route: 'Muzaffarabad → Keran',
    offer: 5000,
    distance: '93 km',
    passengers: 3,
    time: 'Today · 09:30',
    type: 'Intercity',
  ),
  RideRequest(
    customer: 'Hamza Tariq',
    route: 'Islamabad → Muzaffarabad',
    offer: 12000,
    distance: '138 km',
    passengers: 2,
    time: '18 Jul · 08:00',
    type: 'Scheduled',
  ),
  RideRequest(
    customer: 'Ayesha Noor',
    route: 'Sharda → Kel',
    offer: 4500,
    distance: '19 km',
    passengers: 4,
    time: 'Today · 13:15',
    type: '4×4',
  ),
];

const driverPackages = [
  DriverPackage(
    title: 'Neelum Valley Escape',
    route: 'Muzaffarabad · Keran · Sharda',
    price: 58000,
    status: 'Active',
    days: 3,
    bookings: 8,
  ),
  DriverPackage(
    title: 'Leepa Valley Adventure',
    route: 'Reshian · Leepa',
    price: 76000,
    status: 'Pending Approval',
    days: 4,
    bookings: 0,
  ),
];
