/// Modelo de dominio del perfil del pasajero.
///
/// Campos que consume la app hoy (cabecera del menú de perfil y
/// pantalla "Editar perfil"): `firstName`, `lastName`, `email`
/// (opcional, puede ser `null`), `phoneE164` (solo lectura en la app —
/// se muestra pero no se edita) y la calificación
/// (`ratingAverage`/`ratingCount`). El backend
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
    required this.email,
    required this.phoneE164,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final String firstName;
  final String lastName;

  /// Correo electrónico opcional. `null` cuando el pasajero todavía no
  /// cargó uno (no se colapsa a cadena vacía: "sin correo" y "correo
  /// vacío" tienen que poder distinguirse al comparar cambios en
  /// "Editar perfil").
  final String? email;

  /// Número de teléfono en formato E.164 (`+51987654321`). Vive en
  /// `User` del lado del backend, no en el perfil, pero llega en la
  /// misma respuesta de `passengers/me`. Solo lectura en la app.
  final String phoneE164;

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
      email: _toNullableString(json['email']),
      phoneE164: json['phoneE164']?.toString() ?? '',
      ratingAverage: _toDouble(json['ratingAverage']),
      ratingCount: _toInt(json['ratingCount']),
    );
  }

  /// Devuelve el valor solo si ya es un `String`; ausente, `null` o de
  /// otro tipo → `null`. No convierte con `toString()` a propósito: un
  /// correo no-string es un dato corrupto, no algo que valga la pena
  /// mostrar.
  static String? _toNullableString(dynamic value) {
    return value is String ? value : null;
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
