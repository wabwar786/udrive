import 'package:flutter/material.dart';

enum UserMode { customer, driver }

enum VerificationStatus { verified, pending, draft, rejected }

class ServiceItem {
  const ServiceItem({required this.id, required this.titleKey, required this.icon, required this.color});
  final String id;
  final String titleKey;
  final IconData icon;
  final Color color;
}

class DestinationItem {
  const DestinationItem({required this.name, required this.location, required this.image, required this.rating, required this.travelTime, required this.description});
  final String name;
  final String location;
  final String image;
  final double rating;
  final String travelTime;
  final String description;
}

class VehicleCategory {
  const VehicleCategory({required this.name, required this.icon, required this.seats, required this.luggage, required this.baseFare, required this.description});
  final String name;
  final IconData icon;
  final int seats;
  final int luggage;
  final int baseFare;
  final String description;
}

class DriverOffer {
  const DriverOffer({required this.id, required this.name, required this.vehicle, required this.registration, required this.rating, required this.trips, required this.eta, required this.price, required this.verified});
  final String id;
  final String name;
  final String vehicle;
  final String registration;
  final double rating;
  final int trips;
  final int eta;
  final int price;
  final bool verified;
}

class RideRequest {
  RideRequest({required this.id, required this.pickup, required this.destination, required this.customer, required this.distance, required this.passengers, required this.offer, required this.time, required this.category, this.status = 'New'});
  final String id;
  final String pickup;
  final String destination;
  final String customer;
  final String distance;
  final int passengers;
  final int offer;
  final String time;
  final String category;
  String status;
}

class TripRecord {
  const TripRecord({required this.id, required this.route, required this.date, required this.status, required this.driver, required this.vehicle, required this.price});
  final String id;
  final String route;
  final String date;
  final String status;
  final String driver;
  final String vehicle;
  final int price;
}

class TourPackage {
  TourPackage({required this.id, required this.title, required this.route, required this.days, required this.price, required this.image, required this.driver, required this.rating, required this.maxGuests, required this.vehicle, required this.description, required this.inclusions, required this.itinerary, this.allowOffers = true, this.status = 'Active'});
  final String id;
  final String title;
  final String route;
  final int days;
  final int price;
  final String image;
  final String driver;
  final double rating;
  final int maxGuests;
  final String vehicle;
  final String description;
  final List<String> inclusions;
  final List<String> itinerary;
  final bool allowOffers;
  String status;
}

class AppNotificationItem {
  const AppNotificationItem({required this.title, required this.body, required this.time, required this.icon, required this.color, this.unread = true});
  final String title;
  final String body;
  final String time;
  final IconData icon;
  final Color color;
  final bool unread;
}

class WalletTransaction {
  const WalletTransaction({required this.title, required this.date, required this.amount, required this.credit});
  final String title;
  final String date;
  final int amount;
  final bool credit;
}

class VehicleRecord {
  VehicleRecord({required this.id, required this.make, required this.model, required this.year, required this.color, required this.registration, required this.category, required this.seats, required this.luggage, required this.airConditioning, required this.fourWheelDrive, required this.status, required this.documents});
  final String id;
  final String make;
  final String model;
  final int year;
  final String color;
  final String registration;
  final String category;
  final int seats;
  final int luggage;
  final bool airConditioning;
  final bool fourWheelDrive;
  VerificationStatus status;
  final Map<String, bool> documents;
}

class DriverDocument {
  const DriverDocument({required this.title, required this.number, required this.expiry, required this.status});
  final String title;
  final String number;
  final String expiry;
  final VerificationStatus status;
}
