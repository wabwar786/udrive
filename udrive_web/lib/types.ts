export type Driver = { name: string; initials: string; rating: number; toursDone: number };

export type TourCard = {
  id: string;
  title: string;
  destination: string;
  destinationSlug: string;
  from: string;
  pickupPoint: string | null;
  departureAt: string;
  returnAt: string | null;
  days: number;
  totalSeats: number;
  seatsLeft: number;
  pricePerSeat: number;
  wholeVehiclePrice: number;
  wholeVehicleAvailable: boolean;
  vehicle: string;
  imageUrl: string | null;
  driver: Driver;
};

export type TourDetail = {
  tour: TourCard;
  description: string | null;
  routeStops: string[];
  included: string[];
  notIncluded: string[];
  plan: { day: number; title: string; text: string }[];
  images: string[];
  cancellationPolicy: string | null;
  passengerPolicy: string;
  luggage: string | null;
  familyOnly: boolean;
  womenOnly: boolean;
  advancePercent: number;
};

export type Destination = {
  id: string;
  slug: string;
  name: string;
  district: string;
  summary: string;
  bestSeason: string;
  imageUrl: string | null;
  upcomingTours: number;
};

export type HotelCard = {
  id: string;
  slug: string;
  name: string;
  propertyType: string;
  city: string;
  district: string;
  rating: number;
  startingRate: number;
  imageUrl: string | null;
};

export type HotelDetail = {
  hotel: HotelCard;
  description: string;
  address: string;
  latitude: number | null;
  longitude: number | null;
  amenities: string[];
  checkInTime: string | null;
  checkOutTime: string | null;
  transportAvailable: boolean;
  photos: string[];
  rooms: { roomType: string; description: string; capacity: number; rate: number; imageUrl: string | null }[];
};

export type Ad = { id: string; slot: string; title: string; body: string; imageUrl: string | null; linkUrl: string | null; ctaLabel: string };

export type Stats = { toursToday: number; toursThisWeek: number; verifiedDrivers: number; hotels: number };

export type Home = { stats: Stats; tours: TourCard[]; hotels: HotelCard[]; destinations: Destination[]; ads: Ad[] };

export type Page<T> = { items: T[]; page: number; hasMore: boolean };

export type Sitemap = { destinations: Destination[]; hotels: HotelCard[]; generatedAt: string };

export type BookingResult = {
  reference: string;
  tour: string;
  departureAt: string;
  pickupPoint: string;
  mode: string;
  seats: number;
  total: number;
  advance: number;
  payDriverOnTheDay: number;
  driverName: string;
};

export const EMPTY_HOME: Home = {
  stats: { toursToday: 0, toursThisWeek: 0, verifiedDrivers: 0, hotels: 0 },
  tours: [],
  hotels: [],
  destinations: [],
  ads: [],
};

// ───────────────────────────── rent a car (public)
export type RentCar = {
  id: string;
  name: string;
  category: string;
  year: number;
  seats: number;
  photoUrl: string | null;
  withDriverDaily: number | null;
  selfDriveDaily: number | null;
  securityDeposit: number;
  minimumDays: number;
  kmPerDay: number | null;
  fuelIncluded: boolean;
  pickupPoint: string | null;
  ownerName: string;
  ownerRating: number;
  airConditioning: boolean;
  fourByFour: boolean;
};

// ───────────────────────────── owner area (same API as the app)
export type Kit = { fourByFour: boolean; firstAidKit: boolean; spareTyre: boolean; fireExtinguisher: boolean; snowChains: boolean; heating: boolean; airConditioning: boolean };
export type Review = { status: 'None' | 'Pending' | 'Approved' | 'Rejected' | 'Info' | string; note: string | null };
export type OwnerVehicle = {
  id: string; name: string; make: string; model: string; year: number; category: string; isFourByFour: boolean;
  registrationNumber: string; seats: number; photoUrl: string | null; status: string; reviewNote: string | null;
  wantsRent: boolean; wantsTour: boolean; availableForRent: boolean; availableForTour: boolean;
  withDriverDaily: number | null; selfDriveDaily: number | null; pickupPoint: string | null;
  readinessScore: number; readinessRequired: number; kit: Kit;
  docs: { front: boolean; registrationFront: boolean; registrationBack: boolean };
  pendingRentals: number; tehsilId?: string | null; tehsilName?: string | null; districtName?: string | null;
  rentReview?: Review; tourReview?: Review;
};
export type OwnerProfile = {
  hasProfile: boolean; drivesSelf: boolean; cnicFront: boolean; cnicBack: boolean; selfie: boolean;
  licenceFront: boolean; licenceBack: boolean; licenceNumber: string | null; licenceExpiry: string | null;
  agreementAccepted: boolean; agreementVersion: number;
};
export type FleetDriver = { id: string; name: string; phone: string; isOwner: boolean; status: string; licenceExpiry: string | null; licenceValid: boolean; expiresInDays: number | null; reviewNote: string | null };
export type ListingHome = { owner: OwnerProfile; vehicles: OwnerVehicle[]; drivers: FleetDriver[]; invites: number };
export type Area = { id: string; name: string; tehsils: { id: string; name: string }[] };
export type CalendarDay = { date: string; state: 'past' | 'booked' | 'pending' | 'blocked' | 'tour' | 'free' | string };
export type Departure = {
  date: string | null; packageId: string | null; from: string; destinationId: string; destination: string; time: string;
  durationDays: number; seatsSold: number; totalSeats: number; pricePerSeat: number; wholeVehiclePrice: number;
  pickupPoint: string; fleetDriverId: string | null; driverName: string | null;
};
export type DepartureMonth = { days: Departure[]; template: Departure | null; totalSeats: number; perSeatAllowed: boolean };
export type OwnerRental = {
  id: string; bookingReference: string; vehicleId: string; vehicleName: string; registrationNumber: string; photoUrl: string | null;
  startDate: string; endDate: string; rentalMode: string; days: number; dailyRate: number; subtotal: number; securityDeposit: number;
  advanceAmount: number; balanceDue: number; pickupPoint: string | null; status: string; counterpartName: string; counterpartPhone: string | null; createdAt: string;
};

