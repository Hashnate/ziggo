import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'places.dart';

/// Rules shared by the screens where a pin in the middle of the map picks a place.
///
/// The address is looked up only when the map has stopped at least
/// [kPinSameSpotMeters] away from the place the pin last showed, so the app's own
/// camera moves (to the GPS position, a searched place, the other end of the
/// trip) and small nudges cost nothing. "Fetching address..." never stays behind:
/// when no address can be found the pin shows [pinnedPlace].
const double kPinSameSpotMeters = 15;

/// True when [center] is still on [known] (within [kPinSameSpotMeters]).
bool pinStillOn(Place? known, LatLng center) =>
    known != null &&
    Geolocator.distanceBetween(
          known.location.latitude,
          known.location.longitude,
          center.latitude,
          center.longitude,
        ) <
        kPinSameSpotMeters;

/// True when the pin is no longer where a lookup for [asked] started (it moved on,
/// and a newer lookup will answer).
bool pinMovedOn(LatLng? now, LatLng asked) =>
    now != null &&
    Geolocator.distanceBetween(now.latitude, now.longitude, asked.latitude, asked.longitude) > 1;

/// [known]'s name and address at the exact pin point.
Place placeAt(Place known, LatLng center) => Place(known.name, known.area, center);

/// What the pin shows when no address could be found for it.
Place pinnedPlace(LatLng center) => Place(
      'Pinned location',
      '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}',
      center,
    );
