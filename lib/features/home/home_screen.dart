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
  static const LatLng _tarapotoCenter = LatLng(
    -6.4877,
    -76.3599,
  );

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

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _destinationSearchController.dispose();
    _passengerOfferController.dispose();
    _destinationSearchFocusNode.dispose();
    _mapController?.dispose();

    super.dispose();
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

    _destinationSearchFocusNode.unfocus();
    _destinationSearchController.clear();

    setState(() {
      _selectedDestination = destination;

      _selectedDestinationName =
          'Destino en el mapa';

      _selectedDestinationAddress =
          'Destino seleccionado en el mapa';

      _placePredictions = const [];
      _placeSearchMessage = null;
      _placesSessionToken = null;

      _quote = null;
      _routePoints = const [];
    });
  }

  void _clearDestination() {
    _searchDebounce?.cancel();

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
            Theme.of(context)
                .colorScheme
                .primary,

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
                'Destino seleccionado en el mapa',
          );

      if (!mounted) {
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

      _passengerOfferController.text =
          quote.estimatedFare;

      setState(() {
        _quote = quote;
        _routePoints = routePoints;
      });

      if (routePoints.length >= 2) {
        await _fitCameraToRoute();
      }
    } on DioException catch (error) {
      if (!mounted) {
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

      if (!mounted) {
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
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _requestRide() async {
    final quote = _quote;

    if (quote == null) {
      return;
    }

    final rawOffer =
        _passengerOfferController.text
            .trim()
            .replaceAll(',', '.');

    final passengerOffer =
        double.tryParse(rawOffer);

    if (passengerOffer == null ||
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
        passengerOffer.toStringAsFixed(2);

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
        !_loadingPlaceDetails;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TukiTuki',
        ),
        actions: [
          IconButton(
            tooltip:
                'Cerrar sesión',
            onPressed:
                _logout,
            icon:
                const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 390,
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
                        left:
                            16,
                        right:
                            72,
                        top:
                            16,
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal:
                                  14,
                              vertical:
                                  10,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.touch_app,
                                  size:
                                      20,
                                ),
                                const SizedBox(
                                  width:
                                      10,
                                ),
                                Expanded(
                                  child: Text(
                                    'También puedes tocar un punto del mapa para elegir tu destino',
                                    style:
                                        Theme.of(
                                      context,
                                    )
                                            .textTheme
                                            .bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    Positioned(
                      right:
                          16,
                      bottom:
                          16,
                      child:
                          FloatingActionButton
                              .small(
                        heroTag:
                            'passenger-location',

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

              Padding(
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '¿A dónde vamos?',
                      style:
                          TextStyle(
                        fontSize:
                            30,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height:
                          8,
                    ),

                    if (_locationMessage !=
                        null)
                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            16,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_off,
                              ),
                              const SizedBox(
                                width:
                                    12,
                              ),
                              Expanded(
                                child: Text(
                                  _locationMessage!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (position !=
                        null)
                      Text(
                        'GPS: '
                        '${position.latitude.toStringAsFixed(5)}, '
                        '${position.longitude.toStringAsFixed(5)}',
                        style:
                            Theme.of(
                          context,
                        )
                                .textTheme
                                .bodySmall,
                      )
                    else
                      const Text(
                        'Obteniendo tu ubicación...',
                      ),

                    const SizedBox(
                      height:
                          20,
                    ),

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
                        labelText:
                            'Buscar destino',

                        hintText:
                            'Ej. GH Bus, Plaza de Morales...',

                        prefixIcon:
                            const Icon(
                          Icons.search,
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

                        border:
                            const OutlineInputBorder(),
                      ),
                    ),

                    if (_searchingPlaces) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      const LinearProgressIndicator(),
                    ],

                    if (_placeSearchMessage !=
                        null) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      Text(
                        _placeSearchMessage!,
                        style:
                            Theme.of(
                          context,
                        )
                                .textTheme
                                .bodyMedium,
                      ),
                    ],

                    if (_placePredictions
                        .isNotEmpty) ...[
                      const SizedBox(
                        height:
                            8,
                      ),

                      Card(
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

                    Card(
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .all(
                          18,
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding:
                                  EdgeInsets.zero,

                              leading:
                                  const Icon(
                                Icons.my_location,
                              ),

                              title:
                                  const Text(
                                'Origen',
                              ),

                              subtitle:
                                  Text(
                                position == null
                                    ? 'Esperando GPS...'
                                    : 'Tu ubicación actual',
                              ),
                            ),

                            const Divider(),

                            ListTile(
                              contentPadding:
                                  EdgeInsets.zero,

                              leading:
                                  const Icon(
                                Icons.location_on,
                              ),

                              title:
                                  const Text(
                                'Destino',
                              ),

                              subtitle:
                                  destination == null
                                      ? const Text(
                                          'Busca una dirección o toca el mapa',
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (_selectedDestinationName !=
                                                null)
                                              Text(
                                                _selectedDestinationName!,
                                                style:
                                                    const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),

                                            if (_selectedDestinationAddress !=
                                                null)
                                              Text(
                                                _selectedDestinationAddress!,
                                              ),
                                          ],
                                        ),

                              trailing:
                                  destination ==
                                          null
                                      ? null
                                      : IconButton(
                                          tooltip:
                                              'Quitar destino',
                                          onPressed:
                                              _clearDestination,
                                          icon:
                                              const Icon(
                                            Icons.close,
                                          ),
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(
                      height:
                          24,
                    ),

                    FilledButton.icon(
                      onPressed:
                          canEstimate
                              ? _estimateFare
                              : null,

                      icon: _loading
                          ? const SizedBox(
                              width:
                                  20,
                              height:
                                  20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.route,
                            ),

                      label: Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical:
                              16,
                        ),
                        child: Text(
                          _loading
                              ? 'Calculando ruta...'
                              : destination ==
                                      null
                                  ? 'Selecciona un destino'
                                  : 'Calcular tarifa',
                        ),
                      ),
                    ),

                    if (quote != null) ...[
                      const SizedBox(
                        height:
                            28,
                      ),

                      Card(
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
                                'Tu viaje',
                                style:
                                    TextStyle(
                                  fontSize:
                                      20,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              const Text(
                                'Precio recomendado TukiTuki',
                                textAlign:
                                    TextAlign.center,
                              ),

                              const SizedBox(
                                height:
                                    6,
                              ),

                              Text(
                                'S/ ${quote.estimatedFare}',
                                textAlign:
                                    TextAlign.center,
                                style:
                                    const TextStyle(
                                  fontSize:
                                      32,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              const Text(
                                '¿Cuánto quieres ofrecer?',
                                style:
                                    TextStyle(
                                  fontSize:
                                      17,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    8,
                              ),

                              TextField(
                                controller:
                                    _passengerOfferController,

                                enabled:
                                    !_requestingRide,

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
                                  fontSize:
                                      28,
                                  fontWeight:
                                      FontWeight.bold,
                                ),

                                decoration:
                                    const InputDecoration(
                                  prefixText:
                                      'S/ ',
                                  hintText:
                                      '5.00',
                                  border:
                                      OutlineInputBorder(),
                                  helperText:
                                      'Este es el monto que verán los conductores.',
                                ),
                              ),

                              const SizedBox(
                                height:
                                    8,
                              ),

                              Text(
                                '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km'
                                ' • '
                                '${(quote.durationSeconds / 60).round()} min',
                                textAlign:
                                    TextAlign.center,
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.my_location,
                                    size:
                                        20,
                                  ),
                                  const SizedBox(
                                    width:
                                        10,
                                  ),
                                  Expanded(
                                    child:
                                        Text(
                                      quote.originAddress,
                                    ),
                                  ),
                                ],
                              ),

                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(
                                  vertical:
                                      10,
                                ),
                                child:
                                    Icon(
                                  Icons.arrow_downward,
                                ),
                              ),

                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size:
                                        20,
                                  ),
                                  const SizedBox(
                                    width:
                                        10,
                                  ),
                                  Expanded(
                                    child:
                                        Text(
                                      quote.destinationAddress,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              Text(
                                'Cotización válida hasta '
                                '${quote.expiresAt.toLocal()}',
                                textAlign:
                                    TextAlign.center,
                                style:
                                    const TextStyle(
                                  fontSize:
                                      12,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    20,
                              ),

                              FilledButton.icon(
                                onPressed:
                                    _requestingRide
                                        ? null
                                        : _requestRide,

                                icon:
                                    _requestingRide
                                        ? const SizedBox(
                                            width:
                                                20,
                                            height:
                                                20,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth:
                                                  2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.two_wheeler,
                                          ),

                                label:
                                    Text(
                                  _requestingRide
                                      ? 'Solicitando...'
                                      : 'Ofrecer y buscar conductor',
                                ),
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
    );
  }
}