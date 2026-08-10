import 'passenger_ride_offer.dart';

List<PassengerRideOffer> visibleRideOffers(
  Iterable<PassengerRideOffer> offers, {
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final seenOfferIds = <String>{};
  final visibleOffers = <PassengerRideOffer>[];

  for (final offer in offers) {
    final expiresAt = offer.expiresAt;

    if (expiresAt != null && !expiresAt.isAfter(referenceTime)) {
      continue;
    }

    if (!seenOfferIds.add(offer.offerId)) {
      continue;
    }

    visibleOffers.add(offer);
  }

  return visibleOffers;
}
