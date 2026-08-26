import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/passenger_colors.dart';
import '../../core/theme/passenger_spacing.dart';
import '../../core/theme/passenger_typography.dart';
import '../../core/widgets/tuki_search_bar.dart';
import '../places/data/places_repository.dart';
import '../places/domain/place_prediction.dart';
import 'domain/search_destination_result.dart';

/// Pantalla completa de búsqueda de destino (`HOME-FLOW-R1`, etapa 2).
///
/// Construida y probada en aislamiento — todavía **no está conectada**
/// a `HomeScreen`. El origen es de solo lectura (decisión explícita de
/// JuanJo para este checkpoint: sin autocompletado ni edición de
/// origen acá, es un dato que ya trae Home). El destino se elige por
/// autocompletado, con el mismo repositorio (`placesRepositoryProvider`)
/// y el mismo flujo de dos pasos (`autocomplete` → `getDetails`) que
/// usaba el campo inline de `home_screen.dart` antes de este
/// checkpoint — la lógica se movió, no se reescribió.
///
/// Se navega hacia acá con `Navigator.push` y se vuelve con
/// `Navigator.pop(context, SearchDestinationResult(...))` al elegir un
/// destino, o `Navigator.pop(context)` (sin resultado) al cancelar —
/// `HomeScreen` decide qué hacer con eso, esta pantalla no sabe nada
/// de Home.
class SearchDestinationScreen extends ConsumerStatefulWidget {
  const SearchDestinationScreen({
    super.key,
    required this.originAddress,
    required this.originCoordinates,
  });

  /// Texto ya resuelto por Home — esta pantalla no lo recalcula ni lo
  /// vuelve a pedir al backend.
  final String originAddress;

  /// Coordenadas reales del origen, necesarias para sesgar
  /// `places/autocomplete` hacia resultados cercanos — mismo criterio
  /// que ya usaba `home_screen.dart`.
  final LatLng originCoordinates;

  @override
  ConsumerState<SearchDestinationScreen> createState() =>
      _SearchDestinationScreenState();
}

