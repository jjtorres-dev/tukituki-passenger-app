class PlaceDetails {
  const PlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  factory PlaceDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return PlaceDetails(
      placeId:
          json['placeId']?.toString() ?? '',
      formattedAddress:
          json['formattedAddress']?.toString() ?? '',
      latitude:
          (json['latitude'] as num).toDouble(),
      longitude:
          (json['longitude'] as num).toDouble(),
    );
  }
}