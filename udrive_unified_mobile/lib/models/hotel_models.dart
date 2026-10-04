class HotelSummary {
  const HotelSummary({required this.id,required this.name,required this.address,required this.city,required this.latitude,required this.longitude,required this.rating,required this.mainImageUrl,required this.startingRate,required this.availableRooms,required this.transportAvailable,this.approvalStatus,this.rejectionReason,this.contactPhone=''});
  final String id,name,address,city,mainImageUrl; final double latitude,longitude,rating,startingRate; final int availableRooms; final bool transportAvailable; final String? approvalStatus,rejectionReason; final String contactPhone;
  factory HotelSummary.fromJson(Map<String,dynamic> j)=>HotelSummary(id:'${j['id']}',name:'${j['name']??''}',address:'${j['address']??''}',city:'${j['city']??''}',latitude:(j['latitude'] as num?)?.toDouble()??0,longitude:(j['longitude'] as num?)?.toDouble()??0,rating:(j['rating'] as num?)?.toDouble()??0,mainImageUrl:'${j['mainImageUrl']??''}',startingRate:(j['startingRate'] as num?)?.toDouble()??0,availableRooms:(j['availableRooms'] as num?)?.toInt()??0,transportAvailable:j['transportAvailable']==true,approvalStatus:j['approvalStatus']?.toString(),rejectionReason:j['rejectionReason']?.toString(),contactPhone:'${j['contactPhone']??''}');
}
class HotelRoom {const HotelRoom({required this.id,required this.roomType,required this.capacity,required this.availableRooms,required this.rate,required this.imageUrl,required this.amenities});final String id,roomType,imageUrl;final int capacity,availableRooms;final double rate;final List<String> amenities;factory HotelRoom.fromJson(Map<String,dynamic>j)=>HotelRoom(id:'${j['id']}',roomType:'${j['roomType']??''}',capacity:(j['capacity']as num?)?.toInt()??1,availableRooms:(j['availableRooms']as num?)?.toInt()??0,rate:(j['rate']as num?)?.toDouble()??0,imageUrl:'${j['imageUrl']??''}',amenities:(j['amenities']as List? ?? const[]).map((e)=>'$e').toList());}
class HotelDetails {const HotelDetails({required this.hotel,required this.rooms,required this.description,required this.amenities});final HotelSummary hotel;final List<HotelRoom> rooms;final String description;final List<String> amenities;}

/// How the guest is getting to the hotel. The strings are the server's.
enum HotelArrivalMode {
  ownCar('OwnCar'),
  udriveRide('UDriveRide'),
  hotelTransport('HotelTransport');

  const HotelArrivalMode(this.wire);
  final String wire;

  static HotelArrivalMode fromWire(String? value) => HotelArrivalMode.values
      .firstWhere((mode) => mode.wire == value, orElse: () => ownCar);
}

/// One of the customer's own hotel bookings — "My stays", and the booking
/// confirmation screen.
class HotelStay {
  const HotelStay({
    required this.id,
    required this.reference,
    required this.hotelId,
    required this.hotelName,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.contactPhone,
    required this.imageUrl,
    required this.roomType,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.rooms,
    required this.amount,
    required this.status,
    required this.arrivalTime,
    required this.arrivalMode,
    required this.carNumber,
    required this.ownerNotified,
  });

  final String id;
  final String reference;
  final String hotelId;
  final String hotelName;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final String contactPhone;
  final String imageUrl;
  final String roomType;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int rooms;
  final double amount;
  final String status;

  /// "14:00", or null when the guest did not say.
  final String? arrivalTime;
  final HotelArrivalMode arrivalMode;
  final String? carNumber;

  /// Whether the hotel was sent the booking on WhatsApp.
  final bool ownerNotified;

  int get nights => checkOut.difference(checkIn).inDays;

  bool get hasLocation => latitude != 0 || longitude != 0;

  factory HotelStay.fromJson(Map<String, dynamic> j) => HotelStay(
        id: '${j['id'] ?? ''}',
        reference: '${j['reference'] ?? ''}',
        hotelId: '${j['hotelId'] ?? ''}',
        hotelName: '${j['hotelName'] ?? ''}',
        address: '${j['address'] ?? ''}',
        city: '${j['city'] ?? ''}',
        latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
        contactPhone: '${j['contactPhone'] ?? ''}',
        imageUrl: '${j['mainImageUrl'] ?? ''}',
        roomType: '${j['roomType'] ?? ''}',
        checkIn: DateTime.parse('${j['checkIn']}'),
        checkOut: DateTime.parse('${j['checkOut']}'),
        guests: (j['guests'] as num?)?.toInt() ?? 1,
        rooms: (j['rooms'] as num?)?.toInt() ?? 1,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: '${j['status'] ?? ''}',
        arrivalTime: j['arrivalTime']?.toString(),
        arrivalMode: HotelArrivalMode.fromWire(j['arrivalMode']?.toString()),
        carNumber: j['carNumber']?.toString(),
        ownerNotified: j['ownerNotified'] == true,
      );
}
