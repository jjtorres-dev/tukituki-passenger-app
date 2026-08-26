import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Resultado que `SearchDestinationScreen` devuelve al hacer `pop`
/// (`HOME-FLOW-R1`, etapa 2). Deliberadamente chico: solo lo que Home
/// necesita para fijar el destino con el mismo camino que ya usa hoy
/// para una selección por autocompletado — la búsqueda no expone
/// `PlacePrediction`/`PlaceDetails` fuera de sí misma, para no acoplar
/// a Home con tipos que son responsabilidad de la pantalla de
/// búsqueda.
class SearchDestinationResult {
  const SearchDestinationResult({
    required this.destination,
    required this.name,
    required this.address,
  });

  final LatLng destination;
  final String name;
  final String? address;
}
