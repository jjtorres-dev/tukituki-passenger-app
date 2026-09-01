/// Modelo de dominio mínimo del perfil del pasajero.
///
/// Solo los campos que consume la app hoy (cabecera del menú de perfil
/// y pantalla "Editar perfil"): `firstName`, `lastName` y la
/// calificación (`ratingAverage`/`ratingCount`). El backend
/// (`PassengerProfileResponseDto`) expone además `id`, `userId`,
/// `photoUrl`, `emergencyContact*` y timestamps — se omiten a
/// propósito: si un checkpoint futuro los necesita, se agregan acá.
///
/// Parseo defensivo por convención del repo (`assigned_driver.dart`,
/// `passenger_ride_offer.dart`): nunca asume tipos exactos del backend
/// ni lanza si falta un campo; los desconocidos se ignoran.
class PassengerProfile {
  const PassengerProfile({
    required this.firstName,
    required this.lastName,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final String firstName;
  final String lastName;

  /// Promedio de calificación como número. El backend lo manda como
  /// string (`"4.85"`, `"0.00"`); acá ya viene parseado con
  /// `double.tryParse(...) ?? 0.0` — mismo criterio de tolerancia que
  /// `assigned_driver.dart`.
  final double ratingAverage;

  final int ratingCount;

  /// `true` cuando el pasajero ya tiene al menos una calificación
  /// recibida. Es el switch primario de la cabecera del menú: con
  /// `false` se muestra la etiqueta "Nuevo" en vez de estrellas.
  bool get hasRating => ratingCount > 0;

  factory PassengerProfile.fromJson(Map<String, dynamic> json) {
    return PassengerProfile(
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      ratingAverage: _toDouble(json['ratingAverage']),
      ratingCount: _toInt(json['ratingCount']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
