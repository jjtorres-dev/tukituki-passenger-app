/// Método de pago referencial del viaje (`FARE-PANEL-R1`).
///
/// El backend acepta `CASH`/`YAPE`/`PLIN`/`CARD` en
/// `CreatePassengerRideDto.paymentMethod`, pero la app **solo** ofrece
/// los tres primeros: no hay pasarela, el pago es directo entre el
/// pasajero y el conductor, y el método es puramente informativo
/// (decisión de producto, ver `estado-actual.md` §5). `CARD` no se
/// muestra y, si apareciera guardado localmente, se resuelve como
/// [cash].
enum PaymentMethod {
  cash,
  yape,
  plin;

  /// Valor exacto que espera el backend en `paymentMethod`.
  String get wireValue => switch (this) {
    PaymentMethod.cash => 'CASH',
    PaymentMethod.yape => 'YAPE',
    PaymentMethod.plin => 'PLIN',
  };

  /// Etiqueta visible para el pasajero.
  String get label => switch (this) {
    PaymentMethod.cash => 'Efectivo',
    PaymentMethod.yape => 'Yape',
    PaymentMethod.plin => 'Plin',
  };

  /// Parseo tolerante de un valor persistido (o recibido). Cualquier
  /// cosa que no sea exactamente `YAPE`/`PLIN` —incluido `CARD`, `null`,
  /// texto vacío o basura— cae en [cash], el default de producto.
  static PaymentMethod parse(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'YAPE':
        return PaymentMethod.yape;
      case 'PLIN':
        return PaymentMethod.plin;
      default:
        return PaymentMethod.cash;
    }
  }
}
