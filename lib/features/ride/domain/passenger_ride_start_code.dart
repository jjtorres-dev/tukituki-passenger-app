class PassengerRideStartCode {
  const PassengerRideStartCode({
    required this.rideId,
    required this.code,
    required this.status,
    required this.expiresAt,
    required this.remainingSeconds,
    required this.remainingAttempts,
  });

  final String rideId;
  final String code;
  final String status;
  final DateTime expiresAt;
  final num remainingSeconds;
  final num remainingAttempts;

  factory PassengerRideStartCode.fromJson(
    Map<String, dynamic> json,
  ) {
    return PassengerRideStartCode(
      rideId: json['rideId'] as String,
      code: json['code'] as String,
      status: json['status'] as String,
      expiresAt: DateTime.parse(
        json['expiresAt'] as String,
      ),
      remainingSeconds:
          json['remainingSeconds'] as num,
      remainingAttempts:
          json['remainingAttempts'] as num,
    );
  }
}