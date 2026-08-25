import '../../ride/domain/ride_history_item.dart';

/// Cuántos destinos sugeridos mostrar en Home. Constante nombrada (no
/// un número suelto) — InDriver muestra dos; ajustar acá si cambia.
const int suggestedDestinationsCount = 2;

/// Literales que Backend usa como fallback honesto cuando no pudo
/// resolver una dirección real (reverse geocoding falló, o el destino
/// vino de un tap en el mapa sin pasar por reverse geocoding) — ver
/// `FALLBACK_DESTINATION_ADDRESS`/`MANUAL_DESTINATION_PLACEHOLDER` en
/// `fares.service.ts`/`google-geocoding.service.ts` del Backend. No
/// son direcciones reales: sugerirlas como "destino frecuente" no
/// tiene sentido.
const List<String> nonSuggestableDestinationAddresses = [
  'Destino seleccionado',
  'Destino seleccionado en el mapa',
];

/// SUGGESTED-DESTINATIONS-R1: de los viajes completados más recientes
/// del pasajero, calcula hasta [suggestedDestinationsCount] destinos
/// sugeridos — el criterio es **frecuencia** dentro de la ventana que
/// trae [history] (no recencia pura: un lugar al que se vuelve
/// seguido debe ganarle a uno visitado una sola vez ayer), con empate
/// resuelto por el más reciente de los dos.
///
/// Función pura, sin `BuildContext` — testeable directo. No asume que
/// [history] venga ordenado por fecha: compara `requestedAt`
/// explícitamente en vez de confiar en el orden de entrada.
///
/// Filtra:
/// - Ítems sin coordenadas de destino (no se pueden usar como
///   sugerencia tocable sin re-resolverlas — ver `ride_repository.dart`
///   y la entrada `SUGGESTED-DESTINATIONS-R1` de `decisiones.md`).
/// - Direcciones vacías o iguales a [nonSuggestableDestinationAddresses].
///
/// Deduplica por dirección normalizada (`trim` + minúsculas). **Limitación
/// conocida, sin solución sin cambiar Backend**: dos visitas al mismo
/// lugar con un `destinationAddress` formateado de forma distinta
/// (p. ej. con/sin ciudad) se tratan como destinos diferentes — no hay
/// coordenadas de origen suficientemente estables ni un identificador
/// de lugar (`placeId`) persistido en el historial para deduplicar de
/// forma más robusta.
List<RideHistoryItem> resolveSuggestedDestinations(
  List<RideHistoryItem> history,
) {
  final counts = <String, int>{};
  final mostRecentByKey = <String, RideHistoryItem>{};

  for (final item in history) {
    if (item.destinationLatitude == null ||
        item.destinationLongitude == null) {
      continue;
    }

    final address = item.destinationAddress.trim();

    if (address.isEmpty || nonSuggestableDestinationAddresses.contains(address)) {
      continue;
    }

    final key = address.toLowerCase();

    counts[key] = (counts[key] ?? 0) + 1;

    final existing = mostRecentByKey[key];

    if (existing == null || item.requestedAt.isAfter(existing.requestedAt)) {
      mostRecentByKey[key] = item;
    }
  }

  final keys = mostRecentByKey.keys.toList()
    ..sort((a, b) {
      final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);

      if (byCount != 0) {
        return byCount;
      }

      return mostRecentByKey[b]!.requestedAt.compareTo(
        mostRecentByKey[a]!.requestedAt,
      );
    });

  return keys
      .take(suggestedDestinationsCount)
      .map((key) => mostRecentByKey[key]!)
      .toList();
}
