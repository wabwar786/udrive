import 'package:flutter/material.dart';

enum UserMode { customer, driver }

enum VerificationStatus { verified, pending, draft, rejected }

enum BookingType { perSeat, wholeVehicle }

enum TripPartyType { individual, family, womenOnly, group }

class ServiceItem {
  const ServiceItem({required this.id, required this.titleKey, required this.icon, required this.color});
  final String id;
  final String titleKey;
  final IconData icon;
  final Color color;
}

class DestinationItem {
  const DestinationItem({
    required this.name,
    required this.location,
    required this.image,
    required this.rating,
    required this.travelTime,
    required this.description,
    this.bestSeason = 'April – October',
    this.roadCondition = 'Mountain road',
    this.recommendedVehicle = 'SUV',
    this.networkStatus = 'Limited in remote areas',
    this.familyFriendly = true,
    this.safetyScore = 84,
  });
  final String name;
  final String location;
  final String image;
  final double rating;
  final String travelTime;
  final String description;
  final String bestSeason;
  final String roadCondition;
  final String recommendedVehicle;
  final String networkStatus;
  final bool familyFriendly;
  final int safetyScore;
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
  const DriverOffer({
    required this.id,
    required this.name,
    required this.vehicle,
    required this.registration,
    required this.rating,
    required this.trips,
    required this.eta,
    required this.price,
    required this.verified,
    this.routeExperience = 24,
    this.safetyScore = 92,
    this.familyRecommended = true,
  });
  final String id;
  final String name;
  final String vehicle;
  final String registration;
  final double rating;
  final int trips;
  final int eta;
  final int price;
  final bool verified;
  final int routeExperience;
  final int safetyScore;
  final bool familyRecommended;
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
  TourPackage({
    required this.id,
    required this.title,
    required this.route,
    required this.days,
    required this.price,
    required this.image,
    required this.driver,
    required this.rating,
    required this.maxGuests,
    required this.vehicle,
    required this.description,
    required this.inclusions,
    required this.itinerary,
    this.allowOffers = true,
    this.status = 'Active',
    this.pricePerSeat,
    this.wholeVehiclePrice,
    this.availableSeats,
    this.departureDate = '15 Aug 2026',
    this.departureTime = '7:00 AM',
    this.pickupPoint = 'Ghari Pan, Muzaffarabad',
    this.familyOnly = false,
    this.womenOnly = false,
    this.verifiedPassengers = true,
    this.safetyScore = 90,
  });
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
  final int? pricePerSeat;
  final int? wholeVehiclePrice;
  final int? availableSeats;
  final String departureDate;
  final String departureTime;
  final String pickupPoint;
  final bool familyOnly;
  final bool womenOnly;
  final bool verifiedPassengers;
  final int safetyScore;
}

class SharedTour {
  const SharedTour({
    required this.id,
    required this.title,
    required this.pickup,
    required this.destination,
    required this.departureDate,
    required this.departureTime,
    required this.vehicle,
    required this.driver,
    required this.rating,
    required this.totalSeats,
    required this.availableSeats,
    required this.pricePerSeat,
    required this.wholeVehiclePrice,
    required this.partyType,
    required this.matchPercent,
    required this.safetyScore,
    this.malePassengers = 0,
    this.femalePassengers = 0,
    this.children = 0,
    this.verifiedDriver = true,
    this.verifiedPassengers = true,
  });
  final String id;
  final String title;
  final String pickup;
  final String destination;
  final String departureDate;
  final String departureTime;
  final String vehicle;
  final String driver;
  final double rating;
  final int totalSeats;
  final int availableSeats;
  final int pricePerSeat;
  final int wholeVehiclePrice;
  final TripPartyType partyType;
  final int matchPercent;
  final int safetyScore;
  final int malePassengers;
  final int femalePassengers;
  final int children;
  final bool verifiedDriver;
  final bool verifiedPassengers;
}

class AdvanceBooking {
  AdvanceBooking({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.departureDate,
    required this.departureTime,
    required this.bookingType,
    required this.adults,
    required this.children,
    required this.luggage,
    required this.vehicle,
    required this.estimatedTotal,
    required this.partyType,
    this.returnDate,
    this.notes = '',
    this.status = 'Awaiting offers',
  });
  final String id;
  final String pickup;
  final String destination;
  final DateTime departureDate;
  final TimeOfDay departureTime;
  final BookingType bookingType;
  final int adults;
  final int children;
  final int luggage;
  final String vehicle;
  final int estimatedTotal;
  final TripPartyType partyType;
  final DateTime? returnDate;
  final String notes;
  String status;
}

class TourInterest {
  TourInterest({
    required this.id,
    required this.destination,
    required this.pickupCity,
    required this.dateFrom,
    required this.dateTo,
    required this.persons,
    required this.budgetPerSeat,
    required this.partyType,
    required this.vehiclePreference,
    this.status = 'Matching tours',
  });
  final String id;
  final String destination;
  final String pickupCity;
  final DateTime dateFrom;
  final DateTime dateTo;
  final int persons;
  final int budgetPerSeat;
  final TripPartyType partyType;
  final String vehiclePreference;
  String status;
}

class FamilyTourPlan {
  const FamilyTourPlan({
    required this.id,
    required this.startLocation,
    required this.destination,
    required this.days,
    required this.adults,
    required this.children,
    required this.infants,
    required this.elderly,
    required this.budget,
    required this.vehicle,
    required this.estimatedTotal,
    required this.itinerary,
    required this.hotelSuggestion,
    required this.safetyScore,
  });
  final String id;
  final String startLocation;
  final String destination;
  final int days;
  final int adults;
  final int children;
  final int infants;
  final int elderly;
  final int budget;
  final String vehicle;
  final int estimatedTotal;
  final List<String> itinerary;
  final String hotelSuggestion;
  final int safetyScore;
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
