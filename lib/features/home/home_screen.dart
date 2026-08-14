import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../auth/data/auth_repository.dart';
import '../fare/data/fare_repository.dart';
import '../fare/domain/fare_estimate.dart';
import '../places/data/places_repository.dart';
import '../places/domain/place_prediction.dart';
import '../ride/data/ride_repository.dart';
import '../ride/domain/fare_amount.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
  });

  @override
  ConsumerState<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends ConsumerState<HomeScreen> {
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _secondaryGreen = Color(0xFF5C8A17);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _cream = Color(0xFFFFF9EC);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _softBorder = Color(0xFFEFE8D4);
  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF7C8A79);
  static const Color _destinationColor = Color(0xFFD8542C);

  static const LatLng _tarapotoCenter = LatLng(
    -6.4877,
    -76.3599,
  );

  /// Literal local que marca "el Passenger todavía no tiene una
  /// dirección real para este destino" (recién tocó el mapa, sin
  /// pasar por autocomplete). Mismo texto que Backend reconoce como
  /// señal para hacer reverse geocoding — G4B-R5.2 lo reutiliza para
  /// saber, cuando llega el FareQuote, si corresponde reemplazar
  /// esta tarjeta por la dirección real que Backend ya resolvió.
  static const String _manualDestinationPlaceholder =
      'Destino seleccionado en el mapa';

  GoogleMapController? _mapController;

  final TextEditingController
      _destinationSearchController =
      TextEditingController();

  final TextEditingController
      _passengerOfferController =
      TextEditingController();

  final FocusNode _destinationSearchFocusNode =
      FocusNode();

  Timer? _searchDebounce;
  Timer? _quoteExpiryTimer;

  Position? _currentPosition;
  LatLng? _selectedDestination;

  String? _selectedDestinationAddress;
  String? _selectedDestinationName;

  List<PlacePrediction> _placePredictions =
      const [];

  /*
   * Puntos decodificados de la polyline
   * devuelta por Google Routes.
   */
  List<LatLng> _routePoints = const [];

  String? _placesSessionToken;
  String? _placeSearchMessage;
  String? _locationMessage;

  bool _locating = false;
  bool _loading = false;
  bool _requestingRide = false;
  bool _searchingPlaces = false;
  bool _loadingPlaceDetails = false;

  FareEstimate? _quote;

  /// Expone el id de la cotización vigente únicamente para tests
  /// (verificar cuál request "ganó" ante selecciones de destino
  /// concurrentes — G4B-R5.1). No se usa en producción.
  @visibleForTesting
  String? get debugQuoteId => _quote?.quoteId;

  /// Generación de la última solicitud de cotización disparada.
  /// Evita que una respuesta/errores tardíos de un `_estimateFare`
  /// obsoleto (destino cambiado mientras la llamada anterior seguía
  /// en vuelo) pisen el estado de una selección de destino más
  /// reciente — G4B-R5. Solo protege de verdad si, al cambiar de
  /// destino, efectivamente arranca una NUEVA solicitud que
  /// incremente este contador (ver `_lastEstimateRequestDestination`
  /// y `_maybeAutoEstimateFare` — G4B-R5.1).
  int _quoteRequestId = 0;

  /// Destino para el que arrancó la última solicitud de cotización
  /// (en vuelo o ya resuelta). Permite a `_maybeAutoEstimateFare`
  /// distinguir "ya estoy pidiendo esto mismo, no dupliques" de "el
  /// destino cambió de verdad, hay que pedir una nueva aunque la
  /// anterior siga en vuelo" — G4B-R5.1.
  LatLng? _lastEstimateRequestDestination;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _quoteExpiryTimer?.cancel();
    _destinationSearchController.dispose();
    _passengerOfferController.dispose();
    _destinationSearchFocusNode.dispose();
    _mapController?.dispose();

    super.dispose();
  }

  void _cancelQuoteExpiryTimer() {
    _quoteExpiryTimer?.cancel();
    _quoteExpiryTimer = null;
  }

  /// G4B-R5.1: al vencer, la cotización se renueva sola — el
  /// Passenger nunca ve un botón "Calcular nueva tarifa". Llama
  /// directo a `_estimateFare()` (no a `_maybeAutoEstimateFare`,
  /// cuyo guard de "ya hay quote" bloquearía justo lo que acá
  /// queremos: reemplazar una quote existente pero vencida).
  /// `_estimateFare` nunca toca `_passengerOfferController`, así que
  /// la oferta que el Passenger ya escribió sobrevive intacta.
  void _scheduleQuoteExpiryTimer(
    FareEstimate quote,
  ) {
    _cancelQuoteExpiryTimer();

    final duration = quote.expiresAt.difference(
      DateTime.now(),
    );

    if (duration <= Duration.zero) {
      if (mounted) {
        _estimateFare();
      }

      return;
    }

    _quoteExpiryTimer = Timer(
      duration,
      () {
        _quoteExpiryTimer = null;

        if (!mounted) {
          return;
        }

        _estimateFare();
      },
    );
  }

  String _createPlacesSessionToken() {
    final random = Random.secure();
    final buffer = StringBuffer();

    for (var i = 0; i < 16; i++) {
      final value = random.nextInt(256);

      buffer.write(
        value.toRadixString(16).padLeft(2, '0'),
      );
    }

    return buffer.toString();
  }

  String _ensurePlacesSessionToken() {
    final existing = _placesSessionToken;

    if (existing != null) {
      return existing;
    }

    final token =
        _createPlacesSessionToken();

    _placesSessionToken = token;

    return token;
  }

  Future<void> _loadCurrentLocation() async {
    if (_locating) {
      return;
    }

    setState(() {
      _locating = true;
      _locationMessage = null;
    });

    try {
      final serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }

        setState(() {
          _locationMessage =
              'Activa la ubicación del dispositivo.';
        });

        return;
      }

      var permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator
                .requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        if (!mounted) {
          return;
        }

        setState(() {
          _locationMessage =
              'Necesitamos permiso de ubicación '
              'para encontrar tu punto de recojo.';
        });

        return;
      }

      if (permission ==
          LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }

        setState(() {
          _locationMessage =
              'El permiso de ubicación está '
              'bloqueado. Actívalo desde '
              'Ajustes del dispositivo.';
        });

        return;
      }

      final position =
          await Geolocator
              .getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }

      _cancelQuoteExpiryTimer();

      setState(() {
        _currentPosition = position;
        _locationMessage = null;

        /*
         * Si cambia el origen,
         * la cotización y su ruta
         * dejan de ser válidas.
         */
        _quote = null;
        _routePoints = const [];
      });

      _maybeAutoEstimateFare();

      await _moveCameraToCurrentLocation();
    } catch (error) {
      debugPrint(
        'Error obteniendo ubicación: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _locationMessage =
            'No se pudo obtener tu ubicación.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  Future<void>
      _moveCameraToCurrentLocation() async {
    final controller = _mapController;
    final position = _currentPosition;

    if (controller == null ||
        position == null) {
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            position.latitude,
            position.longitude,
          ),
          zoom: 16,
        ),
      ),
    );
  }

  Future<void> _moveCameraToDestination(
    LatLng destination,
  ) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: destination,
          zoom: 17,
        ),
      ),
    );
  }

  Future<void> _fitCameraToRoute() async {
    final controller = _mapController;

    if (controller == null ||
        _routePoints.isEmpty) {
      return;
    }

    var minLatitude =
        _routePoints.first.latitude;

    var maxLatitude =
        _routePoints.first.latitude;

    var minLongitude =
        _routePoints.first.longitude;

    var maxLongitude =
        _routePoints.first.longitude;

    for (final point in _routePoints) {
      if (point.latitude < minLatitude) {
        minLatitude = point.latitude;
      }

      if (point.latitude > maxLatitude) {
        maxLatitude = point.latitude;
      }

      if (point.longitude < minLongitude) {
        minLongitude = point.longitude;
      }

      if (point.longitude > maxLongitude) {
        maxLongitude = point.longitude;
      }
    }

    /*
     * Incluimos también el GPS real
     * del pasajero y el destino dentro
     * del encuadre de la ruta.
     */
    final position = _currentPosition;

    if (position != null) {
      minLatitude = min(
        minLatitude,
        position.latitude,
      );

      maxLatitude = max(
        maxLatitude,
        position.latitude,
      );

      minLongitude = min(
        minLongitude,
        position.longitude,
      );

      maxLongitude = max(
        maxLongitude,
        position.longitude,
      );
    }

    final destination =
        _selectedDestination;

    if (destination != null) {
      minLatitude = min(
        minLatitude,
        destination.latitude,
      );

      maxLatitude = max(
        maxLatitude,
        destination.latitude,
      );

      minLongitude = min(
        minLongitude,
        destination.longitude,
      );

      maxLongitude = max(
        maxLongitude,
        destination.longitude,
      );
    }

    await Future<void>.delayed(
      const Duration(
        milliseconds: 120,
      ),
    );

    if (!mounted) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              minLatitude,
              minLongitude,
            ),
            northeast: LatLng(
              maxLatitude,
              maxLongitude,
            ),
          ),
          48,
        ),
      );
    } catch (error) {
      debugPrint(
        'No se pudo ajustar la cámara a la ruta: $error',
      );
    }
  }

  void _selectDestination(
    LatLng destination,
  ) {
    _searchDebounce?.cancel();
    _cancelQuoteExpiryTimer();

    _destinationSearchFocusNode.unfocus();
    _destinationSearchController.clear();

    setState(() {
      _selectedDestination = destination;

      _selectedDestinationName =
          'Destino en el mapa';

      _selectedDestinationAddress =
          _manualDestinationPlaceholder;

      _placePredictions = const [];
      _placeSearchMessage = null;
      _placesSessionToken = null;

      _quote = null;
      _routePoints = const [];
    });

    _maybeAutoEstimateFare();
  }

  void _clearDestination() {
    _searchDebounce?.cancel();
    _cancelQuoteExpiryTimer();

    _destinationSearchController.clear();

    setState(() {
      _selectedDestination = null;
      _selectedDestinationAddress = null;
      _selectedDestinationName = null;

      _placePredictions = const [];
      _placeSearchMessage = null;
      _placesSessionToken = null;

      _quote = null;
      _routePoints = const [];
    });
  }

  Future<void> _onDestinationSearchChanged(
    String value,
  ) async {
    _searchDebounce?.cancel();

    final query = value.trim();

    if (_selectedDestination != null) {
      _cancelQuoteExpiryTimer();

      setState(() {
        _selectedDestination = null;
        _selectedDestinationAddress = null;
        _selectedDestinationName = null;

        _quote = null;
        _routePoints = const [];
      });
    }

    if (query.length < 2) {
      setState(() {
        _placePredictions = const [];
        _placeSearchMessage = null;
        _searchingPlaces = false;
      });

      return;
    }

    final position = _currentPosition;

    if (position == null) {
      setState(() {
        _placePredictions = const [];

        _placeSearchMessage =
            'Esperando tu ubicación GPS...';
      });

      return;
    }

    final sessionToken =
        _ensurePlacesSessionToken();

    _searchDebounce = Timer(
      const Duration(
        milliseconds: 450,
      ),
      () async {
        if (!mounted) {
          return;
        }

        setState(() {
          _searchingPlaces = true;
          _placeSearchMessage = null;
        });

        try {
          final results = await ref
              .read(placesRepositoryProvider)
              .autocomplete(
                input: query,
                latitude:
                    position.latitude,
                longitude:
                    position.longitude,
                sessionToken:
                    sessionToken,
              );

          if (!mounted) {
            return;
          }

          if (_destinationSearchController
                  .text
                  .trim() !=
              query) {
            return;
          }

          setState(() {
            _placePredictions = results;

            _placeSearchMessage =
                results.isEmpty
                    ? 'No encontramos destinos con ese nombre.'
                    : null;
          });
        } on DioException catch (error) {
          if (!mounted) {
            return;
          }

          final backendMessage =
              _backendMessage(error);

          setState(() {
            _placePredictions = const [];

            _placeSearchMessage =
                backendMessage ??
                (error.response == null
                    ? 'No se pudo conectar con TukiTuki.'
                    : 'No se pudo buscar el destino.');
          });
        } catch (error) {
          debugPrint(
            'Error buscando destinos: $error',
          );

          if (!mounted) {
            return;
          }

          setState(() {
            _placePredictions = const [];

            _placeSearchMessage =
                'No se pudo buscar el destino.';
          });
        } finally {
          if (mounted &&
              _destinationSearchController
                      .text
                      .trim() ==
                  query) {
            setState(() {
              _searchingPlaces = false;
            });
          }
        }
      },
    );
  }

  Future<void> _selectPlacePrediction(
    PlacePrediction prediction,
  ) async {
    if (_loadingPlaceDetails) {
      return;
    }

    final sessionToken =
        _ensurePlacesSessionToken();

    _destinationSearchFocusNode.unfocus();

    setState(() {
      _loadingPlaceDetails = true;
      _placeSearchMessage = null;
    });

    try {
      final details = await ref
          .read(placesRepositoryProvider)
          .getDetails(
            placeId:
                prediction.placeId,
            sessionToken:
                sessionToken,
          );

      if (!mounted) {
        return;
      }

      final destination = LatLng(
        details.latitude,
        details.longitude,
      );

      _destinationSearchController.text =
          prediction.primaryText;

      _cancelQuoteExpiryTimer();

      setState(() {
        _selectedDestination =
            destination;

        _selectedDestinationName =
            prediction.primaryText;

        _selectedDestinationAddress =
            details.formattedAddress;

        _placePredictions = const [];
        _placeSearchMessage = null;
        _placesSessionToken = null;

        _quote = null;
        _routePoints = const [];
      });

      await _moveCameraToDestination(
        destination,
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final backendMessage =
          _backendMessage(error);

      setState(() {
        _placeSearchMessage =
            backendMessage ??
            (error.response == null
                ? 'No se pudo conectar con TukiTuki.'
                : 'No se pudo obtener el destino seleccionado.');
      });
    } catch (error) {
      debugPrint(
        'Error obteniendo detalles del lugar: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _placeSearchMessage =
            'No se pudo obtener el destino seleccionado.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlaceDetails = false;
        });

        _maybeAutoEstimateFare();
      }
    }
  }

  /*
   * Ya NO creamos un Marker para el origen.
   *
   * La ubicación actual queda representada
   * únicamente por el punto azul nativo de
   * Google Maps mediante myLocationEnabled.
   *
   * Nosotros dibujamos solamente el destino.
   */
  Set<Marker> get _markers {
    final markers = <Marker>{};

    final destination =
        _selectedDestination;

    if (destination != null) {
      markers.add(
        Marker(
          markerId:
              const MarkerId(
            'destination',
          ),

          position:
              destination,

          infoWindow:
              InfoWindow(
            title:
                _selectedDestinationName ??
                'Destino',

            snippet:
                _selectedDestinationAddress ??
                'Destino seleccionado',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) {
      return const <Polyline>{};
    }

    return {
      Polyline(
        polylineId:
            const PolylineId(
          'fare-route',
        ),

        points:
            _routePoints,

        width:
            6,

        color:
            _secondaryGreen,

        geodesic:
            false,

        zIndex:
            10,
      ),
    };
  }

  String? _backendMessage(
    DioException error,
  ) {
    final data = error.response?.data;

    if (data is Map) {
      final message = data['message'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message.trim();
      }

      if (message is List &&
          message.isNotEmpty) {
        return message
            .map(
              (item) =>
                  item.toString(),
            )
            .join('\n');
      }
    }

    return null;
  }

  String _formatPredictionDistance(
    int distanceMeters,
  ) {
    if (distanceMeters < 1000) {
      return '$distanceMeters m';
    }

    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  List<LatLng> _decodePolyline(
    String encoded,
  ) {
    final points = <LatLng>[];

    var index = 0;
    var latitude = 0;
    var longitude = 0;

    try {
      while (index < encoded.length) {
        var result = 0;
        var shift = 0;
        int byte;

        do {
          if (index >= encoded.length) {
            return const [];
          }

          byte =
              encoded.codeUnitAt(index++) -
              63;

          result |=
              (byte & 0x1f) << shift;

          shift += 5;
        } while (byte >= 0x20);

        final latitudeDelta =
            (result & 1) != 0
                ? ~(result >> 1)
                : result >> 1;

        latitude +=
            latitudeDelta;

        result = 0;
        shift = 0;

        do {
          if (index >= encoded.length) {
            return const [];
          }

          byte =
              encoded.codeUnitAt(index++) -
              63;

          result |=
              (byte & 0x1f) << shift;

          shift += 5;
        } while (byte >= 0x20);

        final longitudeDelta =
            (result & 1) != 0
                ? ~(result >> 1)
                : result >> 1;

        longitude +=
            longitudeDelta;

        points.add(
          LatLng(
            latitude / 1e5,
            longitude / 1e5,
          ),
        );
      }
    } catch (error) {
      debugPrint(
        'No se pudo decodificar la ruta: $error',
      );

      return const [];
    }

    return points;
  }

  /// G4B-R5: dispara `_estimateFare` automáticamente en cuanto
  /// origen y destino están listos, sin esperar un tap manual.
  /// Nunca se llama desde `build()` (evitaría loops de setState) —
  /// solo desde los handlers que cambian destino o posición.
  ///
  /// G4B-R5.1: "ya hay una solicitud en vuelo" solo bloquea un
  /// disparo nuevo si es para el MISMO destino (evita duplicados
  /// inútiles). Si el destino cambió de verdad mientras la anterior
  /// seguía en vuelo, se deja pasar a propósito: `_estimateFare`
  /// arranca de inmediato e invalida la anterior al incrementar
  /// `_quoteRequestId`, en vez de esperar a que termine (eso dejaría
  /// la pantalla bloqueada esperando una respuesta que ya no importa).
  void _maybeAutoEstimateFare() {
    final destination = _selectedDestination;

    if (_currentPosition == null || destination == null) {
      return;
    }

    if (_requestingRide || _quote != null) {
      return;
    }

    if (_loading && _lastEstimateRequestDestination == destination) {
      return;
    }

    _estimateFare();
  }

  Future<void> _estimateFare() async {
    final position =
        _currentPosition;

    final destination =
        _selectedDestination;

    if (position == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Todavía no tenemos tu ubicación GPS.',
          ),
        ),
      );

      return;
    }

    if (destination == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Busca un destino o tócalo en el mapa.',
          ),
        ),
      );

      return;
    }

    _cancelQuoteExpiryTimer();

    final requestId = ++_quoteRequestId;

    // G4B-R5.1: marca INMEDIATAMENTE (antes del await) para qué
    // destino es esta solicitud. Cualquier solicitud anterior para
    // un destino distinto queda invalidada desde ya por el cambio
    // de `_quoteRequestId`, sin esperar a que esa anterior termine.
    _lastEstimateRequestDestination = destination;

    setState(() {
      _loading = true;
      _quote = null;
      _routePoints = const [];
    });

    try {
      final quote = await ref
          .read(fareRepositoryProvider)
          .estimateRide(
            originLatitude:
                position.latitude,

            originLongitude:
                position.longitude,

            destinationLatitude:
                destination.latitude,

            destinationLongitude:
                destination.longitude,

            destinationAddress:
                _selectedDestinationAddress ??
                _manualDestinationPlaceholder,
          );

      if (!mounted || requestId != _quoteRequestId) {
        return;
      }

      final encodedPolyline =
          quote.routePolyline;

      final routePoints =
          encodedPolyline == null
              ? const <LatLng>[]
              : _decodePolyline(
                  encodedPolyline,
                );

      // G4B-R5.2: si el destino vino de un tap en el mapa (todavía
      // muestra el placeholder local), reemplaza la tarjeta Home por
      // la dirección real que Backend ya resolvió — sin volver a
      // pedir un FareQuote ni tocar coordenadas. Autocomplete nunca
      // deja este placeholder puesto, así que este bloque nunca lo
      // toca (no rompe "B" del checkpoint). Vive DESPUÉS del check
      // de `requestId` de arriba, así que una respuesta obsoleta de
      // un destino anterior jamás llega hasta acá (protege Caso 4).
      final resolvedDestinationAddress =
          quote.destinationAddress.trim();

      final destinationAddressResolved =
          _selectedDestinationAddress ==
              _manualDestinationPlaceholder &&
          resolvedDestinationAddress.isNotEmpty;

      setState(() {
        _quote = quote;
        _routePoints = routePoints;

        if (destinationAddressResolved) {
          _selectedDestinationName =
              resolvedDestinationAddress;
          _selectedDestinationAddress = null;
        }
      });

      _scheduleQuoteExpiryTimer(quote);

      if (routePoints.length >= 2) {
        await _fitCameraToRoute();
      }
    } on DioException catch (error) {
      if (!mounted || requestId != _quoteRequestId) {
        return;
      }

      final backendMessage =
          _backendMessage(error);

      String message =
          backendMessage ??
          'No se pudo calcular la tarifa.';

      if (error.response?.statusCode ==
              401 &&
          backendMessage == null) {
        message =
            'Tu sesión ya no es válida.';
      } else if (error.response
                  ?.statusCode ==
              503 &&
          backendMessage == null) {
        message =
            'El servicio de rutas no está '
            'disponible en este momento.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar '
            'con TukiTuki.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } catch (error) {
      debugPrint(
        'Error calculando tarifa: $error',
      );

      if (!mounted || requestId != _quoteRequestId) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Ocurrió un error inesperado.',
          ),
        ),
      );
    } finally {
      if (mounted && requestId == _quoteRequestId) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _requestRide() async {
    if (_requestingRide) {
      return;
    }

    final quote = _quote;

    if (quote == null) {
      return;
    }

    if (_isQuoteExpired(quote)) {
      // G4B-R5.1: caso límite (venció justo al tocar el CTA) — se
      // renueva sola, sin pedirle al Passenger una acción manual.
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'La cotización venció. Actualizándola...',
          ),
        ),
      );

      _estimateFare();

      return;
    }

    final rawOffer =
        _passengerOfferController.text
            .trim()
            .replaceAll(',', '.');

    final passengerOffer =
        double.tryParse(rawOffer);

    if (passengerOffer == null ||
        !passengerOffer.isFinite ||
        passengerOffer <= 0 ||
        passengerOffer > 9999.99) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa un monto válido para tu oferta.',
          ),
        ),
      );

      return;
    }

    final decimalParts = rawOffer.split('.');

    if (decimalParts.length > 2 ||
        (decimalParts.length == 2 &&
            decimalParts[1].length > 2)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'La oferta puede tener como máximo '
            '2 decimales.',
          ),
        ),
      );

      return;
    }

    final normalizedPassengerOffer =
        normalizePassengerOfferFare(rawOffer);

    if (normalizedPassengerOffer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa un monto válido para tu oferta.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _requestingRide = true;
    });

    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .createRide(
            fareQuoteId:
                quote.quoteId,
            passengerOfferFare:
                normalizedPassengerOffer,
          );

      if (!mounted) {
        return;
      }

      context.go(
        '/ride/${ride.id}',
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final backendMessage =
          _backendMessage(error);

      String message =
          backendMessage ??
          'No se pudo solicitar el viaje.';

      if (error.response?.statusCode ==
              400 &&
          backendMessage == null) {
        message =
            'La cotización venció. '
            'Calcula una nueva tarifa.';
      } else if (error.response
                  ?.statusCode ==
              409 &&
          backendMessage == null) {
        message =
            'Ya tienes un viaje activo.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar '
            'con TukiTuki.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _requestingRide = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await ref
        .read(authRepositoryProvider)
        .logout();

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  bool _isQuoteExpired(
    FareEstimate quote,
  ) {
    return !quote.expiresAt.isAfter(
      DateTime.now(),
    );
  }

  String _formatQuoteExpiry(
    DateTime expiresAt,
  ) {
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(
      TimeOfDay.fromDateTime(
        expiresAt.toLocal(),
      ),
      alwaysUse24HourFormat:
          MediaQuery.alwaysUse24HourFormatOf(
        context,
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.16,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 17,
            color: _ctaYellow,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final position = _currentPosition;
    final destination =
        _selectedDestination;

    final canEstimate =
        position != null &&
        destination != null &&
        !_loading &&
        !_requestingRide &&
        !_loadingPlaceDetails;

    final quoteExpired =
        quote != null && _isQuoteExpired(quote);

    final hasValidOffer =
        normalizePassengerOfferFare(
          _passengerOfferController.text,
        ) !=
        null;

    final canRequestRide =
        destination != null &&
        quote != null &&
        !quoteExpired &&
        hasValidOffer &&
        !_loading &&
        !_requestingRide;

    final mediaQuery = MediaQuery.of(context);
    final keyboardInset =
        mediaQuery.viewInsets.bottom;
    final keyboardVisible =
        keyboardInset > 0;
    late final String ctaLabel;
    late final VoidCallback? ctaOnPressed;
    // G4B-R5: null = sin icono. La cotización ya no depende de un
    // tap manual ("Calcular tarifa" dejó de ser un paso visible);
    // `_maybeAutoEstimateFare` la dispara sola apenas hay destino.
    //
    // G4B-R5.1: la expiración también se renueva sola
    // (`_scheduleQuoteExpiryTimer` llama a `_estimateFare` sin
    // esperar un tap). Este branch (quote == null, ya sin loading)
    // solo se ve de verdad cuando la solicitud automática — inicial
    // o de renovación — falló por un error real: es un retry manual
    // neutral ("Reintentar"), nunca vuelve a decir "Calcular
    // [nueva] tarifa".
    late final IconData? ctaIcon;

    if (_loading) {
      ctaLabel = 'Calculando tarifa...';
      ctaOnPressed = null;
      ctaIcon = Icons.route;
    } else if (_requestingRide) {
      ctaLabel = 'Buscando conductor...';
      ctaOnPressed = null;
      ctaIcon = Icons.two_wheeler;
    } else if (destination == null) {
      ctaLabel = 'Selecciona un destino';
      ctaOnPressed = null;
      ctaIcon = Icons.location_on_outlined;
    } else if (quote == null || quoteExpired) {
      ctaLabel = 'Reintentar';
      ctaOnPressed =
          canEstimate ? _estimateFare : null;
      ctaIcon = Icons.refresh;
    } else {
      ctaLabel = 'Ofrecer y buscar conductor';
      ctaOnPressed =
          canRequestRide ? _requestRide : null;
      // G4B-R5: sin icono de moto en este CTA.
      ctaIcon = null;
    }

    final ctaShowsProgress =
        _loading || _requestingRide;
    final ctaButtonStyle = FilledButton.styleFrom(
      backgroundColor: _ctaYellow,
      foregroundColor: _darkGreen,
      disabledBackgroundColor: _softBorder,
      disabledForegroundColor: _secondaryText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
    final mapHeight = keyboardVisible
        ? 150.0
        : (mediaQuery.size.height * 0.33)
            .clamp(200.0, 280.0)
            .toDouble();

    return Scaffold(
      backgroundColor: _cream,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 58,
        backgroundColor: _cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _green,
                borderRadius:
                    BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.two_wheeler,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'TukiTuki',
              style: TextStyle(
                color: _darkGreen,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
            color: _darkGreen,
            icon: const Icon(
              Icons.logout,
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: _softBorder,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: mapHeight,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition:
                          const CameraPosition(
                        target:
                            _tarapotoCenter,
                        zoom:
                            14.5,
                      ),

                      /*
                       * Solo contiene
                       * el marcador del destino.
                       */
                      markers:
                          _markers,

                      polylines:
                          _polylines,

                      /*
                       * Google Maps muestra
                       * el punto azul nativo
                       * de la ubicación actual.
                       */
                      myLocationEnabled:
                          position != null,

                      myLocationButtonEnabled:
                          false,

                      zoomControlsEnabled:
                          false,

                      compassEnabled:
                          true,

                      mapToolbarEnabled:
                          false,

                      scrollGesturesEnabled:
                          true,

                      zoomGesturesEnabled:
                          true,

                      rotateGesturesEnabled:
                          true,

                      tiltGesturesEnabled:
                          true,

                      gestureRecognizers:
                          <Factory<
                              OneSequenceGestureRecognizer>>{
                        Factory<
                            OneSequenceGestureRecognizer>(
                          () =>
                              EagerGestureRecognizer(),
                        ),
                      },

                      onMapCreated:
                          (controller) {
                        _mapController =
                            controller;

                        _moveCameraToCurrentLocation();
                      },

                      onTap:
                          _selectDestination,
                    ),

                    if (destination == null)
                      Positioned(
                        left: 14,
                        right: 74,
                        top: 14,
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          color: _cream,
                          surfaceTintColor:
                              Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.touch_app,
                                  size: 18,
                                  color: _darkGreen,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Toca el mapa para elegir tu destino',
                                    style: TextStyle(
                                      color: _primaryText,
                                      fontSize: 12.5,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    Positioned(
                      right: 16,
                      bottom: 30,
                      child:
                          FloatingActionButton
                              .small(
                        heroTag:
                            'passenger-location',

                        tooltip:
                            'Centrar en mi ubicación',
                        backgroundColor:
                            _ctaYellow,
                        foregroundColor:
                            _darkGreen,
                        disabledElevation: 0,
                        onPressed:
                            _locating
                                ? null
                                : _loadCurrentLocation,

                        child: _locating
                            ? const Padding(
                                padding:
                                    EdgeInsets.all(
                                  10,
                                ),
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                  color:
                                      _darkGreen,
                                ),
                              )
                            : const Icon(
                                Icons.my_location,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                transform:
                    Matrix4.translationValues(
                  0,
                  -24,
                  0,
                ),
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  4,
                ),
                decoration: const BoxDecoration(
                  color: _cream,
                  borderRadius:
                      BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _border,
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      '¿A dónde vamos?',
                      style:
                          TextStyle(
                        color: _darkGreen,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (_locationMessage !=
                        null)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFF0E8,
                          ),
                          borderRadius:
                              BorderRadius.circular(14),
                          border: Border.all(
                            color: _destinationColor
                                .withValues(
                              alpha: 0.22,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_off,
                                color: _destinationColor,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _locationMessage!,
                                  style: const TextStyle(
                                    color: _primaryText,
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (position !=
                        null)
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: _green,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Ubicación actual detectada',
                            style: TextStyle(
                              color: _secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _green,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Obteniendo tu ubicación...',
                            style: TextStyle(
                              color: _secondaryText,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    TextField(
                      controller:
                          _destinationSearchController,

                      focusNode:
                          _destinationSearchFocusNode,

                      enabled:
                          position != null &&
                          !_loadingPlaceDetails,

                      textInputAction:
                          TextInputAction.search,

                      autocorrect:
                          false,

                      onChanged:
                          _onDestinationSearchChanged,

                      decoration:
                          InputDecoration(
                        hintText:
                            'Buscar destino',

                        hintStyle:
                            const TextStyle(
                          color: _secondaryText,
                          fontWeight:
                              FontWeight.w500,
                        ),

                        prefixIcon:
                            const Icon(
                          Icons.search,
                          color: _darkGreen,
                        ),

                        suffixIcon:
                            _loadingPlaceDetails
                                ? const Padding(
                                    padding:
                                        EdgeInsets.all(
                                      14,
                                    ),
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth:
                                          2,
                                    ),
                                  )
                                : _destinationSearchController
                                        .text
                                        .isNotEmpty
                                    ? IconButton(
                                        tooltip:
                                            'Limpiar destino',
                                        onPressed:
                                            _clearDestination,
                                        icon:
                                            const Icon(
                                          Icons.close,
                                        ),
                                      )
                                    : null,

                        filled: true,
                        fillColor: _secondaryCream,
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(
                            color: _border,
                          ),
                        ),
                        enabledBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(
                            color: _border,
                          ),
                        ),
                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(
                            color: _green,
                            width: 1.5,
                          ),
                        ),
                        disabledBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(
                            color: _softBorder,
                          ),
                        ),
                      ),
                    ),

                    if (_searchingPlaces) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      const LinearProgressIndicator(
                        color: _green,
                        backgroundColor: _softBorder,
                      ),
                    ],

                    if (_placeSearchMessage !=
                        null) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      Text(
                        _placeSearchMessage!,
                        style: const TextStyle(
                          color: _secondaryText,
                        ),
                      ),
                    ],

                    if (_placePredictions
                        .isNotEmpty) ...[
                      const SizedBox(
                        height:
                            8,
                      ),

                      Card(
                        margin: EdgeInsets.zero,
                        color: _secondaryCream,
                        surfaceTintColor:
                            Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          side: const BorderSide(
                            color: _border,
                          ),
                        ),
                        clipBehavior:
                            Clip.antiAlias,
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index <
                                  _placePredictions
                                      .length;
                              index++
                            ) ...[
                              ListTile(
                                leading:
                                    const Icon(
                                  Icons.location_on,
                                  color:
                                      _destinationColor,
                                ),

                                title:
                                    Text(
                                  _placePredictions[
                                          index]
                                      .primaryText,
                                ),

                                subtitle: _placePredictions[
                                            index]
                                        .secondaryText
                                        .isEmpty
                                    ? null
                                    : Text(
                                        _placePredictions[
                                                index]
                                            .secondaryText,
                                      ),

                                trailing:
                                    _placePredictions[
                                                index]
                                            .distanceMeters ==
                                        null
                                    ? null
                                    : Text(
                                        _formatPredictionDistance(
                                          _placePredictions[
                                                  index]
                                              .distanceMeters!,
                                        ),
                                      ),

                                onTap:
                                    _loadingPlaceDetails
                                        ? null
                                        : () =>
                                            _selectPlacePrediction(
                                              _placePredictions[
                                                  index],
                                            ),
                              ),

                              if (index !=
                                  _placePredictions
                                          .length -
                                      1)
                                const Divider(
                                  height:
                                      1,
                                  color:
                                      _softBorder,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(
                      height:
                          20,
                    ),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _secondaryCream,
                        borderRadius:
                            BorderRadius.circular(17),
                        border: Border.all(
                          color: _border,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration:
                                    const BoxDecoration(
                                  color: _green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Origen',
                                      style: TextStyle(
                                        color:
                                            _secondaryText,
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      quote != null &&
                                              quote.originAddress
                                                  .trim()
                                                  .isNotEmpty
                                          ? quote.originAddress
                                          : position == null
                                              ? 'Esperando GPS...'
                                              : 'Tu ubicación actual',
                                      style: const TextStyle(
                                        color: _primaryText,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              left: 9,
                            ),
                            child: Align(
                              alignment:
                                  Alignment.centerLeft,
                              child: Column(
                                children: List.generate(
                                  3,
                                  (_) => Container(
                                    width: 2,
                                    height: 4,
                                    margin:
                                        const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    color: _border,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: _destinationColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Destino',
                                      style: TextStyle(
                                        color:
                                            _secondaryText,
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      destination == null
                                          ? 'Selecciona un destino'
                                          : _selectedDestinationName ??
                                              'Destino seleccionado',
                                      style: const TextStyle(
                                        color: _primaryText,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                    ),
                                    if (destination != null &&
                                        _selectedDestinationAddress !=
                                            null &&
                                        _selectedDestinationAddress!
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _selectedDestinationAddress!,
                                        style: const TextStyle(
                                          color:
                                              _secondaryText,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (destination != null)
                                IconButton(
                                  tooltip: 'Quitar destino',
                                  onPressed:
                                      _clearDestination,
                                  visualDensity:
                                      VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close,
                                    color: _secondaryText,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (quote != null) ...[
                      const SizedBox(
                        height:
                            28,
                      ),

                      Container(
                        decoration: BoxDecoration(
                          color: _darkGreen,
                          borderRadius:
                              BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _darkGreen.withValues(
                                alpha: 0.16,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            20,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '¿Cuánto quieres ofrecer?',
                                style:
                                    TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    8,
                              ),

                              TextField(
                                key: const ValueKey(
                                  'passenger-offer-field',
                                ),

                                controller:
                                    _passengerOfferController,

                                enabled:
                                    !_requestingRide,

                                onChanged: (_) {
                                  setState(() {});
                                },

                                keyboardType:
                                    const TextInputType
                                        .numberWithOptions(
                                  decimal:
                                      true,
                                ),

                                textAlign:
                                    TextAlign.center,

                                style:
                                    const TextStyle(
                                  color: _primaryText,
                                  fontSize: 27,
                                  fontWeight:
                                      FontWeight.w800,
                                ),

                                decoration:
                                    InputDecoration(
                                  prefixText:
                                      'S/ ',
                                  prefixStyle:
                                      const TextStyle(
                                    color: _secondaryText,
                                    fontSize: 19,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                  hintText:
                                      '5.00',
                                  filled: true,
                                  fillColor: _cream,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                      14,
                                    ),
                                    borderSide:
                                        BorderSide.none,
                                  ),
                                  enabledBorder:
                                      OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                      14,
                                    ),
                                    borderSide:
                                        BorderSide.none,
                                  ),
                                  focusedBorder:
                                      OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                      14,
                                    ),
                                    borderSide:
                                        const BorderSide(
                                      color: _ctaYellow,
                                      width: 2,
                                    ),
                                  ),
                                  disabledBorder:
                                      OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(
                                      14,
                                    ),
                                    borderSide:
                                        BorderSide.none,
                                  ),
                                  helperText:
                                      'Este es el monto que verán los conductores.',
                                  helperStyle:
                                      const TextStyle(
                                    color: Color(
                                      0xFFB9C8BC,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(
                                height:
                                    8,
                              ),

                              Wrap(
                                alignment:
                                    WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _buildMetricChip(
                                    icon:
                                        Icons.route_outlined,
                                    label:
                                        '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km',
                                  ),
                                  _buildMetricChip(
                                    icon:
                                        Icons.schedule,
                                    label:
                                        '${(quote.durationSeconds / 60).round()} min',
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    quoteExpired
                                        ? Icons.timer_off_outlined
                                        : Icons.schedule,
                                    size: 16,
                                    color: quoteExpired
                                        ? _ctaYellow
                                        : const Color(
                                            0xFFB9C8BC,
                                          ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      quoteExpired
                                          ? 'Cotización vencida'
                                          : 'Cotización válida hasta '
                                              '${_formatQuoteExpiry(quote.expiresAt)}',
                                      textAlign:
                                          TextAlign.center,
                                      style: TextStyle(
                                        color: quoteExpired
                                            ? _ctaYellow
                                            : const Color(
                                                0xFFB9C8BC,
                                              ),
                                        fontSize: 12.5,
                                        fontWeight:
                                            FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(
                      height:
                          24,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: keyboardInset,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: _cream,
            border: Border(
              top: BorderSide(
                color: _softBorder,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: !keyboardVisible,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                10,
                16,
                12,
              ),
              child: SizedBox(
                height: 54,
                // G4B-R5: "Ofrecer y buscar conductor" no lleva
                // icono — únicamente ese estado (ctaIcon null y sin
                // progreso) usa un FilledButton sin `.icon`.
                child: !ctaShowsProgress && ctaIcon == null
                    ? FilledButton(
                        onPressed: ctaOnPressed,
                        style: ctaButtonStyle,
                        child: Text(ctaLabel),
                      )
                    : FilledButton.icon(
                        onPressed: ctaOnPressed,
                        style: ctaButtonStyle,
                        icon: ctaShowsProgress
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _darkGreen,
                                ),
                              )
                            : Icon(
                                ctaIcon,
                              ),
                        label: Text(ctaLabel),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
