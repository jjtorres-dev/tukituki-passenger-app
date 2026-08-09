class PassengerRideOffer {
  const PassengerRideOffer({
    required this.offerId,
    required this.rideId,
    required this.driverProfileId,
    required this.driverFirstName,
    required this.driverLastNameInitial,
    required this.photoUrl,
    required this.ratingAverage,
    required this.ratingCount,
    required this.distanceToOriginMeters,
    required this.passengerOfferFare,
    required this.proposedFare,
    required this.isCounterOffer,
    required this.currency,
    required this.proposedAt,
    required this.expiresAt,
  });

  final String offerId;
  final String rideId;

  final String driverProfileId;
  final String driverFirstName;
  final String driverLastNameInitial;
  final String? photoUrl;

  final double ratingAverage;
  final int ratingCount;

  final num distanceToOriginMeters;

  final String passengerOfferFare;
  final String proposedFare;
  final bool isCounterOffer;
  final String currency;

  final DateTime? proposedAt;
  final DateTime? expiresAt;

  String get driverDisplayName {
    final initial = driverLastNameInitial.trim();

    if (initial.isEmpty) {
      return driverFirstName;
    }

    final normalizedInitial = initial.endsWith('.') ? initial : '$initial.';

    return '$driverFirstName $normalizedInitial';
  }

  factory PassengerRideOffer.fromJson(Map<String, dynamic> json) {
    final driverRaw = json['driver'];

    final driver = driverRaw is Map
        ? Map<String, dynamic>.from(driverRaw)
        : const <String, dynamic>{};

    final passengerFare = json['passengerOfferFare']?.toString() ?? '0.00';

    final proposedFare = json['proposedFare']?.toString() ?? passengerFare;

    double toDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    int toInt(dynamic value) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    num toNum(dynamic value) {
      if (value is num) {
        return value;
      }

      return num.tryParse(value?.toString() ?? '') ?? 0;
    }

    final passengerValue = double.tryParse(passengerFare);

    final proposedValue = double.tryParse(proposedFare);

    return PassengerRideOffer(
      offerId: json['offerId']?.toString() ?? json['id']?.toString() ?? '',
      rideId: json['rideId']?.toString() ?? '',
      driverProfileId:
          driver['profileId']?.toString() ??
          json['driverProfileId']?.toString() ??
          '',
      driverFirstName:
          driver['firstName']?.toString() ??
          json['firstName']?.toString() ??
          json['driverFirstName']?.toString() ??
          'Conductor',
      driverLastNameInitial:
          driver['lastNameInitial']?.toString() ??
          json['lastNameInitial']?.toString() ??
          json['driverLastNameInitial']?.toString() ??
          '',
      photoUrl:
          driver['photoUrl']?.toString() ??
          json['photoUrl']?.toString() ??
          json['driverPhotoUrl']?.toString(),
      ratingAverage: toDouble(
        driver['ratingAverage'] ??
            json['ratingAverage'] ??
            json['driverRatingAverage'],
      ),
      ratingCount: toInt(
        driver['ratingCount'] ??
            json['ratingCount'] ??
            json['driverRatingCount'],
      ),
      distanceToOriginMeters: toNum(json['distanceToOriginMeters']),
      passengerOfferFare: passengerFare,
      proposedFare: proposedFare,
      isCounterOffer:
          json['isCounterOffer'] as bool? ??
          (passengerValue != null &&
              proposedValue != null &&
              proposedValue > passengerValue),
      currency: json['currency']?.toString() ?? 'PEN',
      proposedAt: DateTime.tryParse(json['proposedAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}
