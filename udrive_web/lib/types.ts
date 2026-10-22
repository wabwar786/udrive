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