// hotels (owner)
export type OwnerHotelCard = { id: string; name: string; propertyType: string; city: string; district: string; status: string; rejectionReason: string | null; isActive: boolean; photoUrl: string; photoCount: number; roomTypes: number; contactPhone: string };
export type HotelOwnerHome = { profile: { ownerName: string; businessName: string; cnicFront: boolean; cnicBack: boolean; verificationStatus: string; complete: boolean }; hotels: OwnerHotelCard[] };
export type OwnerRoom = { id: string; roomType: string; description: string; capacity: number; totalRooms: number; baseRate: number; imageUrl: string };
export type OwnerHotel = {
  id: string; name: string; propertyType: string; description: string; address: string; city: string; district: string;
  contactPhone: string; status: string; rejectionReason: string | null; isActive: boolean;
  photos: { id: string; url: string; isMain: boolean }[]; rooms: OwnerRoom[]; missing: string[];
};
export type SpecialRate = { id: string; roomId: string | null; roomType: string; startsOn: string; endsOn: string; rate: number | null; percent: number | null; roomsOpen: number | null };

// partner
export type PartnerMessage = { id: string; author: 'Applicant' | 'Team' | string; body: string; whatsAppSent: boolean; createdAt: string };
export type PartnerRequest = { id: string; reference: string; fullName: string; currentCity: string; targetCity: string; budget: string; status: string; createdAt: string; messages: PartnerMessage[] };

// ───────────────────────────── rent a car booking (customer, same API as the app)
export type RentQuote = {
  vehicleId: string; startDate: string; endDate: string; rentalMode: string; days: number; dailyRate: number; subtotal: number;
  securityDeposit: number; advanceAmount: number; balanceDue: number; kmIncluded: number | null; fuelIncluded: boolean;
  disclaimerVersion: number; requiresCustomerDocuments: boolean; customerDocumentsOnFile: boolean;
};
export type CustomerDocs = { cnicFront: boolean; cnicBack: boolean; drivingLicence: boolean; selfie: boolean; complete: boolean };
export type MyRental = {
  id: string; bookingReference: string; vehicleId: string; vehicleName: string; photoUrl: string | null; startDate: string; endDate: string;
  rentalMode: string; days: number; dailyRate: number; subtotal: number; securityDeposit: number; advanceAmount: number; balanceDue: number;
  kmPerDay: number | null; fuelIncluded: boolean; pickupPoint: string | null; status: string; counterpartName: string; counterpartPhone: string | null;
  createdAt: string; cancelledAt: string | null; cancelReason: string | null; advanceRefundableNow: boolean;
  ownerRespondBy?: string | null; driverName?: string | null; driverPhone?: string | null;
};
export type Waitlist = { id: string; vehicleId: string; vehicleName: string; startDate: string; endDate: string; rentalMode: string; status: string; acceptExpiresAt: string | null; createdAt: string };

// ───────────────────────────── weather (hourly readings stored by the API)
export type WxDay = { date: string; code: number; max: number; min: number; rain: number; snow: number; windMax: number };
export type WxPlace = { key: string; name: string; district: string; kind: 'Spot' | 'Tehsil' | string; now: { temperature: number; code: number; wind: number }; days: WxDay[]; advice: { level: 'ok' | 'warn' | 'bad' | string; text: string } };
export type RoadUpdate = { title: string; details: string; severity: string; route: string | null; source: string; startsAt: string };
export type Weather = { updatedAt: string | null; places: WxPlace[]; roadUpdates: RoadUpdate[] };
export const EMPTY_WEATHER: Weather = { updatedAt: null, places: [], roadUpdates: [] };
