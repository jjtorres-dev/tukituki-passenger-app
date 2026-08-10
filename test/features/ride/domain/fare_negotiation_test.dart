import 'package:flutter_test/flutter_test.dart';
import 'package:passenger/features/ride/domain/fare_amount.dart';
import 'package:passenger/features/ride/domain/passenger_ride_offer.dart';
import 'package:passenger/features/ride/domain/ride_offer_filter.dart';

void main() {
  group('PassengerRideOffer isCounterOffer', () {
    for (final testCase in const [
      ('7.00', false),
      ('6.00', true),
      ('8.00', true),
    ]) {
      test('usa isCounterOffer explícito para 7/${testCase.$1}', () {
        final offer = _offerFromJson(
          proposedFare: testCase.$1,
          isCounterOffer: testCase.$2,
        );

        expect(offer.isCounterOffer, testCase.$2);
      });

      test('calcula fallback bidireccional para 7/${testCase.$1}', () {
        final offer = _offerFromJson(proposedFare: testCase.$1);

        expect(offer.isCounterOffer, testCase.$2);
      });
    }

    test('la representación monetaria compara centavos', () {
      final offer = _offerFromJson(proposedFare: '7.000');

      expect(offer.isCounterOffer, isFalse);
    });

    test('un monto inválido usa un fallback seguro', () {
      final offer = _offerFromJson(proposedFare: 'NaN');

      expect(offer.isCounterOffer, isFalse);
      expect(offer.hasDifferentProposedFare, isFalse);
    });

    test('la UI puede corregir un boolean obsoleto del backend', () {
      final offer = _offerFromJson(proposedFare: '6.00', isCounterOffer: false);

      expect(offer.isCounterOffer, isFalse);
      expect(offer.hasDifferentProposedFare, isTrue);
    });
  });

  group('normalizePassengerOfferFare', () {
    test('acepta y normaliza montos válidos', () {
      expect(normalizePassengerOfferFare('7'), '7.00');
      expect(normalizePassengerOfferFare('6.50'), '6.50');
      expect(normalizePassengerOfferFare('8,5'), '8.50');
    });

    test('rechaza montos inválidos o fuera de rango', () {
      for (final value in const [
        '',
        '0',
        '-1',
        'NaN',
        'Infinity',
        '-Infinity',
        '10000',
        '7.123',
      ]) {
        expect(
          normalizePassengerOfferFare(value),
          isNull,
          reason: '$value debe ser inválido',
        );
      }
    });
  });

  group('visibleRideOffers', () {
    test('deduplica por offerId y conserva el orden del backend', () {
      final offers = visibleRideOffers([
        _offer('offer-a', '7.00'),
        _offer('offer-b', '6.00'),
        _offer('offer-a', '8.00'),
        _offer('offer-c', '8.00'),
      ]);

      expect(offers.map((offer) => offer.offerId), [
        'offer-a',
        'offer-b',
        'offer-c',
      ]);
      expect(offers.map((offer) => offer.proposedFare), [
        '7.00',
        '6.00',
        '8.00',
      ]);
    });

    test('elimina propuestas vencidas', () {
      final now = DateTime.utc(2026, 8, 9, 12);
      final offers = visibleRideOffers([
        _offer('expired', '6.00', expiresAt: now),
        _offer(
          'active',
          '7.00',
          expiresAt: now.add(const Duration(seconds: 1)),
        ),
        _offer('without-expiration', '8.00'),
      ], now: now);

      expect(offers.map((offer) => offer.offerId), [
        'active',
        'without-expiration',
      ]);
    });
  });
}

PassengerRideOffer _offerFromJson({
  required String proposedFare,
  bool? isCounterOffer,
}) {
  return PassengerRideOffer.fromJson({
    'offerId': 'offer-$proposedFare',
    'rideId': 'ride-1',
    'driver': const {
      'profileId': 'driver-1',
      'firstName': 'Carlos',
      'lastNameInitial': 'P',
    },
    'passengerOfferFare': '7.00',
    'proposedFare': proposedFare,
    'isCounterOffer': ?isCounterOffer,
    'currency': 'PEN',
  });
}

PassengerRideOffer _offer(
  String offerId,
  String proposedFare, {
  DateTime? expiresAt,
}) {
  return PassengerRideOffer(
    offerId: offerId,
    rideId: 'ride-1',
    driverProfileId: 'driver-$offerId',
    driverFirstName: offerId,
    driverLastNameInitial: '',
    photoUrl: null,
    ratingAverage: 5,
    ratingCount: 1,
    distanceToOriginMeters: 100,
    passengerOfferFare: '7.00',
    proposedFare: proposedFare,
    isCounterOffer: proposedFare != '7.00',
    currency: 'PEN',
    proposedAt: null,
    expiresAt: expiresAt,
  );
}
