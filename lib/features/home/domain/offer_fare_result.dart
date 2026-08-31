import '../../ride/domain/payment_method.dart';

/// Resultado que `OfferFareScreen` devuelve al hacer `pop`
/// (`FARE-PANEL-R1`, etapa 4). Deliberadamente chico, mismo criterio
/// que `SearchDestinationResult`: solo lo que Home necesita para
/// actualizar su oferta y método de pago antes de llamar a
/// `_requestRide()` — la pantalla de confirmación no conoce ni
/// `quoteId` ni ningún otro estado de Home.
class OfferFareResult {
  const OfferFareResult({required this.offerCents, required this.paymentMethod});

  final int offerCents;
  final PaymentMethod paymentMethod;
}
