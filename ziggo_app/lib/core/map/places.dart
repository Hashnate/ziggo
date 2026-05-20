import 'package:latlong2/latlong.dart';

/// A hand-curated list of well-known Sri Lankan landmarks so the location
/// picker can autocomplete without any external Places API.
class Place {
  final String name;
  final String area;
  final LatLng location;
  const Place(this.name, this.area, this.location);

  String get fullAddress => '$name, $area';
}

const List<Place> kColomboPlaces = [
  Place('Galle Face Green', 'Colombo 3', LatLng(6.9271, 79.8420)),
  Place('Lotus Tower', 'Colombo 1', LatLng(6.9305, 79.8540)),
  Place('Independence Square', 'Colombo 7', LatLng(6.9043, 79.8682)),
  Place('Viharamahadevi Park', 'Colombo 7', LatLng(6.9165, 79.8625)),
  Place('Bambalapitiya Junction', 'Colombo 4', LatLng(6.8941, 79.8536)),
  Place('Dehiwala Zoo', 'Dehiwala', LatLng(6.8567, 79.8744)),
  Place('Mount Lavinia Beach', 'Mount Lavinia', LatLng(6.8404, 79.8623)),
  Place('Pettah Market', 'Colombo 11', LatLng(6.9388, 79.8542)),
  Place('Colombo Fort Railway', 'Colombo 1', LatLng(6.9335, 79.8503)),
  Place('Beira Lake', 'Colombo 2', LatLng(6.9213, 79.8556)),
  Place('Nelum Pokuna Theatre', 'Colombo 7', LatLng(6.9046, 79.8636)),
  Place('Kandy City Centre', 'Kandy', LatLng(7.2906, 80.6337)),
  Place('Sigiriya Rock', 'Dambulla', LatLng(7.9570, 80.7603)),
  Place('Galle Fort', 'Galle', LatLng(6.0269, 80.2167)),
  Place('Negombo Beach', 'Negombo', LatLng(7.2083, 79.8358)),
  Place('Maharagama Junction', 'Maharagama', LatLng(6.8485, 79.9265)),
  Place('Nugegoda Junction', 'Nugegoda', LatLng(6.8716, 79.8898)),
  Place('Rajagiriya', 'Rajagiriya', LatLng(6.9089, 79.8946)),
  Place('Wellawatta', 'Colombo 6', LatLng(6.8769, 79.8589)),
  Place('Bandaranaike Airport', 'Katunayake', LatLng(7.1808, 79.8841)),
];

List<Place> searchPlaces(String q) {
  final query = q.trim().toLowerCase();
  if (query.isEmpty) return kColomboPlaces.take(8).toList();
  return kColomboPlaces
      .where((p) =>
          p.name.toLowerCase().contains(query) || p.area.toLowerCase().contains(query))
      .take(12)
      .toList();
}