class _SearchDestinationScreenState
    extends ConsumerState<SearchDestinationScreen> {
  final TextEditingController _destinationController =
      TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();

  Timer? _searchDebounce;
  String? _placesSessionToken;

  List<PlacePrediction> _predictions = const [];
  String? _searchMessage;
  bool _searching = false;
  bool _loadingDetails = false;

  @override
  void initState() {
    super.initState();

    // "Teclado arriba" desde que se entra a la pantalla — es el punto
    // completo de esta pantalla, a diferencia del campo inline de
    // Home, que nunca robaba el foco solo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _destinationFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  String _createPlacesSessionToken() {
    final random = Random.secure();
    final buffer = StringBuffer();

    for (var i = 0; i < 16; i++) {
      final value = random.nextInt(256);
      buffer.write(value.toRadixString(16).padLeft(2, '0'));
    }

    return buffer.toString();
  }

  String _ensurePlacesSessionToken() {
    return _placesSessionToken ??= _createPlacesSessionToken();
  }

  String? _backendMessage(DioException error) {
    final data = error.response?.data;

    if (data is Map) {
      final message = data['message'];

      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }

      if (message is List && message.isNotEmpty) {
        return message.map((item) => item.toString()).join('\n');
      }
    }

    return null;
  }

  String _formatPredictionDistance(int distanceMeters) {
    if (distanceMeters < 1000) {
      return '$distanceMeters m';
    }

    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  void _handleDestinationChanged(String value) {
    _searchDebounce?.cancel();

    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _predictions = const [];
        _searchMessage = null;
        _searching = false;
      });

      return;
    }

    final sessionToken = _ensurePlacesSessionToken();

    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) {
        return;
      }

      setState(() {
        _searching = true;
        _searchMessage = null;
      });

      try {
        final results = await ref
            .read(placesRepositoryProvider)
            .autocomplete(
              input: query,
              latitude: widget.originCoordinates.latitude,
              longitude: widget.originCoordinates.longitude,
              sessionToken: sessionToken,
            );

        if (!mounted || _destinationController.text.trim() != query) {
          return;
        }

        setState(() {
          _predictions = results;
          _searchMessage = results.isEmpty
              ? 'No encontramos destinos con ese nombre.'
              : null;
        });
      } on DioException catch (error) {
        if (!mounted) {
          return;
        }

        final backendMessage = _backendMessage(error);

        setState(() {
          _predictions = const [];
          _searchMessage =
              backendMessage ??
              (error.response == null
                  ? 'No se pudo conectar con TukiTuki.'
                  : 'No se pudo buscar el destino.');
        });
      } catch (error) {
        debugPrint('Error buscando destinos: $error');

        if (!mounted) {
          return;
        }

        setState(() {
          _predictions = const [];
          _searchMessage = 'No se pudo buscar el destino.';
        });
      } finally {
        if (mounted && _destinationController.text.trim() == query) {
          setState(() {
            _searching = false;
          });
        }
      }
    });
  }

  void _handleClear() {
    _searchDebounce?.cancel();
    _destinationController.clear();

    setState(() {
      _predictions = const [];
      _searchMessage = null;
      _searching = false;
    });
  }

  Future<void> _selectPrediction(PlacePrediction prediction) async {
    if (_loadingDetails) {
      return;
    }

    final sessionToken = _ensurePlacesSessionToken();

    _destinationFocusNode.unfocus();

    setState(() {
      _loadingDetails = true;
      _searchMessage = null;
    });

    try {
      final details = await ref
          .read(placesRepositoryProvider)
          .getDetails(placeId: prediction.placeId, sessionToken: sessionToken);

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        SearchDestinationResult(
          destination: LatLng(details.latitude, details.longitude),
          name: prediction.primaryText,
          address: details.formattedAddress,
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final backendMessage = _backendMessage(error);

      setState(() {
        _loadingDetails = false;
        _searchMessage =
            backendMessage ??
            (error.response == null
                ? 'No se pudo conectar con TukiTuki.'
                : 'No se pudo obtener el destino seleccionado.');
      });
    } catch (error) {
      debugPrint('Error obteniendo detalles del lugar: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingDetails = false;
        _searchMessage = 'No se pudo obtener el destino seleccionado.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PassengerColors.crema,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                  Text(
                    'Elige tu destino',
                    style: PassengerTypography.tituloSeccion.copyWith(
                      color: PassengerColors.verdeMarca,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PassengerSpacing.margenLateralPantalla,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Origen: solo lectura a propósito en este checkpoint
                  // — ver el doc-comment de la clase.
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: PassengerColors.acento,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: PassengerColors.blanco,
                          size: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.originAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PassengerTypography.cuerpo.copyWith(
                            color: PassengerColors.textoPrimario,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TukiSearchBar(
                    key: const ValueKey('search-destination-field'),
                    controller: _destinationController,
                    focusNode: _destinationFocusNode,
                    hintText: 'Buscar destino',
                    isLoading: _searching,
                    onClear: _handleClear,
                    onChanged: _handleDestinationChanged,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_searchMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PassengerSpacing.margenLateralPantalla,
                ),
                child: Text(
                  _searchMessage!,
                  style: PassengerTypography.subtitulo.copyWith(
                    color: PassengerColors.textoSecundario,
                  ),
                ),
              ),
            Expanded(
              child: _predictions.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PassengerSpacing.margenLateralPantalla,
                      ),
                      itemCount: _predictions.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: PassengerColors.bordeSuave,
                      ),
                      itemBuilder: (context, index) {
                        final prediction = _predictions[index];

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.location_on,
                            color: PassengerColors.destino,
                          ),
                          title: Text(
                            prediction.primaryText,
                            style: PassengerTypography.cuerpo.copyWith(
                              color: PassengerColors.textoPrimario,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: prediction.secondaryText.isEmpty
                              ? null
                              : Text(prediction.secondaryText),
                          trailing: prediction.distanceMeters == null
                              ? null
                              : Text(
                                  _formatPredictionDistance(
                                    prediction.distanceMeters!,
                                  ),
                                ),
                          onTap: _loadingDetails
                              ? null
                              : () => _selectPrediction(prediction),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
