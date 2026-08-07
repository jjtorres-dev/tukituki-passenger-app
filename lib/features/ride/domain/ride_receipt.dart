class RideReceipt {
  const RideReceipt({
    required this.rideId,
    required this.status,
    required this.originAddress,
    required this.destinationAddress,
    required this.startedAt,
    required this.completedAt,
    required this.actualDistanceMeters,
    required this.actualDurationSeconds,
    required this.estimatedFare,
    required this.fare,
    this.completionNotes,
    this.payment,
  });

  final String rideId;
  final String status;

  final String originAddress;
  final String destinationAddress;

  final DateTime startedAt;
  final DateTime completedAt;

  final num actualDistanceMeters;
  final num actualDurationSeconds;

  final String estimatedFare;

  final String? completionNotes;

  final RideReceiptPayment? payment;
  final RideReceiptFare fare;

  factory RideReceipt.fromJson(
    Map<String, dynamic> json,
  ) {
    final paymentJson =
        json['payment'] as Map<String, dynamic>?;

    final fareJson =
        json['fare'] as Map<String, dynamic>? ?? {};

    return RideReceipt(
      rideId:
          json['rideId']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'UNKNOWN',
      originAddress:
          json['originAddress']?.toString() ?? 'Origen',
      destinationAddress:
          json['destinationAddress']?.toString() ??
              'Destino',
      startedAt: DateTime.parse(
        json['startedAt'] as String,
      ),
      completedAt: DateTime.parse(
        json['completedAt'] as String,
      ),
      actualDistanceMeters:
          json['actualDistanceMeters'] as num? ?? 0,
      actualDurationSeconds:
          json['actualDurationSeconds'] as num? ?? 0,
      estimatedFare:
          json['estimatedFare']?.toString() ?? '0.00',
      completionNotes:
          json['completionNotes']?.toString(),
      payment: paymentJson == null
          ? null
          : RideReceiptPayment.fromJson(
              paymentJson,
            ),
      fare: RideReceiptFare.fromJson(
        fareJson,
      ),
    );
  }
}

class RideReceiptPayment {
  const RideReceiptPayment({
    required this.method,
    required this.status,
    required this.amountDue,
    required this.grossAmount,
    required this.discountAmount,
    this.cashReceived,
    this.changeGiven,
    this.confirmedAt,
  });

  final String method;
  final String status;

  final String amountDue;
  final String grossAmount;
  final String discountAmount;

  final String? cashReceived;
  final String? changeGiven;

  final DateTime? confirmedAt;

  factory RideReceiptPayment.fromJson(
    Map<String, dynamic> json,
  ) {
    final confirmedAtValue =
        json['confirmedAt']?.toString();

    return RideReceiptPayment(
      method:
          json['method']?.toString() ?? 'CASH',
      status:
          json['status']?.toString() ?? 'PENDING',
      amountDue:
          json['amountDue']?.toString() ?? '0.00',
      grossAmount:
          json['grossAmount']?.toString() ?? '0.00',
      discountAmount:
          json['discountAmount']?.toString() ?? '0.00',
      cashReceived:
          json['cashReceived']?.toString(),
      changeGiven:
          json['changeGiven']?.toString(),
      confirmedAt: confirmedAtValue == null
          ? null
          : DateTime.tryParse(
              confirmedAtValue,
            ),
    );
  }
}

class RideReceiptFare {
  const RideReceiptFare({
    required this.baseFare,
    required this.distanceAmount,
    required this.timeAmount,
    required this.bookingFee,
    required this.subtotal,
    required this.adjustmentMultiplier,
    required this.calculatedFinalFare,
    required this.finalFare,
    required this.fareCapAmount,
    required this.fareWasCapped,
    required this.currency,
  });

  final String baseFare;
  final String distanceAmount;
  final String timeAmount;
  final String bookingFee;
  final String subtotal;

  final String adjustmentMultiplier;

  final String calculatedFinalFare;
  final String finalFare;
  final String fareCapAmount;

  final bool fareWasCapped;

  final String currency;

  factory RideReceiptFare.fromJson(
    Map<String, dynamic> json,
  ) {
    return RideReceiptFare(
      baseFare:
          json['baseFare']?.toString() ?? '0.00',
      distanceAmount:
          json['distanceAmount']?.toString() ??
              '0.00',
      timeAmount:
          json['timeAmount']?.toString() ?? '0.00',
      bookingFee:
          json['bookingFee']?.toString() ?? '0.00',
      subtotal:
          json['subtotal']?.toString() ?? '0.00',
      adjustmentMultiplier:
          json['adjustmentMultiplier']?.toString() ??
              '1.000',
      calculatedFinalFare:
          json['calculatedFinalFare']?.toString() ??
              '0.00',
      finalFare:
          json['finalFare']?.toString() ?? '0.00',
      fareCapAmount:
          json['fareCapAmount']?.toString() ?? '0.00',
      fareWasCapped:
          json['fareWasCapped'] as bool? ?? false,
      currency:
          json['currency']?.toString() ?? 'PEN',
    );
  }
}