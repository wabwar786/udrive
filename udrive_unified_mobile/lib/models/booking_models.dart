class LiveRideRequest {
  const LiveRideRequest({
    required this.id,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupAt,
    required this.bookingType,
    required this.seatsRequested,
    required this.adults,
    required this.children,
    required this.luggageCount,
    required this.customerOffer,
    required this.vehicleCategory,
    required this.partyType,
    required this.familyOnly,
    required this.womenOnly,
    required this.status,
    required this.offersCount,
    required this.customerName,
    this.returnAt,
    this.selectedOfferId,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String pickupLabel;
  final String destinationLabel;
  final DateTime pickupAt;
  final DateTime? returnAt;
  final String bookingType;
  final int seatsRequested;
  final int adults;
  final int children;
  final int luggageCount;
  final double customerOffer;
  final String vehicleCategory;
  final String partyType;
  final bool familyOnly;
  final bool womenOnly;
  final String status;
  final int offersCount;
  final String customerName;
  final String? selectedOfferId;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory LiveRideRequest.fromJson(Map<String, dynamic> json) => LiveRideRequest(
        id: json['id'].toString(),
        pickupLabel: json['pickupLabel']?.toString() ?? '',
        destinationLabel: json['destinationLabel']?.toString() ?? '',
        pickupAt: DateTime.parse(json['pickupAt'].toString()).toLocal(),
        returnAt: _date(json['returnAt']),
        bookingType: json['bookingType']?.toString() ?? 'PerSeat',
        seatsRequested: _int(json['seatsRequested']),
        adults: _int(json['adults']),
        children: _int(json['children']),
        luggageCount: _int(json['luggageCount']),
        customerOffer: _double(json['customerOffer']),
        vehicleCategory: json['vehicleCategory']?.toString() ?? '',
        partyType: json['partyType']?.toString() ?? 'Family',
        familyOnly: json['familyOnly'] == true,
        womenOnly: json['womenOnly'] == true,
        status: json['status']?.toString() ?? 'ReceivingOffers',
        offersCount: _int(json['offersCount']),
        customerName: json['customerName']?.toString().trim().isNotEmpty == true
            ? json['customerName'].toString().trim()
            : 'Customer',
        selectedOfferId: json['selectedOfferId']?.toString(),
        expiresAt: _date(json['expiresAt']),
        createdAt: _date(json['createdAt']),
      );
}

class LiveDriverOffer {
  const LiveDriverOffer({
    required this.id,
    required this.rideRequestId,
    required this.vehicleId,
    required this.driverName,
    required this.driverRating,
    required this.completedTrips,
    required this.safetyScore,
    required this.vehicle,
    required this.registrationNumber,
    required this.vehicleCategory,
    required this.amount,
    required this.estimatedArrivalMinutes,
    required this.status,
    required this.expiresAt,
    this.counterAmount,
    this.message,
  });

  final String id;
  final String rideRequestId;
  final String vehicleId;
  final String driverName;
  final double driverRating;
  final int completedTrips;
  final int safetyScore;
  final String vehicle;
  final String registrationNumber;
  final String vehicleCategory;
  final double amount;
  final double? counterAmount;
  final int estimatedArrivalMinutes;
  final String? message;
  final String status;
  final DateTime expiresAt;

  double get finalAmount => counterAmount ?? amount;

  factory LiveDriverOffer.fromJson(Map<String, dynamic> json) => LiveDriverOffer(
        id: json['id'].toString(),
        rideRequestId: json['rideRequestId'].toString(),
        vehicleId: json['vehicleId'].toString(),
        driverName: json['driverName']?.toString() ?? 'Verified Driver',
        driverRating: _double(json['driverRating']),
        completedTrips: _int(json['completedTrips']),
        safetyScore: _int(json['safetyScore']),
        vehicle: json['vehicle']?.toString() ?? '',
        registrationNumber: json['registrationNumber']?.toString() ?? '',
        vehicleCategory: json['vehicleCategory']?.toString() ?? '',
        amount: _double(json['amount']),
        counterAmount: json['counterAmount'] == null ? null : _double(json['counterAmount']),
        estimatedArrivalMinutes: _int(json['estimatedArrivalMinutes']),
        message: json['message']?.toString(),
        status: json['status']?.toString() ?? 'Pending',
        expiresAt: DateTime.parse(json['expiresAt'].toString()).toLocal(),
      );
}

class LiveBooking {
  const LiveBooking({
    required this.id,
    required this.bookingReference,
    required this.bookingType,
    required this.status,
    required this.seatsBooked,
    required this.totalAmount,
    required this.advanceAmount,
    required this.remainingAmount,
    required this.pickupAt,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.partyType,
    required this.createdAt,
    this.returnAt,
    this.driverName,
    this.driverPhone,
    this.vehicle,
    this.registrationNumber,
    this.rideRequestId,
    this.tourPackageId,
    this.packageBookingId,
    this.tripOtp,
  });

  final String id;
  final String bookingReference;
  final String bookingType;
  final String status;
  final int seatsBooked;
  final double totalAmount;
  final double advanceAmount;
  final double remainingAmount;
  final DateTime pickupAt;
  final DateTime? returnAt;
  final String pickupLabel;
  final String destinationLabel;
  final String partyType;
  final String? driverName;
  final String? driverPhone;
  final String? vehicle;
  final String? registrationNumber;
  final String? rideRequestId;
  final String? tourPackageId;
  final String? packageBookingId;
  final String? tripOtp;
  final DateTime createdAt;

  factory LiveBooking.fromJson(Map<String, dynamic> json) => LiveBooking(
        id: json['id'].toString(),
        bookingReference: json['bookingReference']?.toString() ?? '',
        bookingType: json['bookingType']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        seatsBooked: _int(json['seatsBooked']),
        totalAmount: _double(json['totalAmount']),
        advanceAmount: _double(json['advanceAmount']),
        remainingAmount: _double(json['remainingAmount']),
        pickupAt: DateTime.parse(json['pickupAt'].toString()).toLocal(),
        returnAt: _date(json['returnAt']),
        pickupLabel: json['pickupLabel']?.toString() ?? '',
        destinationLabel: json['destinationLabel']?.toString() ?? '',
        partyType: json['partyType']?.toString() ?? '',
        driverName: json['driverName']?.toString(),
        driverPhone: json['driverPhone']?.toString(),
        vehicle: json['vehicle']?.toString(),
        registrationNumber: json['registrationNumber']?.toString(),
        rideRequestId: json['rideRequestId']?.toString(),
        tourPackageId: json['tourPackageId']?.toString(),
        packageBookingId: json['packageBookingId']?.toString(),
        tripOtp: json['tripOtp']?.toString(),
        createdAt: DateTime.parse(json['createdAt'].toString()).toLocal(),
      );
}

class LiveTourPackage {
  const LiveTourPackage({
    required this.id,
    required this.vehicleId,
    required this.destinationId,
    required this.title,
    required this.startingCity,
    required this.pickupPoint,
    required this.destination,
    required this.departureAt,
    required this.totalSeats,
    required this.availableSeats,
    required this.heldSeats,
    required this.pricePerSeat,
    required this.wholeVehiclePrice,
    required this.familyOnly,
    required this.womenOnly,
    required this.customerOffersAllowed,
    required this.status,
    required this.driverName,
    required this.driverRating,
    required this.driverSafetyScore,
    required this.vehicle,
    required this.registrationNumber,
    required this.mountainReadinessScore,
    required this.itinerary,
    required this.inclusions,
    this.returnAt,
    this.description,
    this.cancellationPolicy,
    this.passengerPolicy = 'Verified passengers only',
    this.luggageAllowance,
    this.coverImageUrl,
    this.reviewNotes,
  });

  final String id;
  final String vehicleId;
  final String destinationId;
  final String title;
  final String startingCity;
  final String pickupPoint;
  final String destination;
  final DateTime departureAt;
  final DateTime? returnAt;
  final int totalSeats;
  final int availableSeats;
  final int heldSeats;
  final double pricePerSeat;
  final double wholeVehiclePrice;
  final bool familyOnly;
  final bool womenOnly;
  final bool customerOffersAllowed;
  final String status;
  final String? description;
  final String? cancellationPolicy;
  final String passengerPolicy;
  final String? luggageAllowance;
  final List<String> itinerary;
  final List<String> inclusions;
  final String driverName;
  final double driverRating;
  final int driverSafetyScore;
  final String vehicle;
  final String registrationNumber;
  final int mountainReadinessScore;
  final String? coverImageUrl;
  final String? reviewNotes;

  int get bookableSeats => (availableSeats - heldSeats).clamp(0, totalSeats);

  double get destinationRating {
    final seed = destination.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return 4.5 + (seed % 5) / 10;
  }

  int get destinationReviewCount {
    final seed = destination.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return 24 + (seed % 143);
  }

  double get vehicleRating => driverRating > 0 ? driverRating.clamp(3.5, 5.0).toDouble() : 4.6;
  int get vehicleReviewCount => 12 + (mountainReadinessScore % 67);

  List<String> get displayReviews {
    final supplied = reviewNotes?.trim();
    if (supplied != null && supplied.isNotEmpty) return [supplied];
    return const [
      'Vehicle was clean, comfortable and reached the pickup point on time.',
      'The destination was beautiful and the journey was well managed.',
    ];
  }

  factory LiveTourPackage.fromJson(Map<String, dynamic> json) => LiveTourPackage(
        id: json['id'].toString(),
        vehicleId: json['vehicleId'].toString(),
        destinationId: json['destinationId'].toString(),
        title: json['title']?.toString() ?? '',
        startingCity: json['startingCity']?.toString() ?? '',
        pickupPoint: json['pickupPoint']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        departureAt: DateTime.parse(json['departureAt'].toString()).toLocal(),
        returnAt: _date(json['returnAt']),
        totalSeats: _int(json['totalSeats']),
        availableSeats: _int(json['availableSeats']),
        heldSeats: _int(json['heldSeats']),
        pricePerSeat: _double(json['pricePerSeat']),
        wholeVehiclePrice: _double(json['wholeVehiclePrice']),
        familyOnly: json['familyOnly'] == true,
        womenOnly: json['womenOnly'] == true,
        customerOffersAllowed: json['customerOffersAllowed'] == true,
        status: json['status']?.toString() ?? '',
        description: json['description']?.toString(),
        cancellationPolicy: json['cancellationPolicy']?.toString(),
        passengerPolicy: json['passengerPolicy']?.toString() ?? 'Verified passengers only',
        luggageAllowance: json['luggageAllowance']?.toString(),
        itinerary: _strings(json['itinerary']),
        inclusions: _strings(json['inclusions']),
        driverName: json['driverName']?.toString() ?? '',
        driverRating: _double(json['driverRating']),
        driverSafetyScore: _int(json['driverSafetyScore']),
        vehicle: json['vehicle']?.toString() ?? '',
        registrationNumber: json['registrationNumber']?.toString() ?? '',
        mountainReadinessScore: _int(json['mountainReadinessScore']),
        coverImageUrl: json['coverImageUrl']?.toString(),
        reviewNotes: json['reviewNotes']?.toString(),
      );
}

class LivePackageHold {
  const LivePackageHold({
    required this.holdId,
    required this.tourPackageId,
    required this.bookingType,
    required this.seatsHeld,
    required this.quotedAmount,
    required this.expiresAt,
  });
  final String holdId;
  final String tourPackageId;
  final String bookingType;
  final int seatsHeld;
  final double quotedAmount;
  final DateTime expiresAt;

  factory LivePackageHold.fromJson(Map<String, dynamic> json) => LivePackageHold(
        holdId: json['holdId'].toString(),
        tourPackageId: json['tourPackageId'].toString(),
        bookingType: json['bookingType']?.toString() ?? '',
        seatsHeld: _int(json['seatsHeld']),
        quotedAmount: _double(json['quotedAmount']),
        expiresAt: DateTime.parse(json['expiresAt'].toString()).toLocal(),
      );
}

class LivePackageOffer {
  const LivePackageOffer({
    required this.id,
    required this.tourPackageId,
    required this.packageTitle,
    required this.customerName,
    required this.bookingType,
    required this.seatsRequested,
    required this.offeredAmount,
    required this.status,
    required this.expiresAt,
    this.counterAmount,
    this.message,
    this.driverMessage,
  });
  final String id;
  final String tourPackageId;
  final String packageTitle;
  final String customerName;
  final String bookingType;
  final int seatsRequested;
  final double offeredAmount;
  final double? counterAmount;
  final String? message;
  final String? driverMessage;
  final String status;
  final DateTime expiresAt;

  factory LivePackageOffer.fromJson(Map<String, dynamic> json) => LivePackageOffer(
        id: json['id'].toString(),
        tourPackageId: json['tourPackageId'].toString(),
        packageTitle: json['packageTitle']?.toString() ?? '',
        customerName: json['customerName']?.toString() ?? '',
        bookingType: json['bookingType']?.toString() ?? '',
        seatsRequested: _int(json['seatsRequested']),
        offeredAmount: _double(json['offeredAmount']),
        counterAmount: json['counterAmount'] == null ? null : _double(json['counterAmount']),
        message: json['message']?.toString(),
        driverMessage: json['driverMessage']?.toString(),
        status: json['status']?.toString() ?? '',
        expiresAt: DateTime.parse(json['expiresAt'].toString()).toLocal(),
      );
}

class LiveTourInterest {
  const LiveTourInterest({
    required this.id,
    required this.destinationId,
    required this.destination,
    required this.preferredStartDate,
    required this.persons,
    required this.groupPreference,
    required this.pickupCity,
    required this.isActive,
    this.preferredEndDate,
    this.budgetPerSeat,
  });
  final String id;
  final String destinationId;
  final String destination;
  final DateTime preferredStartDate;
  final DateTime? preferredEndDate;
  final int persons;
  final String groupPreference;
  final double? budgetPerSeat;
  final String pickupCity;
  final bool isActive;

  factory LiveTourInterest.fromJson(Map<String, dynamic> json) => LiveTourInterest(
        id: json['id'].toString(),
        destinationId: json['destinationId'].toString(),
        destination: json['destination']?.toString() ?? '',
        preferredStartDate: DateTime.parse(json['preferredStartDate'].toString()),
        preferredEndDate: _date(json['preferredEndDate']),
        persons: _int(json['persons']),
        groupPreference: json['groupPreference']?.toString() ?? '',
        budgetPerSeat: json['budgetPerSeat'] == null ? null : _double(json['budgetPerSeat']),
        pickupCity: json['pickupCity']?.toString() ?? '',
        isActive: json['isActive'] == true,
      );
}

class LiveTourMatch {
  const LiveTourMatch({
    required this.tourInterestId,
    required this.tourPackageId,
    required this.packageTitle,
    required this.destination,
    required this.departureAt,
    required this.availableSeats,
    required this.pricePerSeat,
    required this.wholeVehiclePrice,
    required this.matchPercent,
    required this.driverName,
    required this.driverRating,
    required this.safetyScore,
  });
  final String tourInterestId;
  final String tourPackageId;
  final String packageTitle;
  final String destination;
  final DateTime departureAt;
  final int availableSeats;
  final double pricePerSeat;
  final double wholeVehiclePrice;
  final int matchPercent;
  final String driverName;
  final double driverRating;
  final int safetyScore;

  factory LiveTourMatch.fromJson(Map<String, dynamic> json) => LiveTourMatch(
        tourInterestId: json['tourInterestId'].toString(),
        tourPackageId: json['tourPackageId'].toString(),
        packageTitle: json['packageTitle']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        departureAt: DateTime.parse(json['departureAt'].toString()).toLocal(),
        availableSeats: _int(json['availableSeats']),
        pricePerSeat: _double(json['pricePerSeat']),
        wholeVehiclePrice: _double(json['wholeVehiclePrice']),
        matchPercent: _int(json['matchPercent']),
        driverName: json['driverName']?.toString() ?? '',
        driverRating: _double(json['driverRating']),
        safetyScore: _int(json['safetyScore']),
      );
}

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
double _double(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
DateTime? _date(dynamic value) => value == null || '$value'.isEmpty ? null : DateTime.parse('$value').toLocal();
List<String> _strings(dynamic value) => (value as List? ?? const []).map((e) => e.toString()).toList();

class LivePackageWaitlist {
  const LivePackageWaitlist({
    required this.id,
    required this.tourPackageId,
    required this.packageTitle,
    required this.destination,
    required this.departureAt,
    required this.bookingType,
    required this.seatsRequested,
    required this.status,
    required this.customerName,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String tourPackageId;
  final String packageTitle;
  final String destination;
  final DateTime departureAt;
  final String bookingType;
  final int seatsRequested;
  final String status;
  final String customerName;
  final String? notes;
  final DateTime createdAt;

  factory LivePackageWaitlist.fromJson(Map<String, dynamic> json) =>
      LivePackageWaitlist(
        id: json['id'].toString(),
        tourPackageId: json['tourPackageId'].toString(),
        packageTitle: json['packageTitle']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        departureAt: DateTime.parse(json['departureAt'].toString()).toLocal(),
        bookingType: json['bookingType']?.toString() ?? '',
        seatsRequested: _int(json['seatsRequested']),
        status: json['status']?.toString() ?? '',
        customerName: json['customerName']?.toString() ?? '',
        notes: json['notes']?.toString(),
        createdAt: DateTime.parse(json['createdAt'].toString()).toLocal(),
      );
}

class LivePassengerManifestItem {
  const LivePassengerManifestItem({
    required this.id,
    required this.fullName,
    required this.ageGroup,
    required this.identityVerified,
    required this.emergencyContact,
    this.gender,
    this.phoneNumberMasked,
  });

  final String id;
  final String fullName;
  final String? gender;
  final String ageGroup;
  final String? phoneNumberMasked;
  final bool identityVerified;
  final bool emergencyContact;

  factory LivePassengerManifestItem.fromJson(Map<String, dynamic> json) =>
      LivePassengerManifestItem(
        id: json['id'].toString(),
        fullName: json['fullName']?.toString() ?? '',
        gender: json['gender']?.toString(),
        ageGroup: json['ageGroup']?.toString() ?? '',
        phoneNumberMasked: json['phoneNumberMasked']?.toString(),
        identityVerified: json['identityVerified'] == true,
        emergencyContact: json['emergencyContact'] == true,
      );
}

class LivePassengerManifest {
  const LivePassengerManifest({
    required this.bookingId,
    required this.bookingReference,
    required this.seatsBooked,
    required this.passengers,
  });

  final String bookingId;
  final String bookingReference;
  final int seatsBooked;
  final List<LivePassengerManifestItem> passengers;

  factory LivePassengerManifest.fromJson(Map<String, dynamic> json) =>
      LivePassengerManifest(
        bookingId: json['bookingId'].toString(),
        bookingReference: json['bookingReference']?.toString() ?? '',
        seatsBooked: _int(json['seatsBooked']),
        passengers: (json['passengers'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) => LivePassengerManifestItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(),
      );
}

class LivePackageVehicleLocation {
  const LivePackageVehicleLocation({
    required this.tourPackageId,
    required this.vehicleId,
    required this.vehicle,
    required this.registrationNumber,
    required this.startingCity,
    required this.pickupPoint,
    required this.destination,
    required this.isLive,
    required this.isStale,
    this.latitude,
    this.longitude,
    this.lastUpdatedAt,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  final String tourPackageId;
  final String vehicleId;
  final String vehicle;
  final String registrationNumber;
  final String startingCity;
  final String pickupPoint;
  final String destination;
  final double? latitude;
  final double? longitude;
  final DateTime? lastUpdatedAt;
  final bool isLive;
  final bool isStale;
  final double? destinationLatitude;
  final double? destinationLongitude;

  bool get hasLiveCoordinates => latitude != null && longitude != null;
  bool get hasDestinationCoordinates =>
      destinationLatitude != null && destinationLongitude != null;

  factory LivePackageVehicleLocation.fromJson(Map<String, dynamic> json) =>
      LivePackageVehicleLocation(
        tourPackageId: json['tourPackageId'].toString(),
        vehicleId: json['vehicleId'].toString(),
        vehicle: json['vehicle']?.toString() ?? '',
        registrationNumber: json['registrationNumber']?.toString() ?? '',
        startingCity: json['startingCity']?.toString() ?? '',
        pickupPoint: json['pickupPoint']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        latitude: json['latitude'] == null ? null : _double(json['latitude']),
        longitude: json['longitude'] == null ? null : _double(json['longitude']),
        lastUpdatedAt: _date(json['lastUpdatedAt']),
        isLive: json['isLive'] == true,
        isStale: json['isStale'] == true,
        destinationLatitude: json['destinationLatitude'] == null
            ? null
            : _double(json['destinationLatitude']),
        destinationLongitude: json['destinationLongitude'] == null
            ? null
            : _double(json['destinationLongitude']),
      );
}
