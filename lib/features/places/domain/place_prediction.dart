class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.fullText,
    required this.distanceMeters,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String fullText;
  final int? distanceMeters;

  factory PlacePrediction.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawDistance = json['distanceMeters'];

    return PlacePrediction(
      placeId:
          json['placeId']?.toString() ?? '',
      primaryText:
          json['primaryText']?.toString() ?? '',
      secondaryText:
          json['secondaryText']?.toString() ?? '',
      fullText:
          json['fullText']?.toString() ?? '',
      distanceMeters:
          rawDistance is num
              ? rawDistance.round()
              : null,
    );
  }
}