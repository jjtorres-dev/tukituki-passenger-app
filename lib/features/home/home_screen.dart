import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/passenger_colors.dart';
import '../../core/widgets/tuki_search_bar.dart';
import '../auth/data/auth_repository.dart';
import '../fare/data/fare_repository.dart';
import '../fare/domain/fare_estimate.dart';
import '../ride/data/ride_repository.dart';
import '../ride/domain/fare_amount.dart';
import '../ride/domain/ride_history_item.dart';
import 'domain/search_destination_result.dart';
import 'domain/suggested_destinations.dart';
import 'search_destination_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const LatLng _tarapotoCenter = LatLng(-6.4877, -76.3599);
  static const String _originMarkerAsset =
      'assets/images/passenger_origin_marker.png';
  static const Size _originMarkerLogicalSize = Size(48, 64);
  static const double _originMarkerLabelGap = 6;
  static const double _routeBoundsPadding = 48;

  /// Literal local que marca "el Passenger todavía no tiene una
  /// dirección real para este destino" (recién tocó el mapa, sin
  /// pasar por autocomplete). Se sigue enviando como `address` (el
  /// backend lo exige no vacío) y se sigue mostrando en pantalla
  /// hasta que llega el FareQuote, pero desde G4B-CONTRACT-R1 la
  /// señal real para que Backend dispare reverse geocoding es la
  /// bandera `isManualSelection` (ver `_destinationIsManualSelection`
  /// más abajo) — este texto ya NO se compara contra nada, ni acá ni
  /// en Backend, salvo en el fallback legado de una única instalación
  /// anterior a ese campo (ver `fares.service.ts`).
  static const String _manualDestinationPlaceholder =
      'Destino seleccionado en el mapa';

  /// ORIGIN-ADDRESS-R1: distancia mínima, en metros, para considerar
  /// que el GPS se movió a un lugar distinto y vale la pena resolver
  /// una dirección de origen nueva. Por debajo de este umbral, la
  /// nueva posición se trata como "el mismo punto" (jitter típico de
  /// un GPS de celular en reposo) y se reutiliza
  /// [_resolvedOriginAddress] sin llamar de nuevo al backend.
  ///
  /// Sin validar todavía en calle — mismo estado que
  /// `_driverMarkerLargeJumpMetersThreshold` (300m, umbral de salto
  /// grande del marcador del Driver, `ride_searching_screen.dart`,
  /// R4.4B), que tampoco se probó en zona de señal GPS difícil.
  /// Ajustar este valor si la prueba física muestra que 50m es
  /// demasiado chico (parpadea con el jitter normal del GPS) o
  /// demasiado grande (no actualiza al moverse una cuadra corta).
  static const double _originAddressCacheDistanceMeters = 50;

  GoogleMapController? _mapController;
  BitmapDescriptor? _originMarkerIcon;
  bool _originMarkerIconLoadStarted = false;

  /// HOME-LAYOUT-R1 (rev: marcador real): el ícono del origen es ahora
  /// un `Marker` real de Google Maps (ver [_markers]) — el SDK nativo
  /// ya lo sigue solo en cualquier gesto de cámara. La etiqueta con la
  /// dirección, en cambio, sigue siendo un widget de Flutter (Google
  /// Maps no permite anclarle overlays propios a un `Marker` nativo),
  /// así que hay que proyectar su posición en pantalla a mano — ver
  /// [_originMarkerScreenOffset] y [_updateOriginMarkerScreenOffset].
  /// Mientras esa proyección todavía no llegó (por ejemplo, en tests:
  /// nunca hay un `GoogleMapController` real, así que nunca llega),
  /// [_buildOriginMarkerLabel] se sigue centrando en el área de mapa
  /// libre arriba de la hoja, igual que antes de este cambio.
  Offset? _originMarkerScreenOffset;

  /// Evita que la resolución de una proyección vieja (una llamada a
  /// `getScreenCoordinate` que tardó más que las siguientes) pise el
  /// resultado de una más reciente — mismo patrón que
  /// [_originAddressRequestId] y [_quoteRequestId] en este archivo.
  int _originMarkerScreenOffsetRequestId = 0;

  /// `getScreenCoordinate` devuelve píxeles FÍSICOS (de dispositivo),
  /// no lógicos — hay que dividirlos por este valor para que el
  /// resultado coincida con el sistema de coordenadas que usa
  /// `Positioned` (píxeles lógicos, igual que el resto de Flutter).
  /// Se actualiza en cada `build()` desde `MediaQuery`.
  double _devicePixelRatio = 1;

  /// HOME-FLOW-R1: alto real (medido, no estimado) del bloque superior
  /// menú+tarjeta origen/destino. Incluye los 14 px que separan el menú
  /// del borde superior del mapa, para que GoogleMap.padding.top
  /// describa toda el área ocupada por el overlay y no solo sus hijos.
  double _topOverlayHeight = 0;

  /// HOME-LAYOUT-R1: alto real (medido, no estimado) del bloque
  /// recentrar+hoja anclado al fondo del Stack. Se usa para dos cosas
  /// que TIENEN que coincidir entre sí: dónde se centra el marcador
  /// propio MIENTRAS no hay una proyección real todavía (área de mapa
  /// que queda libre arriba de ese bloque, ver
  /// [_buildOriginMarkerLabel]) y el `padding` que se le pasa a
  /// `GoogleMap` (para que el SDK de Google centre la cámara en esa
  /// misma área libre, no en el centro geométrico de la pantalla
  /// completa — de lo contrario el marcador queda centrado en un sitio
  /// distinto de donde Google realmente dibuja la posición real).
  /// Arranca en 0: el primer frame lo corrige apenas se mide el bloque
  /// real, vía [_MeasureSize].
  double _bottomOverlayHeight = 0;

  /// Generación del destino visible. Cambia incluso si el destino se
  /// borra sin que llegue a arrancar otra cotización, para que una
  /// respuesta anterior tampoco pueda programar un movimiento de cámara.
  int _destinationGeneration = 0;

  /// Identifica la ruta que puede mantener su encuadre ante cambios de
  /// altura del overlay. Los dos valores tienen que seguir coincidiendo
  /// con las generaciones vigentes antes de animar la cámara.
  int? _activeRouteQuoteGeneration;
  int? _activeRouteDestinationGeneration;

  /// No-null desde que una cotización nueva entrega su ruta hasta que el
  /// primer encuadre automático de ESA cotización termina. Mientras está
  /// pendiente, el encuadre gana incluso si el Passenger movió el mapa.
  int? _pendingRouteFitQuoteGeneration;

  /// Cada nueva medición invalida el callback post-frame anterior. La
  /// microtask se ejecuta después de todos los callbacks post-frame de ese
  /// frame, incluido `_MeasureSize`, por lo que solo sobrevive la última
  /// altura observada y no se encadenan varias animaciones.
  int _routeFitScheduleGeneration = 0;

  bool _cameraMovedByUserSinceRouteFit = false;
  int _cameraUserMoveGeneration = 0;
  final Set<int> _activeMapPointers = <int>{};

  void _handleTopOverlaySizeChanged(Size size) {
    _handleOverlaySizeChanged(size: size, isTopOverlay: true);
  }

  void _handleBottomOverlaySizeChanged(Size size) {
    _handleOverlaySizeChanged(size: size, isTopOverlay: false);
  }

  /// Los overlays superior e inferior alimentan exactamente el mismo
  /// mecanismo de reencuadre. Cualquier cambio de geometría —incluido el
  /// alto nuevo que puede producir la dirección de origen asíncrona—
  /// programa un nuevo ajuste con ambos paddings ya actualizados.
  void _handleOverlaySizeChanged({
    required Size size,
    required bool isTopOverlay,
  }) {
    final currentHeight = isTopOverlay
        ? _topOverlayHeight
        : _bottomOverlayHeight;

    if (!mounted || size.height == currentHeight) {
      return;
    }

    setState(() {
      if (isTopOverlay) {
        _topOverlayHeight = size.height;
      } else {
        _bottomOverlayHeight = size.height;
      }
    });

    final quoteGeneration = _activeRouteQuoteGeneration;
    final destinationGeneration = _activeRouteDestinationGeneration;

    if (quoteGeneration == null || destinationGeneration == null) {
      return;
    }

    final newQuoteStillNeedsFit =
        _pendingRouteFitQuoteGeneration == quoteGeneration;

    if (newQuoteStillNeedsFit || !_cameraMovedByUserSinceRouteFit) {
      _scheduleRouteFitAfterLayout(
        quoteGeneration: quoteGeneration,
        destinationGeneration: destinationGeneration,
      );
    }
  }

  void _advanceDestinationGeneration() {
    _destinationGeneration++;
    _lastEstimateRequestDestination = null;
    _invalidateRouteFit();
  }

  void _invalidateRouteFit() {
    _routeFitScheduleGeneration++;
    _activeRouteQuoteGeneration = null;
    _activeRouteDestinationGeneration = null;
    _pendingRouteFitQuoteGeneration = null;
    _cameraMovedByUserSinceRouteFit = false;
  }

  bool _isCurrentRouteFit({
    required int quoteGeneration,
    required int destinationGeneration,
  }) {
    return mounted &&
        quoteGeneration == _quoteRequestId &&
        destinationGeneration == _destinationGeneration &&
        quoteGeneration == _activeRouteQuoteGeneration &&
        destinationGeneration == _activeRouteDestinationGeneration &&
        _routePoints.length >= 2;
  }

  bool _isCurrentQuoteRequest({
    required int quoteGeneration,
    required int destinationGeneration,
  }) {
    return mounted &&
        quoteGeneration == _quoteRequestId &&
        destinationGeneration == _destinationGeneration;
  }

  /// Programa un único encuadre después de que el frame haya terminado.
  /// Si `_MeasureSize` detecta otra altura en ese mismo frame, incrementa
  /// [_routeFitScheduleGeneration] antes de que corra la microtask y este
  /// intento queda descartado. El callback nuevo se ejecutará en el frame
  /// siguiente, cuando `GoogleMap.padding` ya recibió la última medida.
  void _scheduleRouteFitAfterLayout({
    required int quoteGeneration,
    required int destinationGeneration,
  }) {
    if (!_isCurrentRouteFit(
      quoteGeneration: quoteGeneration,
      destinationGeneration: destinationGeneration,
    )) {
      return;
    }

    final scheduleGeneration = ++_routeFitScheduleGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (scheduleGeneration != _routeFitScheduleGeneration ||
            !_isCurrentRouteFit(
              quoteGeneration: quoteGeneration,
              destinationGeneration: destinationGeneration,
            )) {
          return;
        }

        final newQuoteStillNeedsFit =
            _pendingRouteFitQuoteGeneration == quoteGeneration;

        if (!newQuoteStillNeedsFit && _cameraMovedByUserSinceRouteFit) {
          return;
        }

        unawaited(
          _fitCameraToRoute(
            quoteGeneration: quoteGeneration,
            destinationGeneration: destinationGeneration,
          ),
        );
      });
    });
  }

  void _markCameraMovedByUser() {
    if (_activeRouteQuoteGeneration == null) {
      return;
    }

    _cameraUserMoveGeneration++;
    _cameraMovedByUserSinceRouteFit = true;

    // Una cotización nueva siempre conserva su encuadre pendiente. Para
    // una ruta ya encuadrada, el gesto del Passenger cancela cualquier
    // reajuste que hubiera quedado programado solo por cambios de altura.
    if (_pendingRouteFitQuoteGeneration == null) {
      _routeFitScheduleGeneration++;
    }
  }

  void _handleMapPointerDown(PointerDownEvent event) {
    _activeMapPointers.add(event.pointer);
  }

  void _handleMapPointerEnd(PointerEvent event) {
    _activeMapPointers.remove(event.pointer);
  }

  void _handleCameraMoveStarted() {
    if (_activeMapPointers.isNotEmpty) {
      _markCameraMovedByUser();
    }
  }

  Future<void> _recenterOnCurrentLocation() async {
    // El botón es una elección explícita de cámara del Passenger. Una
    // cotización futura podrá reencuadrar; un cambio aislado de hoja no.
    _markCameraMovedByUser();
    await _loadCurrentLocation();
  }

  final TextEditingController _passengerOfferController =
      TextEditingController();

  /// Nunca se escribe nada acá — `TukiSearchBar` de Home vacío es un
  /// disparador de navegación (`readOnly` + `onTap`), no un campo de
  /// texto real (`HOME-FLOW-R1`, etapa 3). El controller solo satisface
  /// el parámetro requerido del widget.
  final TextEditingController _searchTriggerController =
      TextEditingController();

  Timer? _quoteExpiryTimer;

  Position? _currentPosition;
  LatLng? _selectedDestination;

  /// ORIGIN-ADDRESS-R1: dirección real del origen, resuelta apenas
  /// hay GPS — independiente de la cotización. `null` mientras no se
  /// resolvió ninguna todavía (se sigue mostrando el placeholder
  /// existente 'Tu ubicación actual' en ese caso). Una vez resuelta,
  /// se conserva la última dirección válida aunque el GPS se mueva de
  /// nuevo — no parpadea a un estado "resolviendo" mientras llega la
  /// dirección para la nueva posición.
  String? _resolvedOriginAddress;

  /// Posición GPS para la que se resolvió [_resolvedOriginAddress].
  /// Permite decidir si una nueva posición cae dentro de
  /// [_originAddressCacheDistanceMeters] del último punto ya resuelto
  /// (mismo lugar: no vale la pena pagar otra llamada) o si el
  /// pasajero se movió lo suficiente como para pedir una dirección
  /// nueva.
  LatLng? _resolvedOriginAddressPosition;

  /// Generación de la última resolución de dirección de origen en
  /// vuelo — mismo propósito que [_quoteRequestId]: si el GPS se
  /// actualiza de nuevo (apertura + tap de "centrar en mi ubicación")
  /// mientras una resolución anterior todavía no responde, una
  /// respuesta tardía de esa llamada obsoleta no debe pisar el estado
  /// de la más reciente.
  int _originAddressRequestId = 0;

  /// Posición para la que hay una llamada a `fares/origin-address`
  /// REALMENTE en curso ahora mismo (disparada, sin responder
  /// todavía). Deliberadamente separada de
  /// [_resolvedOriginAddressPosition] (que solo se mueve en éxito):
  /// si se usara el mismo campo para ambas cosas, un fallo dejaría el
  /// cache de "ya resuelto" apuntando a un punto cuya dirección nunca
  /// se obtuvo, bloqueando reintentos futuros para ese mismo lugar.
  /// Se limpia al terminar la llamada, tanto en éxito como en fallo
  /// (ver [_originAddressInFlightRequestId], que decide si a ESTA
  /// llamada le corresponde limpiarla).
  LatLng? _originAddressInFlightPosition;

  /// [_originAddressRequestId] que "es dueño" de
  /// [_originAddressInFlightPosition] — evita que una llamada vieja,
  /// al terminar, borre por error el marcador "en vuelo" de una
  /// llamada más nueva para un punto distinto que ya lo reemplazó.
  int? _originAddressInFlightRequestId;

  String? _selectedDestinationAddress;
  String? _selectedDestinationName;

  /// true = el destino actual vino de tocar el mapa (nunca de
  /// autocomplete). Es la señal real que se manda a Backend como
  /// `destination.isManualSelection` (G4B-CONTRACT-R1) y la que esta
  /// misma pantalla usa para saber, cuando llega el FareQuote, si
  /// corresponde reemplazar la tarjeta por la dirección real que
  /// Backend ya resolvió — ya no se infiere comparando texto contra
  /// `_manualDestinationPlaceholder`.
  bool _destinationIsManualSelection = false;

  /// SUGGESTED-DESTINATIONS-R1: hasta [suggestedDestinationsCount]
  /// destinos frecuentes del historial del pasajero, ya calculados por
  /// `resolveSuggestedDestinations`. Vacía mientras carga o si el
  /// pasajero no tiene historial suficiente — en ambos casos la
  /// sección de sugerencias simplemente no se muestra, sin mensaje ni
  /// espacio reservado.
  List<RideHistoryItem> _suggestedDestinations = const [];

  /*
   * Puntos decodificados de la polyline
   * devuelta por Google Routes.
   */
  List<LatLng> _routePoints = const [];

  String? _locationMessage;

  bool _locating = false;
  bool _loading = false;
  bool _requestingRide = false;

  FareEstimate? _quote;

  /// Expone el id de la cotización vigente únicamente para tests
  /// (verificar cuál request "ganó" ante selecciones de destino
  /// concurrentes — G4B-R5.1). No se usa en producción.
  @visibleForTesting
  String? get debugQuoteId => _quote?.quoteId;

  /// Permite verificar que una medición tardía de cualquiera de los dos
  /// overlays reutiliza el programador único de reencuadre.
  @visibleForTesting
  int get debugRouteFitScheduleGeneration => _routeFitScheduleGeneration;

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

    // Independiente del GPS: no necesita _currentPosition para pedir
    // el historial. Se dispara una sola vez por apertura de Home.
    unawaited(_loadSuggestedDestinations());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_originMarkerIconLoadStarted) {
      return;
    }

    _originMarkerIconLoadStarted = true;
    unawaited(_loadOriginMarkerIcon());
  }

  Future<void> _loadOriginMarkerIcon() async {
    final configuration = createLocalImageConfiguration(context);
    final icon = await BitmapDescriptor.asset(
      configuration,
      _originMarkerAsset,
      width: _originMarkerLogicalSize.width,
      height: _originMarkerLogicalSize.height,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _originMarkerIcon = icon;
    });
  }

  @override
  void dispose() {
    _quoteExpiryTimer?.cancel();
    _passengerOfferController.dispose();
    _searchTriggerController.dispose();
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
  void _scheduleQuoteExpiryTimer(FareEstimate quote) {
    _cancelQuoteExpiryTimer();

    final duration = quote.expiresAt.difference(DateTime.now());

    if (duration <= Duration.zero) {
      if (mounted) {
        _estimateFare();
      }

      return;
    }

    _quoteExpiryTimer = Timer(duration, () {
      _quoteExpiryTimer = null;

      if (!mounted) {
        return;
      }

      _estimateFare();
    });
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
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }

        setState(() {
          _locationMessage = 'Activa la ubicación del dispositivo.';
        });

        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
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

      if (permission == LocationPermission.deniedForever) {
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
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

      // Fire-and-forget: nunca bloquea el movimiento de cámara ni el
      // resto de esta pantalla — ver `_resolveOriginAddress`.
      unawaited(_resolveOriginAddress(position));

      await _moveCameraToCurrentLocation();
    } catch (error) {
      debugPrint('Error obteniendo ubicación: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _locationMessage = 'No se pudo obtener tu ubicación.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  /// ORIGIN-ADDRESS-R1: resuelve la dirección real de [position] sin
  /// esperar a que el pasajero elija destino ni generar una
  /// cotización (`GET fares/origin-address`, liviano, sin persistir
  /// nada). Cachea por distancia: si [position] cae dentro de
  /// [_originAddressCacheDistanceMeters] de la última posición ya
  /// resuelta, no vuelve a llamar al backend. Tampoco dispara una
  /// llamada nueva si YA hay una en curso para prácticamente el mismo
  /// punto (taps repetidos de "centrar en mi ubicación" sin moverse no
  /// deben acumular llamadas a `fares/origin-address` — ver
  /// [_originAddressInFlightPosition]). Nunca bloquea ni muestra error
  /// si falla — la pantalla sigue mostrando el placeholder existente
  /// ('Tu ubicación actual') hasta que llegue la cotización real o una
  /// resolución futura tenga éxito.
  Future<void> _resolveOriginAddress(Position position) async {
    final newPoint = LatLng(position.latitude, position.longitude);

    final resolvedPoint = _resolvedOriginAddressPosition;

    if (resolvedPoint != null &&
        _originAddressDistanceMeters(resolvedPoint, newPoint) <=
            _originAddressCacheDistanceMeters) {
      return;
    }

    final inFlightPoint = _originAddressInFlightPosition;

    if (inFlightPoint != null &&
        _originAddressDistanceMeters(inFlightPoint, newPoint) <=
            _originAddressCacheDistanceMeters) {
      // Ya hay una resolución real en curso para prácticamente el
      // mismo punto — esa llamada, al terminar, ya va a actualizar
      // el estado. Disparar otra sería un duplicado innecesario.
      return;
    }

    final requestId = ++_originAddressRequestId;

    /*
     * Marca "en vuelo" AL INICIAR, no al recibir la respuesta —
     * si se marcara solo al final, dos taps casi simultáneos
     * pasarían ambos el chequeo de arriba antes de que cualquiera
     * termine. Deliberadamente en un campo separado de
     * `_resolvedOriginAddressPosition`: ese solo se mueve en éxito,
     * así que un fallo acá nunca deja el cache de "ya resuelto"
     * apuntando a un punto sin dirección real.
     */
    _originAddressInFlightPosition = newPoint;
    _originAddressInFlightRequestId = requestId;

    try {
      final address = await ref
          .read(fareRepositoryProvider)
          .getOriginAddress(
            latitude: position.latitude,
            longitude: position.longitude,
          );

      if (!mounted ||
          requestId != _originAddressRequestId ||
          address.trim().isEmpty) {
        return;
      }

      setState(() {
        _resolvedOriginAddress = address;
        _resolvedOriginAddressPosition = newPoint;
      });
    } catch (error) {
      debugPrint('Error resolviendo dirección de origen: $error');
    } finally {
      // Solo limpia si el marcador "en vuelo" sigue siendo el de ESTA
      // llamada — una llamada más nueva, para un punto distinto, ya
      // pudo haberlo reemplazado mientras esta seguía en curso.
      if (_originAddressInFlightRequestId == requestId) {
        _originAddressInFlightPosition = null;
        _originAddressInFlightRequestId = null;
      }
    }
  }

  /// Proyecta [_currentPosition] a coordenadas de pantalla (píxeles
  /// lógicos) y las guarda en [_originMarkerScreenOffset] — de ahí las
  /// lee [_buildOriginMarkerLabel] para dibujar la etiqueta justo
  /// encima del `Marker` real del origen. Se llama tanto desde
  /// `onCameraMove` (arrastre/gestos del Passenger) como al final de
  /// cada movimiento de cámara programático (recentrar, elegir
  /// destino, encuadrar la ruta) para garantizar una posición final
  /// correcta aunque el último evento de `onCameraMove` de una
  /// animación no alcance a llegar.
  ///
  /// Sin controller o sin posición todavía (incluido SIEMPRE en
  /// tests: `onMapCreated` nunca se dispara sin una vista de mapa
  /// real), no hace nada — [_originMarkerScreenOffset] se queda en
  /// `null` y [_buildOriginMarkerLabel] cae de vuelta a centrarse en
  /// el área libre, igual que antes de este cambio.
  Future<void> _updateOriginMarkerScreenOffset() async {
    final controller = _mapController;
    final position = _currentPosition;

    if (controller == null || position == null) {
      return;
    }

    final requestId = ++_originMarkerScreenOffsetRequestId;

    ScreenCoordinate screenCoordinate;

    try {
      screenCoordinate = await controller.getScreenCoordinate(
        LatLng(position.latitude, position.longitude),
      );
    } catch (error) {
      debugPrint('No se pudo proyectar el marcador propio: $error');
      return;
    }

    if (!mounted || requestId != _originMarkerScreenOffsetRequestId) {
      return;
    }

    setState(() {
      _originMarkerScreenOffset = Offset(
        screenCoordinate.x / _devicePixelRatio,
        screenCoordinate.y / _devicePixelRatio,
      );
    });
  }

  Future<void> _moveCameraToCurrentLocation() async {
    final controller = _mapController;
    final position = _currentPosition;

    if (controller == null || position == null) {
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 16,
        ),
      ),
    );

    await _updateOriginMarkerScreenOffset();
  }

  Future<void> _moveCameraToDestination(LatLng destination) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: destination, zoom: 17),
      ),
    );

    await _updateOriginMarkerScreenOffset();
  }

  Future<void> _fitCameraToRoute({
    required int quoteGeneration,
    required int destinationGeneration,
  }) async {
    if (!_isCurrentRouteFit(
      quoteGeneration: quoteGeneration,
      destinationGeneration: destinationGeneration,
    )) {
      return;
    }

    final controller = _mapController;

    if (controller == null) {
      return;
    }

    final routePoints = List<LatLng>.of(_routePoints);
    var minLatitude = routePoints.first.latitude;

    var maxLatitude = routePoints.first.latitude;

    var minLongitude = routePoints.first.longitude;

    var maxLongitude = routePoints.first.longitude;

    for (final point in routePoints) {
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
      minLatitude = min(minLatitude, position.latitude);

      maxLatitude = max(maxLatitude, position.latitude);

      minLongitude = min(minLongitude, position.longitude);

      maxLongitude = max(maxLongitude, position.longitude);
    }

    final destination = _selectedDestination;

    if (destination != null) {
      minLatitude = min(minLatitude, destination.latitude);

      maxLatitude = max(maxLatitude, destination.latitude);

      minLongitude = min(minLongitude, destination.longitude);

      maxLongitude = max(maxLongitude, destination.longitude);
    }

    if (!_isCurrentRouteFit(
      quoteGeneration: quoteGeneration,
      destinationGeneration: destinationGeneration,
    )) {
      return;
    }

    try {
      final userMoveGenerationBeforeFit = _cameraUserMoveGeneration;

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLatitude, minLongitude),
            northeast: LatLng(maxLatitude, maxLongitude),
          ),
          _routeBoundsPadding,
        ),
      );

      if (!_isCurrentRouteFit(
        quoteGeneration: quoteGeneration,
        destinationGeneration: destinationGeneration,
      )) {
        return;
      }

      if (_pendingRouteFitQuoteGeneration == quoteGeneration) {
        _pendingRouteFitQuoteGeneration = null;
      }

      _cameraMovedByUserSinceRouteFit =
          _cameraUserMoveGeneration != userMoveGenerationBeforeFit;
      await _updateOriginMarkerScreenOffset();
    } catch (error) {
      debugPrint('No se pudo ajustar la cámara a la ruta: $error');
    }
  }

  void _selectDestination(LatLng destination) {
    _cancelQuoteExpiryTimer();
    _advanceDestinationGeneration();

    setState(() {
      _selectedDestination = destination;

      _selectedDestinationName = 'Destino en el mapa';

      _selectedDestinationAddress = _manualDestinationPlaceholder;

      _destinationIsManualSelection = true;

      _quote = null;
      _routePoints = const [];
      _loading = false;
    });

    _maybeAutoEstimateFare();
  }

  void _clearDestination() {
    _cancelQuoteExpiryTimer();
    _advanceDestinationGeneration();

    setState(() {
      _selectedDestination = null;
      _selectedDestinationAddress = null;
      _selectedDestinationName = null;
      _destinationIsManualSelection = false;

      _quote = null;
      _routePoints = const [];
      _loading = false;
    });

    // Sin destino, la ruta encuadrada deja de existir — la cámara vuelve
    // al origen con el mismo zoom de entrada, reusando el mismo camino
    // que el botón de recentrar (ver `onMapCreated` y
    // `_recenterOnCurrentLocation`). `_advanceDestinationGeneration` de
    // arriba ya invalidó cualquier reencuadre pendiente y bajó
    // `_activeRouteQuoteGeneration` a null, así que no hay un ajuste
    // automático activo con el que este recentrado pueda pelear.
    unawaited(_moveCameraToCurrentLocation());
  }

  /// Abre `SearchDestinationScreen` (`HOME-FLOW-R1`, etapa 3) y aplica
  /// el resultado con el mismo camino que ya usaba
  /// `_selectPlacePrediction` antes de este checkpoint — la búsqueda en
  /// sí (autocompletado, debounce, `getDetails`) ahora vive
  /// completamente en esa pantalla, Home solo consume su resultado.
  Future<void> _openSearchDestination() async {
    final position = _currentPosition;

    if (position == null) {
      return;
    }

    final result = await Navigator.of(context).push<SearchDestinationResult>(
      MaterialPageRoute(
        builder: (_) => SearchDestinationScreen(
          originAddress: _originAddressLabel(_quote, position),
          originCoordinates: LatLng(position.latitude, position.longitude),
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    await _applySearchResult(result);
  }

  Future<void> _applySearchResult(SearchDestinationResult result) async {
    _cancelQuoteExpiryTimer();
    _advanceDestinationGeneration();

    setState(() {
      _selectedDestination = result.destination;

      _selectedDestinationName = result.name;

      _selectedDestinationAddress = result.address;

      _destinationIsManualSelection = false;

      _quote = null;
      _routePoints = const [];
      _loading = false;
    });

    await _moveCameraToDestination(result.destination);

    _maybeAutoEstimateFare();
  }

  /// SUGGESTED-DESTINATIONS-R1: pide el historial completado del
  /// pasajero una sola vez por apertura de Home y calcula las
  /// sugerencias con `resolveSuggestedDestinations`. Best-effort: un
  /// fallo de red no muestra error ni bloquea nada — la sección de
  /// sugerencias simplemente no aparece, mismo criterio que el resto
  /// de los enriquecimientos no críticos de esta pantalla (dirección
  /// de origen preemptiva).
  Future<void> _loadSuggestedDestinations() async {
    try {
      final history = await ref.read(rideRepositoryProvider).getHistory();

      if (!mounted) {
        return;
      }

      final suggestions = resolveSuggestedDestinations(history);

      if (suggestions.isEmpty) {
        return;
      }

      setState(() {
        _suggestedDestinations = suggestions;
      });
    } catch (error) {
      debugPrint('Error obteniendo destinos sugeridos: $error');
    }
  }

  /// SUGGESTED-DESTINATIONS-R1: mismo camino que `_applySearchResult`
  /// a partir de fijar el destino — pero sin las dos llamadas a
  /// Google (`autocomplete`+`getDetails`), porque [suggestion] ya trae
  /// coordenadas reales resueltas por Backend (`GET
  /// fares/origin-address` no interviene acá; esto es
  /// `destinationLatitude`/`destinationLongitude` del historial).
  Future<void> _selectSuggestedDestination(RideHistoryItem suggestion) async {
    final latitude = suggestion.destinationLatitude;
    final longitude = suggestion.destinationLongitude;

    if (latitude == null || longitude == null) {
      return;
    }

    final destination = LatLng(latitude, longitude);

    _cancelQuoteExpiryTimer();
    _advanceDestinationGeneration();

    setState(() {
      _selectedDestination = destination;

      _selectedDestinationName = suggestion.destinationAddress;

      _selectedDestinationAddress = suggestion.destinationAddress;

      _destinationIsManualSelection = false;

      _quote = null;
      _routePoints = const [];
      _loading = false;
    });

    await _moveCameraToDestination(destination);

    _maybeAutoEstimateFare();
  }

  /// HOME-LAYOUT-R1: el origen usa un `Marker` real de Google Maps con
  /// el asset definitivo, cargado y cacheado una sola vez, en vez del
  /// punto azul nativo (`myLocationEnabled` sigue en `false`, ver
  /// `build()`). La
  /// etiqueta con la dirección NO es parte de este `Marker` — Google
  /// Maps no permite anclarle overlays de Flutter — se dibuja aparte,
  /// posicionada a mano vía [_updateOriginMarkerScreenOffset] (ver
  /// [_buildOriginMarkerLabel]).
  Set<Marker> get _markers {
    final markers = <Marker>{};

    final position = _currentPosition;

    final originMarkerIcon = _originMarkerIcon;

    if (position != null && originMarkerIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(position.latitude, position.longitude),
          anchor: const Offset(0.5, 1),
          icon: originMarkerIcon,
        ),
      );
    }

    final destination = _selectedDestination;

    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),

          position: destination,

          infoWindow: InfoWindow(
            title: _selectedDestinationName ?? 'Destino',

            snippet: _selectedDestinationAddress ?? 'Destino seleccionado',
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
        polylineId: const PolylineId('fare-route'),

        points: _routePoints,

        width: 6,

        color: PassengerColors.lineaRuta,

        geodesic: false,

        zIndex: 10,
      ),
    };
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

  List<LatLng> _decodePolyline(String encoded) {
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

          byte = encoded.codeUnitAt(index++) - 63;

          result |= (byte & 0x1f) << shift;

          shift += 5;
        } while (byte >= 0x20);

        final latitudeDelta = (result & 1) != 0 ? ~(result >> 1) : result >> 1;

        latitude += latitudeDelta;

        result = 0;
        shift = 0;

        do {
          if (index >= encoded.length) {
            return const [];
          }

          byte = encoded.codeUnitAt(index++) - 63;

          result |= (byte & 0x1f) << shift;

          shift += 5;
        } while (byte >= 0x20);

        final longitudeDelta = (result & 1) != 0 ? ~(result >> 1) : result >> 1;

        longitude += longitudeDelta;

        points.add(LatLng(latitude / 1e5, longitude / 1e5));
      }
    } catch (error) {
      debugPrint('No se pudo decodificar la ruta: $error');

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
    final position = _currentPosition;

    final destination = _selectedDestination;

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no tenemos tu ubicación GPS.')),
      );

      return;
    }

    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Busca un destino o tócalo en el mapa.')),
      );

      return;
    }

    _cancelQuoteExpiryTimer();

    final destinationGeneration = _destinationGeneration;
    final requestId = ++_quoteRequestId;
    _invalidateRouteFit();

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
            originLatitude: position.latitude,

            originLongitude: position.longitude,

            destinationLatitude: destination.latitude,

            destinationLongitude: destination.longitude,

            destinationAddress:
                _selectedDestinationAddress ?? _manualDestinationPlaceholder,

            destinationIsManualSelection: _destinationIsManualSelection,
          );

      if (!_isCurrentQuoteRequest(
        quoteGeneration: requestId,
        destinationGeneration: destinationGeneration,
      )) {
        return;
      }

      final encodedPolyline = quote.routePolyline;

      final routePoints = encodedPolyline == null
          ? const <LatLng>[]
          : _decodePolyline(encodedPolyline);

      // G4B-R5.2 (señal desde G4B-CONTRACT-R1): si el destino vino de
      // un tap en el mapa (`_destinationIsManualSelection`), reemplaza
      // la tarjeta Home por la dirección real que Backend ya
      // resolvió — sin volver a pedir un FareQuote ni tocar
      // coordenadas. Ya no se infiere comparando `address` contra
      // `_manualDestinationPlaceholder`: un destino de autocomplete
      // nunca deja `_destinationIsManualSelection` en true, así que
      // este bloque nunca lo toca (no rompe "B" del checkpoint). Vive
      // DESPUÉS del check de `requestId` de arriba, así que una
      // respuesta obsoleta de un destino anterior jamás llega hasta
      // acá (protege Caso 4).
      final resolvedDestinationAddress = quote.destinationAddress.trim();

      final destinationAddressResolved =
          _destinationIsManualSelection &&
          resolvedDestinationAddress.isNotEmpty;

      setState(() {
        _quote = quote;
        _routePoints = routePoints;

        if (destinationAddressResolved) {
          _selectedDestinationName = resolvedDestinationAddress;
          _selectedDestinationAddress = null;
        }
      });

      _scheduleQuoteExpiryTimer(quote);

      if (routePoints.length >= 2) {
        _activeRouteQuoteGeneration = requestId;
        _activeRouteDestinationGeneration = destinationGeneration;
        _pendingRouteFitQuoteGeneration = requestId;
        _scheduleRouteFitAfterLayout(
          quoteGeneration: requestId,
          destinationGeneration: destinationGeneration,
        );
      }
    } on DioException catch (error) {
      if (!_isCurrentQuoteRequest(
        quoteGeneration: requestId,
        destinationGeneration: destinationGeneration,
      )) {
        return;
      }

      if (!mounted) {
        return;
      }

      final backendMessage = _backendMessage(error);

      String message = backendMessage ?? 'No se pudo calcular la tarifa.';

      if (error.response?.statusCode == 401 && backendMessage == null) {
        message = 'Tu sesión ya no es válida.';
      } else if (error.response?.statusCode == 503 && backendMessage == null) {
        message =
            'El servicio de rutas no está '
            'disponible en este momento.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar '
            'con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      debugPrint('Error calculando tarifa: $error');

      if (!_isCurrentQuoteRequest(
        quoteGeneration: requestId,
        destinationGeneration: destinationGeneration,
      )) {
        return;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocurrió un error inesperado.')),
      );
    } finally {
      if (_isCurrentQuoteRequest(
        quoteGeneration: requestId,
        destinationGeneration: destinationGeneration,
      )) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cotización venció. Actualizándola...'),
        ),
      );

      _estimateFare();

      return;
    }

    final rawOffer = _passengerOfferController.text.trim().replaceAll(',', '.');

    final passengerOffer = double.tryParse(rawOffer);

    if (passengerOffer == null ||
        !passengerOffer.isFinite ||
        passengerOffer <= 0 ||
        passengerOffer > 9999.99) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido para tu oferta.'),
        ),
      );

      return;
    }

    final decimalParts = rawOffer.split('.');

    if (decimalParts.length > 2 ||
        (decimalParts.length == 2 && decimalParts[1].length > 2)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La oferta puede tener como máximo '
            '2 decimales.',
          ),
        ),
      );

      return;
    }

    final normalizedPassengerOffer = normalizePassengerOfferFare(rawOffer);

    if (normalizedPassengerOffer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido para tu oferta.'),
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
            fareQuoteId: quote.quoteId,
            passengerOfferFare: normalizedPassengerOffer,
          );

      if (!mounted) {
        return;
      }

      context.go('/ride/${ride.id}');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final backendMessage = _backendMessage(error);

      String message = backendMessage ?? 'No se pudo solicitar el viaje.';

      if (error.response?.statusCode == 400 && backendMessage == null) {
        message =
            'La cotización venció. '
            'Calcula una nueva tarifa.';
      } else if (error.response?.statusCode == 409 && backendMessage == null) {
        message = 'Ya tienes un viaje activo.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar '
            'con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _requestingRide = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  bool _isQuoteExpired(FareEstimate quote) {
    return !quote.expiresAt.isAfter(DateTime.now());
  }

  String _formatQuoteExpiry(DateTime expiresAt) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(expiresAt.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  /// Sin ícono a propósito (`HOME-DESIGN-R1`, análisis de contraste,
  /// 2026-08-26): el ícono decorativo que tenía antes usaba `acento`
  /// sobre `verdeMarca`/el overlay translúcido del chip — 2.33:1 (peor
  /// aún, 1.61:1 contra el fondo compuesto real), por debajo del
  /// mínimo de 3:1 para elementos gráficos. El texto ya dice todo lo
  /// que el ícono aportaba (distancia/duración), así que se quita en
  /// vez de recolorearlo.
  Widget _buildMetricChip({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: PassengerColors.blanco,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// SUGGESTED-DESTINATIONS-R1, formato lista vertical desde
  /// `HOME-FLOW-R1` (etapa 3) — reemplaza la pastilla horizontal
  /// original: verificado en emulador que los chips truncaban la
  /// dirección y de todas formas terminaban apilados verticalmente en
  /// la práctica, así que el formato de chip no aportaba nada sobre
  /// una lista. Sin `ConstrainedBox`/`maxWidth` artificial — el nombre
  /// se ve completo salvo que realmente no entre en una línea.
  /// Deshabilitada (sin `onTap`, atenuada) mientras no hay GPS — mismo
  /// motivo que la pastilla original: tocarla antes fijaría el destino
  /// igual, pero `_maybeAutoEstimateFare` no dispara la cotización
  /// hasta tener origen.
  Widget _buildSuggestedDestinationRow(
    RideHistoryItem suggestion, {
    required bool enabled,
  }) {
    return InkWell(
      key: ValueKey('suggested-destination-${suggestion.rideId}'),
      onTap: enabled ? () => _selectSuggestedDestination(suggestion) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 20,
                color: PassengerColors.destino,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  suggestion.destinationAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PassengerColors.textoPrimario,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final position = _currentPosition;
    final destination = _selectedDestination;

    final canEstimate =
        position != null &&
        destination != null &&
        !_loading &&
        !_requestingRide;

    final quoteExpired = quote != null && _isQuoteExpired(quote);

    final hasValidOffer =
        normalizePassengerOfferFare(_passengerOfferController.text) != null;

    final canRequestRide =
        destination != null &&
        quote != null &&
        !quoteExpired &&
        hasValidOffer &&
        !_loading &&
        !_requestingRide;

    final mediaQuery = MediaQuery.of(context);
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
    final statusBarInset = mediaQuery.viewPadding.top;
    _devicePixelRatio = mediaQuery.devicePixelRatio;

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
      ctaOnPressed = canEstimate ? _estimateFare : null;
      ctaIcon = Icons.refresh;
    } else {
      ctaLabel = 'Ofrecer y buscar conductor';
      ctaOnPressed = canRequestRide ? _requestRide : null;
      // G4B-R5: sin icono de moto en este CTA.
      ctaIcon = null;
    }

    final ctaShowsProgress = _loading || _requestingRide;
    final ctaButtonStyle = FilledButton.styleFrom(
      backgroundColor: PassengerColors.amarilloCTA,
      foregroundColor: PassengerColors.verdeMarca,
      disabledBackgroundColor: PassengerColors.bordeSuave,
      disabledForegroundColor: PassengerColors.textoSecundario,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: PassengerColors.verdeMarca,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: PassengerColors.crema,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            SizedBox(
              key: const ValueKey('home-status-bar-background'),
              width: double.infinity,
              height: statusBarInset,
              child: const ColoredBox(color: PassengerColors.verdeMarca),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // PopScope no necesita envolver visualmente el Stack:
                      // al estar montado bajo la misma ModalRoute registra
                      // el callback de back, y el hijo vacío no participa del
                      // layout ni de los gestos sobre el mapa.
                      Positioned(
                        top: 0,
                        left: 0,
                        width: 0,
                        height: 0,
                        child: PopScope(
                          canPop: destination == null,
                          onPopInvokedWithResult: (didPop, _) {
                            if (!didPop && _selectedDestination != null) {
                              _clearDestination();
                            }
                          },
                          child: const SizedBox.shrink(),
                        ),
                      ),
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _handleMapPointerDown,
                          onPointerUp: _handleMapPointerEnd,
                          onPointerCancel: _handleMapPointerEnd,
                          child: GoogleMap(
                            initialCameraPosition: const CameraPosition(
                              target: _tarapotoCenter,
                              zoom: 14.5,
                            ),

                            /*
                   * Marcador real del origen (ver [_markers]) +
                   * marcador del destino, cuando hay uno elegido.
                   */
                            markers: _markers,

                            polylines: _polylines,

                            /*
                   * La hoja tapa la mitad inferior de la pantalla —
                   * sin este padding, Google Maps centra la cámara en
                   * el centro geométrico de la pantalla COMPLETA, que
                   * queda debajo de la hoja. Con el padding, `target`
                   * en `animateCamera`/`newLatLngBounds` se centra en
                   * el área realmente visible, la misma que usa el
                   * marcador propio (ver `_bottomOverlayHeight`).
                   */
                            padding: EdgeInsets.only(
                              top: _topOverlayHeight,
                              bottom: _bottomOverlayHeight,
                            ),

                            /*
                   * El origen ya no se representa con el punto azul
                   * nativo de Google Maps — lo reemplaza el `Marker`
                   * real que agrega [_markers].
                   */
                            myLocationEnabled: false,

                            myLocationButtonEnabled: false,

                            zoomControlsEnabled: false,

                            compassEnabled: true,

                            mapToolbarEnabled: false,

                            scrollGesturesEnabled: true,

                            zoomGesturesEnabled: true,

                            rotateGesturesEnabled: true,

                            tiltGesturesEnabled: true,

                            gestureRecognizers:
                                <Factory<OneSequenceGestureRecognizer>>{
                                  Factory<OneSequenceGestureRecognizer>(
                                    () => EagerGestureRecognizer(),
                                  ),
                                },

                            onMapCreated: (controller) {
                              _mapController = controller;

                              final quoteGeneration =
                                  _activeRouteQuoteGeneration;
                              final destinationGeneration =
                                  _activeRouteDestinationGeneration;

                              if (quoteGeneration != null &&
                                  destinationGeneration != null) {
                                _scheduleRouteFitAfterLayout(
                                  quoteGeneration: quoteGeneration,
                                  destinationGeneration: destinationGeneration,
                                );
                              } else {
                                unawaited(_moveCameraToCurrentLocation());
                              }
                            },

                            // Recalcula dónde cae en pantalla el `Marker` del
                            // origen en CADA movimiento de cámara, incluido el
                            // arrastre manual del Passenger — es la única forma
                            // de mantener la etiqueta (un widget de Flutter,
                            // ver [_buildOriginMarkerLabel]) pegada a un
                            // `Marker` nativo que Flutter no controla frame a
                            // frame. Puede quedar levemente desfasada MIENTRAS
                            // se arrastra (aceptado a propósito).
                            onCameraMoveStarted: _handleCameraMoveStarted,
                            onCameraMove: (_) =>
                                _updateOriginMarkerScreenOffset(),

                            onTap: _selectDestination,
                          ),
                        ),
                      ),

                      // Etiqueta del origen: se muestra solo mientras no hay
                      // destino. Después es redundante con la tarjeta de la hoja
                      // y puede tapar el pin de destino al encuadrar la ruta.
                      // Sin una proyección real todavía
                      // ([_originMarkerScreenOffset] == null: arranque, o
                      // SIEMPRE en tests), cae de vuelta a centrarse en el ÁREA
                      // VISIBLE del mapa. `IgnorePointer` en ambos casos para
                      // que un tap sobre ella siga llegando al mapa.
                      if (destination == null &&
                          _originMarkerScreenOffset == null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: _bottomOverlayHeight,
                          child: Align(
                            alignment: Alignment.center,
                            child: IgnorePointer(
                              // Cuando la hoja crece cerca de su tope, el área
                              // libre arriba puede quedar más chica que el
                              // alto natural de la etiqueta (pantallas bajas,
                              // teclado abierto). `FittedBox` lo achica para
                              // que quepa en vez de desbordar.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _buildOriginMarkerLabel(quote, position),
                              ),
                            ),
                          ),
                        )
                      else if (destination == null &&
                          _originMarkerScreenOffset!.dx >= 0 &&
                          _originMarkerScreenOffset!.dx <=
                              constraints.maxWidth &&
                          _originMarkerScreenOffset!.dy >= 0 &&
                          _originMarkerScreenOffset!.dy <=
                              constraints.maxHeight)
                        Positioned(
                          // La proyección apunta a la PUNTA del Marker (su
                          // ancla, ver anchor en [_markers]). El descriptor y
                          // este cálculo leen la misma altura lógica; el espacio
                          // adicional evita que la colita toque el asset.
                          left: _originMarkerScreenOffset!.dx,
                          top:
                              _originMarkerScreenOffset!.dy -
                              _originMarkerLogicalSize.height -
                              _originMarkerLabelGap,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -1),
                            child: IgnorePointer(
                              child: _buildOriginMarkerLabel(quote, position),
                            ),
                          ),
                        ),

                      // Menú + tarjeta como un único overlay superior medido.
                      // El padding interno conserva exactamente la posición
                      // histórica del menú; la tarjeta aparece debajo, con el
                      // margen lateral de 20 del sistema de diseño.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _MeasureSize(
                          onChange: _handleTopOverlaySizeChanged,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: _buildMenuButton(),
                                  ),
                                ),
                                if (destination != null) ...[
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: _buildOriginDestinationCard(
                                      position: position,
                                      destination: destination,
                                      quote: quote,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Botón de recentrar + hoja inferior, anclados juntos al
                      // fondo del Stack dentro del mismo Column: cuando la
                      // hoja crece o se encoge, este Column reacomoda el
                      // botón con ella — sin medir su alto a mano. El
                      // `_MeasureSize` que lo envuelve SÍ mide este bloque
                      // completo (botón + hoja), porque ese es el alto que
                      // necesitan tanto el marcador como `GoogleMap.padding`
                      // para saber cuánta pantalla, desde abajo, está tapada.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _MeasureSize(
                          onChange: _handleBottomOverlaySizeChanged,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 16,
                                  bottom: 14,
                                ),
                                child: _buildRecenterButton(),
                              ),
                              _buildSheet(
                                // El bloque inferior completo incluye 40 px
                                // del FAB pequeño + 14 px de separación. La
                                // hoja usa solo el espacio que queda debajo
                                // del overlay superior medido, para que ambos
                                // bloques nunca se tapen en pantallas bajas.
                                maxHeight: keyboardVisible
                                    // Con teclado, la prioridad es conservar
                                    // visible el CTA y permitir que la región
                                    // central del panel haga scroll. El mapa
                                    // queda temporalmente en segundo plano.
                                    ? constraints.maxHeight * 0.75
                                    : min(
                                        constraints.maxHeight * 0.75,
                                        max(
                                          0,
                                          constraints.maxHeight -
                                              _topOverlayHeight -
                                              54,
                                        ),
                                      ),
                                keyboardVisible: keyboardVisible,
                                position: position,
                                destination: destination,
                                quote: quote,
                                quoteExpired: quoteExpired,
                                ctaLabel: ctaLabel,
                                ctaOnPressed: ctaOnPressed,
                                ctaIcon: ctaIcon,
                                ctaShowsProgress: ctaShowsProgress,
                                ctaButtonStyle: ctaButtonStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Etiqueta del origen: la cotización real siempre gana sobre la
  /// resuelta preemptivamente (ORIGIN-ADDRESS-R1), y ambas ganan sobre
  /// los placeholders de "todavía no hay nada". Compartida entre el
  /// marcador flotante y la tarjeta origen/destino de la hoja para no
  /// duplicar este orden de prioridad en dos lugares.
  String _originAddressLabel(FareEstimate? quote, Position? position) {
    if (quote != null && quote.originAddress.trim().isNotEmpty) {
      return quote.originAddress;
    }

    if (_resolvedOriginAddress != null) {
      return _resolvedOriginAddress!;
    }

    return position == null ? 'Esperando GPS...' : 'Tu ubicación actual';
  }

  /// HOME-LAYOUT-R1: versión corta de [_originAddressLabel], SOLO para
  /// la etiqueta del marcador flotante (la tarjeta origen/destino de
  /// la hoja sigue mostrando la dirección completa).
  ///
  /// Heurística — nos quedamos con lo que hay antes de la primera
  /// coma. Es frágil a propósito documentada, no una solución robusta:
  /// depende de que el backend siga devolviendo
  /// `"calle y número, distrito/ciudad, código postal, país"` (el
  /// formato de `formatted_address` de Google Geocoding para
  /// direcciones de Perú). Investigado (2026-08-25): el backend hoy
  /// SOLO expone ese string completo — el tipo `GoogleGeocodingResponse`
  /// de `google-geocoding.service.ts` (tukituki-backend) descarta el
  /// array `address_components` que Google sí devuelve (con
  /// `street_number`/`route` ya separados), y no hay ningún campo
  /// corto en `OriginAddressResponseDto` ni en
  /// `FareQuoteLocationResponseDto`. Agregar ese campo en el backend es
  /// la solución correcta a futuro (ver `App-passenger/decisiones.md`
  /// para el detalle del costo estimado) — fuera de alcance de esta
  /// tarea, que es solo el layout de esta pantalla.
  ///
  /// Formatos que esta heurística rompe hoy: cualquier dirección sin
  /// coma (la deja tal cual, sin acortar — ver el `commaIndex <= 0` de
  /// abajo); una dirección donde la calle/número en sí contenga una
  /// coma antes del punto que el usuario esperaría cortar (p. ej. un
  /// interior/departamento tipo `"Jr. Lima 250, Int. 4, Tarapoto..."`
  /// se corta en `"Jr. Lima 250"`, que en este caso sí es lo deseado,
  /// pero no hay garantía de que Google mantenga siempre esa forma); y
  /// direcciones fuera de Perú con otro orden de componentes (esta app
  /// no opera fuera de Tarapoto hoy, así que no es un caso real todavía).
  String _shortAddressLabel(String address) {
    final trimmed = address.trim();
    final commaIndex = trimmed.indexOf(',');

    if (commaIndex <= 0) {
      return trimmed;
    }

    return trimmed.substring(0, commaIndex).trim();
  }

  /// Etiqueta del marcador propio del origen. El ícono ya NO es parte
  /// de este widget — es el `Marker` real que agrega [_markers]; este
  /// método solo dibuja la píldora con la dirección y la punta
  /// triangular que la conecta visualmente con ese `Marker` (ver el
  /// comentario sobre la proyección de la etiqueta en `build()`).
  Widget _buildOriginMarkerLabel(FareEstimate? quote, Position? position) {
    final address = _shortAddressLabel(_originAddressLabel(quote, position));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: PassengerColors.verdeMarca,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 11,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TE RECOGEMOS EN',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: PassengerColors.textoTenueSobreOscuro,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: PassengerColors.blanco,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // HOME-DESIGN-R1: blanco, no acento (2.33:1 sobre
              // verdeMarca, no pasaba el mínimo de 3:1) — no es
              // decorativo, es el afordance de que la etiqueta se
              // puede tocar para ajustar el punto de recogida.
              const Icon(
                Icons.chevron_right,
                size: 15,
                color: PassengerColors.blanco,
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(12, 6),
          painter: _MarkerPointerPainter(color: PassengerColors.verdeMarca),
        ),
      ],
    );
  }

  /// Botón de menú, flotando arriba a la izquierda sobre el mapa. Por
  /// ahora conserva la acción que ya existía en la AppBar (cerrar
  /// sesión) — el menú lateral real es otra tarea.
  Widget _buildMenuButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: PassengerColors.blanco,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 9,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        tooltip: 'Cerrar sesión',
        onPressed: _logout,
        padding: EdgeInsets.zero,
        color: PassengerColors.textoPrimario,
        icon: const Icon(Icons.menu),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return FloatingActionButton.small(
      heroTag: 'passenger-location',
      tooltip: 'Centrar en mi ubicación',
      backgroundColor: PassengerColors.amarilloCTA,
      foregroundColor: PassengerColors.verdeMarca,
      disabledElevation: 0,
      onPressed: _locating ? null : _recenterOnCurrentLocation,
      child: _locating
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PassengerColors.verdeMarca,
              ),
            )
          : const Icon(Icons.my_location),
    );
  }

  /// Hoja inferior: mide lo que su contenido necesita hasta [maxHeight]
  /// — a partir de ahí, solo la región del medio (título/buscador/
  /// sugerencias, o tarjeta origen-destino/oferta) hace scroll interno
  /// vía [Flexible] + [SingleChildScrollView] con restricciones
  /// sueltas. El CTA queda deliberadamente FUERA de esa región
  /// scrolleable, como último hijo no-flexible del Column: así el
  /// Column siempre le reserva su alto primero, y por construcción
  /// nunca hace falta scrollear para alcanzarlo — misma garantía que
  /// daba `bottomNavigationBar` antes de este cambio, ahora dentro de
  /// la hoja.
  Widget _buildSheet({
    required double maxHeight,
    required bool keyboardVisible,
    required Position? position,
    required LatLng? destination,
    required FareEstimate? quote,
    required bool quoteExpired,
    required String ctaLabel,
    required VoidCallback? ctaOnPressed,
    required IconData? ctaIcon,
    required bool ctaShowsProgress,
    required ButtonStyle ctaButtonStyle,
  }) {
    return ConstrainedBox(
      key: const ValueKey('home-bottom-sheet'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: PassengerColors.crema,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: PassengerColors.bordeSuave,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: destination == null
                    ? _buildEmptySheetContent(position: position)
                    : _buildSheetContent(
                        quote: quote,
                        quoteExpired: quoteExpired,
                      ),
              ),
            ),
            // HOME-FLOW-R1 (etapa 3): sin destino no hay footer de CTA
            // — "Selecciona un destino" no existía para hacer nada más
            // que ocupar espacio deshabilitado. Home vacío no tiene
            // ningún CTA que mostrar todavía.
            if (destination != null)
              _buildCtaFooter(
                keyboardVisible: keyboardVisible,
                ctaLabel: ctaLabel,
                ctaOnPressed: ctaOnPressed,
                ctaIcon: ctaIcon,
                ctaShowsProgress: ctaShowsProgress,
                ctaButtonStyle: ctaButtonStyle,
              ),
          ],
        ),
      ),
    );
  }

  /// Contenido de la hoja de Home vacío (`HOME-FLOW-R1`, etapa 3): solo
  /// título, disparador de búsqueda y sugeridos — sin tarjeta
  /// origen/destino (se muda arriba en la etapa 4) y sin CTA (ver
  /// `_buildSheet`).
  Widget _buildEmptySheetContent({required Position? position}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '¿A dónde vamos?',
          style: TextStyle(
            color: PassengerColors.verdeMarca,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),

        const SizedBox(height: 10),

        if (_locationMessage != null)
          Container(
            decoration: BoxDecoration(
              color: PassengerColors.fondoAviso,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: PassengerColors.aviso.withValues(alpha: 0.22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.location_off, color: PassengerColors.aviso),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _locationMessage!,
                      style: const TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Disparador de navegación, no campo editable — toca y abre
        // `SearchDestinationScreen`. Nunca escribe nada acá (ver
        // doc-comment de `TukiSearchBar.onTap`).
        TukiSearchBar(
          key: const ValueKey('home-search-trigger'),
          controller: _searchTriggerController,
          hintText: 'Buscar destino',
          enabled: position != null,
          readOnly: true,
          onTap: _openSearchDestination,
        ),

        if (_suggestedDestinations.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            key: const ValueKey('suggested-destinations-list'),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < _suggestedDestinations.length;
                  index++
                ) ...[
                  _buildSuggestedDestinationRow(
                    _suggestedDestinations[index],
                    enabled: position != null,
                  ),
                  if (index != _suggestedDestinations.length - 1)
                    const Divider(height: 1, color: PassengerColors.bordeSuave),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSheetContent({
    required FareEstimate? quote,
    required bool quoteExpired,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quote != null) ...[
          Container(
            decoration: BoxDecoration(
              color: PassengerColors.verdeMarca,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: PassengerColors.verdeMarca.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '¿Cuánto quieres ofrecer?',
                    style: TextStyle(
                      color: PassengerColors.blanco,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextField(
                    key: const ValueKey('passenger-offer-field'),
                    controller: _passengerOfferController,
                    enabled: !_requestingRide,
                    onChanged: (_) {
                      setState(() {});
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PassengerColors.textoPrimario,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      prefixText: 'S/ ',
                      prefixStyle: const TextStyle(
                        color: PassengerColors.textoSecundario,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                      hintText: '5.00',
                      filled: true,
                      fillColor: PassengerColors.crema,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: PassengerColors.acento,
                          width: 2,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      helperText: 'Este es el monto que verán los conductores.',
                      helperStyle: const TextStyle(
                        color: PassengerColors.textoSecundarioSobreOscuro,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _buildMetricChip(
                        label:
                            '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km',
                      ),
                      _buildMetricChip(
                        label: '${(quote.durationSeconds / 60).round()} min',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // HOME-DESIGN-R1: sin ícono de reloj (análisis de
                  // contraste, 2026-08-26) — el texto ya dice
                  // "vigente"/"vencida" sin ambigüedad, y el ícono
                  // usaba `aviso` sobre `verdeMarca` (2.90:1, no
                  // pasaba ni el mínimo de 3:1 de ícono ni el 4.5:1 de
                  // texto). El texto de "vencida" pasa a
                  // `textoSecundarioSobreOscuro` por la misma razón —
                  // `aviso` deja de usarse sobre fondo oscuro.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          quoteExpired
                              ? 'Cotización vencida'
                              : 'Cotización válida hasta '
                                    '${_formatQuoteExpiry(quote.expiresAt)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: PassengerColors.textoSecundarioSobreOscuro,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
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

        if (quote != null) const SizedBox(height: 20),
      ],
    );
  }

  /// Tarjeta origen/destino flotante sobre el mapa (`HOME-FLOW-R1`,
  /// etapa 4). Su estilo interno permanece igual al de la hoja anterior;
  /// el `_MeasureSize` superior detecta cualquier variación de alto,
  /// incluida la llegada asíncrona de la dirección del origen.
  Widget _buildOriginDestinationCard({
    required Position? position,
    required LatLng? destination,
    required FareEstimate? quote,
  }) {
    return Container(
      key: const ValueKey('origin-destination-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PassengerColors.crema,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: PassengerColors.bordeSuave),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Origen',
                      style: TextStyle(
                        color: PassengerColors.textoSecundario,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _originAddressLabel(quote, position),
                      style: const TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 2,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: PassengerColors.bordeSuave,
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                color: PassengerColors.destino,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Destino',
                      style: TextStyle(
                        color: PassengerColors.textoSecundario,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      destination == null
                          ? 'Selecciona un destino'
                          : _selectedDestinationName ?? 'Destino seleccionado',
                      style: const TextStyle(
                        color: PassengerColors.textoPrimario,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (destination != null &&
                        _selectedDestinationAddress != null &&
                        _selectedDestinationAddress!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _selectedDestinationAddress!,
                        style: const TextStyle(
                          color: PassengerColors.textoSecundario,
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
                  onPressed: _clearDestination,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    color: PassengerColors.textoSecundario,
                    size: 20,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// CTA: deliberadamente FUERA del `SingleChildScrollView` de
  /// [_buildSheet] — ver el comentario de ese método. Siempre visible
  /// sin scrollear, incluso con la hoja en su estado más alto y el
  /// teclado abierto (cubierto por el test "CTA es alcanzable con
  /// teclado..." en `home_screen_test.dart`).
  Widget _buildCtaFooter({
    required bool keyboardVisible,
    required String ctaLabel,
    required VoidCallback? ctaOnPressed,
    required IconData? ctaIcon,
    required bool ctaShowsProgress,
    required ButtonStyle ctaButtonStyle,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: PassengerColors.crema,
        border: Border(top: BorderSide(color: PassengerColors.bordeSuave)),
      ),
      child: SafeArea(
        top: false,
        bottom: !keyboardVisible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PassengerColors.verdeMarca,
                            ),
                          )
                        : Icon(ctaIcon),
                    label: Text(ctaLabel),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Triangulito que conecta la etiqueta del marcador propio con el
/// `Marker` real del origen — ver `_buildOriginMarkerLabel`.
class _MarkerPointerPainter extends CustomPainter {
  const _MarkerPointerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MarkerPointerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Mide el alto real (post-layout) de [child] y lo reporta vía
/// [onChange] — HOME-LAYOUT-R1 lo usa para enterarse de cuánto mide el
/// bloque recentrar+hoja sin adivinarlo, ya que ese valor alimenta
/// tanto la posición del marcador propio como `GoogleMap.padding` (ver
/// el comentario en `build()`). El reporte se difiere a
/// `addPostFrameCallback` porque `performLayout` corre DURANTE el
/// layout — llamar `setState` ahí mismo (en vez de después de este
/// frame) dispararía "setState() or markNeedsBuild() called during
/// build".
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget child})
    : super(child: child);

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastReportedSize;

  @override
  void performLayout() {
    super.performLayout();

    final newSize = size;

    if (_lastReportedSize == newSize) {
      return;
    }

    _lastReportedSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}

/// Distancia en metros entre dos puntos GPS (fórmula de Haversine).
/// Deliberadamente duplicada de `_driverMarkerDistanceMeters`
/// (`ride_searching_screen.dart`, R4.4B) en vez de extraída a un
/// util compartido — evita tocar ese código ya aprobado físicamente
/// para una tarea (ORIGIN-ADDRESS-R1) que no necesita modificarlo.
/// Sin dependencia nueva (`geolocator` no expone esto), mismo
/// criterio que R4.4B.
double _originAddressDistanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371000.0;

  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final deltaLat = (b.latitude - a.latitude) * pi / 180;
  final deltaLng = (b.longitude - a.longitude) * pi / 180;

  final h =
      sin(deltaLat / 2) * sin(deltaLat / 2) +
      cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
  final c = 2 * atan2(sqrt(h), sqrt(1 - h));

  return earthRadiusMeters * c;
}
