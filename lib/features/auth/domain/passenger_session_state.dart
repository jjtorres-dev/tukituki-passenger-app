/// Estado real de la sesión del Passenger tras resolver contra Backend,
/// derivado siempre de datos frescos (`GET passengers/me` + viaje
/// activo) — nunca de una bandera local de "en qué paso quedé". Se usa
/// desde el único punto real de entrada a la app (`SplashScreen`),
/// alcanzado tanto por un registro nuevo como por un login o una
/// reapertura de la app.
enum PassengerSessionKind {
  /// El Passenger todavía no tiene `PassengerProfile` en Backend (no
  /// completó "Sobre ti") y no tiene un viaje activo que deba
  /// priorizarse — debe completar su identidad antes de continuar.
  identityRequired,

  /// Sesión lista para operar: con perfil completo, o con un viaje
  /// activo que no debe interrumpirse por el formulario de perfil.
  ready,
}

class PassengerSessionState {
  const PassengerSessionState._(this.kind, this.activeRideId);

  const PassengerSessionState.identityRequired()
    : this._(PassengerSessionKind.identityRequired, null);

  const PassengerSessionState.ready({String? activeRideId})
    : this._(PassengerSessionKind.ready, activeRideId);

  final PassengerSessionKind kind;

  /// Solo relevante cuando [kind] es [PassengerSessionKind.ready].
  final String? activeRideId;
}

/// Un viaje activo real siempre tiene prioridad sobre el gate de
/// identidad: un Passenger que ya está en medio de un viaje (por
/// ejemplo, una cuenta existente desde antes de este gate) no debe
/// quedar bloqueado por un formulario de perfil para poder verlo.
PassengerSessionState resolvePassengerSessionState({
  required bool hasProfile,
  String? activeRideId,
}) {
  if (activeRideId != null) {
    return PassengerSessionState.ready(activeRideId: activeRideId);
  }

  if (!hasProfile) {
    return const PassengerSessionState.identityRequired();
  }

  return const PassengerSessionState.ready();
}

/// Traduce el estado resuelto a la ruta real de `go_router`. Vive junto
/// al resolver (no dentro del widget) para poder testear el cálculo de
/// ruta sin `BuildContext`.
String routeForPassengerSessionState(PassengerSessionState state) {
  switch (state.kind) {
    case PassengerSessionKind.identityRequired:
      return '/complete-profile';
    case PassengerSessionKind.ready:
      final rideId = state.activeRideId;

      return rideId != null ? '/ride/$rideId' : '/home';
  }
}
