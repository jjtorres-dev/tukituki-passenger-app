import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/ride_repository.dart';
import '../domain/assigned_driver.dart';
import '../domain/driver_location.dart';
import '../domain/fare_amount.dart';
import '../domain/passenger_ride.dart';
import '../domain/passenger_ride_offer.dart';
import '../domain/passenger_ride_start_code.dart';
import '../domain/ride_offer_filter.dart';

class RideSearchingScreen extends ConsumerStatefulWidget {
  const RideSearchingScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideSearchingScreen> createState() =>
      _RideSearchingScreenState();
}

class _RideSearchingScreenState extends ConsumerState<RideSearchingScreen>
    with SingleTickerProviderStateMixin {
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _cream = Color(0xFFFFF9EC);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _softBorder = Color(0xFFEFE8D4);
  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF6F7E72);
  static const Color _destinationColor = Color(0xFFD8542C);

  PassengerRide? _ride;
  PassengerRideStartCode? _startCode;

  List<PassengerRideOffer> _offers = const [];

  Timer? _timer;
  late final AnimationController _radarController;

  bool _loading = true;
  bool _loadingRide = false;
  bool _loadingStartCode = false;
  bool _loadingOffers = false;
  bool _navigatingAway = false;
  bool _canceling = false;

  int _stateGeneration = 0;

  String? _selectingOfferId;
  String? _error;
  String? _startCodeError;

  bool _assignedAcknowledged = false;

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _loadRide();

    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadRide());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _loadRide() async {
    if (_navigatingAway ||
        _loadingRide ||
        _canceling ||
        _selectingOfferId != null) {
      return;
    }

    final requestGeneration = _stateGeneration;
    _loadingRide = true;

    try {
      final repository = ref.read(rideRepositoryProvider);

      // Primero consultamos el viaje activo real.
      // Si ya terminó, active puede devolver 404,
      // por eso luego consultamos el viaje por ID.
      final activeRide = await repository.getActiveRide();

      if (!_canApplyGeneration(requestGeneration)) {
        return;
      }

      PassengerRide ride;

      if (activeRide != null) {
        ride = activeRide;
      } else {
        ride = await repository.getRide(widget.rideId);
      }

      if (!_canApplyGeneration(requestGeneration)) {
        return;
      }

      setState(() {
        _ride = ride;
        _loading = false;
        _error = null;
      });

      if (ride.status == 'SEARCHING_DRIVER') {
        await _loadRideOffers(ride.id, generation: requestGeneration);
      } else if (_offers.isNotEmpty) {
        setState(() {
          _offers = const [];
        });
      }

      if (!_canApplyGeneration(requestGeneration)) {
        return;
      }

      // IMPORTANTE:
      // Si el backend ya marcó el viaje
      // como COMPLETED, dejamos de hacer polling
      // y vamos directamente al recibo.
      if (ride.status == 'COMPLETED') {
        _timer?.cancel();

        if (!mounted || _navigatingAway) {
          return;
        }

        _navigatingAway = true;

        context.go('/ride/${ride.id}/receipt');

        return;
      }

      // Si el conductor ya llegó,
      // obtenemos automáticamente
      // el código de inicio.
      if (ride.status == 'DRIVER_ARRIVED' &&
          _startCode == null &&
          !_loadingStartCode) {
        await _loadStartCodeForRide(ride.id);
      }

      // Cuando el viaje ya empezó,
      // dejamos de mostrar el código.
      if (ride.status == 'IN_PROGRESS' && _startCode != null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _startCode = null;
        });
      }

      // CANCELLED y EXPIRED ya no necesitan polling.
      if (_isFinalStatus(ride.status)) {
        _timer?.cancel();
      }
    } catch (error) {
      debugPrint('Error actualizando viaje del pasajero: $error');

      if (!_canApplyGeneration(requestGeneration)) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'No se pudo actualizar el viaje.';
      });
    } finally {
      _loadingRide = false;
    }
  }

  bool _canApplyGeneration(int generation) {
    return mounted && !_navigatingAway && generation == _stateGeneration;
  }

  Future<void> _loadRideOffers(String rideId, {required int generation}) async {
    if (_loadingOffers ||
        _navigatingAway ||
        _canceling ||
        _selectingOfferId != null) {
      return;
    }

    _loadingOffers = true;

    try {
      final offers = await ref
          .read(rideRepositoryProvider)
          .getRideOffers(rideId);

      if (!_canApplyGeneration(generation) ||
          _canceling ||
          _selectingOfferId != null ||
          _ride?.id != rideId ||
          _ride?.status != 'SEARCHING_DRIVER') {
        return;
      }

      setState(() {
        _offers = visibleRideOffers(offers);
      });
    } on DioException catch (error) {
      debugPrint(
        'PASSENGER OFFERS ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      final statusCode = error.response?.statusCode;

      if ((statusCode == 404 || statusCode == 409) &&
          _canApplyGeneration(generation)) {
        setState(() {
          _offers = const [];
        });
      } else if (statusCode != 409 &&
          statusCode != 404 &&
          _canApplyGeneration(generation)) {
        setState(() {
          _error =
              'No se pudieron actualizar '
              'las propuestas de conductores.';
        });
      }
    } catch (error) {
      debugPrint('PASSENGER OFFERS ERROR inesperado: $error');
    } finally {
      _loadingOffers = false;
    }
  }

  Future<void> _selectOffer(PassengerRideOffer offer) async {
    if (_selectingOfferId != null || _canceling || _navigatingAway) {
      return;
    }

    final currentRide = _ride;
    final currentRideId = currentRide?.id.trim();

    if (currentRideId == null ||
        currentRideId.isEmpty ||
        offer.rideId.trim().isEmpty ||
        offer.rideId != currentRideId) {
      debugPrint(
        'PASSENGER SELECT OFFER RIDE ID MISMATCH '
        'rideId=$currentRideId '
        'offerRideId=${offer.rideId}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta propuesta no corresponde '
            'al viaje actual.',
          ),
        ),
      );

      return;
    }

    final expiresAt = offer.expiresAt;

    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      setState(() {
        _offers = visibleRideOffers(_offers);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta propuesta ya no está disponible.')),
      );

      return;
    }

    final selectionGeneration = ++_stateGeneration;
    var refreshAfterFailure = false;

    setState(() {
      _selectingOfferId = offer.offerId;
    });

    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .selectRideOffer(rideId: currentRideId, offerId: offer.offerId);

      if (!_canApplyGeneration(selectionGeneration)) {
        return;
      }

      final agreedFare = ride.agreedFare;

      if (agreedFare != null &&
          fareAmountsDiffer(agreedFare, offer.proposedFare) == true) {
        debugPrint(
          'PASSENGER SELECT OFFER FARE MISMATCH '
          'offerFare=${offer.proposedFare} '
          'agreedFare=$agreedFare',
        );
      }

      setState(() {
        _ride = ride;
        _offers = const [];
        _error = null;
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Elegiste a ${offer.driverDisplayName} '
            'por S/ ${offer.proposedFare}.',
          ),
        ),
      );
    } on DioException catch (error) {
      refreshAfterFailure = true;

      debugPrint(
        'PASSENGER SELECT OFFER ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!_canApplyGeneration(selectionGeneration)) {
        return;
      }

      String message = 'No se pudo elegir este conductor.';

      if (error.response?.statusCode == 409) {
        message = 'Esta propuesta ya no está disponible.';
      } else if (error.response?.statusCode == 404) {
        message = 'No encontramos esta propuesta.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (_canApplyGeneration(selectionGeneration)) {
        setState(() {
          _selectingOfferId = null;
        });
      }
    }

    if (refreshAfterFailure && _canApplyGeneration(selectionGeneration)) {
      await _loadRide();
    }
  }

  Future<void> _cancelSearch() async {
    if (_canceling || _selectingOfferId != null || _navigatingAway) {
      return;
    }

    final currentRide = _ride;

    if (currentRide == null || currentRide.status != 'SEARCHING_DRIVER') {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _cream,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: _softBorder),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text(
            '¿Cancelar la búsqueda?',
            style: TextStyle(
              color: _primaryText,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Tu solicitud de viaje será cancelada.',
            style: TextStyle(color: _secondaryText, fontSize: 15, height: 1.4),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: _green,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Seguir buscando',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _destinationColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'Cancelar viaje',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted ||
        _canceling ||
        _selectingOfferId != null ||
        _navigatingAway ||
        _ride?.id != currentRide.id ||
        _ride?.status != 'SEARCHING_DRIVER') {
      return;
    }

    final cancellationGeneration = ++_stateGeneration;

    setState(() {
      _canceling = true;
      _error = null;
    });

    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .cancelRide(rideId: currentRide.id);

      if (!_canApplyGeneration(cancellationGeneration)) {
        return;
      }

      if (ride.status != 'CANCELLED') {
        setState(() {
          _ride = ride;
          if (ride.status != 'SEARCHING_DRIVER') {
            _offers = const [];
          }
          _error =
              'No se pudo confirmar la cancelación del viaje. '
              'El estado actual es ${ride.status}.';
        });
        return;
      }

      _timer?.cancel();

      setState(() {
        _ride = ride;
        _offers = const [];
        _error = null;
      });

      if (!mounted || _navigatingAway) {
        return;
      }

      _navigatingAway = true;
      context.go('/home');
    } on DioException catch (error) {
      if (!_canApplyGeneration(cancellationGeneration)) {
        return;
      }

      final message = _cancelErrorMessage(error);

      setState(() {
        _error = message;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      debugPrint('Error cancelando búsqueda del pasajero: $error');

      if (!_canApplyGeneration(cancellationGeneration)) {
        return;
      }

      const message = 'No se pudo cancelar la búsqueda. Intenta nuevamente.';

      setState(() {
        _error = message;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    } finally {
      if (_canApplyGeneration(cancellationGeneration)) {
        setState(() {
          _canceling = false;
        });
      }
    }
  }

  String _cancelErrorMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TukiTuki está tardando más de lo esperado. '
            'Intenta cancelar nuevamente.';

      case DioExceptionType.connectionError:
        return 'No se pudo conectar con TukiTuki. '
            'Revisa tu conexión e intenta nuevamente.';

      default:
        final statusCode = error.response?.statusCode;

        if (statusCode == 400) {
          return 'No se pudo cancelar la búsqueda. '
              'Revisa el estado del viaje.';
        }

        if (statusCode == 401) {
          return 'Tu sesión ya no es válida. '
              'Intenta iniciar sesión nuevamente.';
        }

        if (statusCode == 403) {
          return 'No tienes permiso para cancelar este viaje.';
        }

        if (statusCode == 404) {
          return 'No encontramos este viaje.';
        }

        if (statusCode == 409) {
          return 'El viaje cambió de estado y ya no puede cancelarse.';
        }

        if (statusCode != null && statusCode >= 500) {
          return 'TukiTuki no está disponible temporalmente. '
              'Intenta cancelar nuevamente.';
        }

        return 'No se pudo cancelar la búsqueda. Intenta nuevamente.';
    }
  }

  Future<void> _loadStartCodeForRide(String rideId) async {
    if (_loadingStartCode || _navigatingAway) {
      return;
    }

    setState(() {
      _loadingStartCode = true;
      _startCodeError = null;
    });

    try {
      final code = await ref.read(rideRepositoryProvider).getStartCode(rideId);

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _startCode = code;
        _startCodeError = null;
      });
    } catch (error) {
      debugPrint('Error obteniendo código de inicio: $error');

      if (!mounted || _navigatingAway) {
        return;
      }

      const message = 'No se pudo obtener el código de inicio.';

      setState(() {
        _startCodeError = message;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted && !_navigatingAway) {
        setState(() {
          _loadingStartCode = false;
        });
      }
    }
  }

  bool _isFinalStatus(String status) {
    return status == 'COMPLETED' ||
        status == 'CANCELLED' ||
        status == 'EXPIRED';
  }

  String _statusText(String status) {
    switch (status) {
      case 'SEARCHING_DRIVER':
        return 'Buscando un conductor...';

      case 'DRIVER_ASSIGNED':
        return '¡Conductor encontrado!';

      case 'DRIVER_ARRIVING':
        return 'Tu conductor está en camino';

      case 'DRIVER_ARRIVED':
        return 'Tu conductor llegó';

      case 'IN_PROGRESS':
        return 'Viaje en curso';

      case 'COMPLETED':
        return 'Viaje completado';

      case 'CANCELLED':
        return 'Viaje cancelado';

      case 'EXPIRED':
        return 'No encontramos conductor';

      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'SEARCHING_DRIVER':
        return Icons.search;

      case 'DRIVER_ASSIGNED':
        return Icons.two_wheeler;

      case 'DRIVER_ARRIVING':
        return Icons.two_wheeler;

      case 'DRIVER_ARRIVED':
        return Icons.location_on;

      case 'IN_PROGRESS':
        return Icons.route;

      case 'COMPLETED':
        return Icons.check_circle;

      case 'CANCELLED':
        return Icons.cancel;

      case 'EXPIRED':
        return Icons.timer_off;

      default:
        return Icons.two_wheeler;
    }
  }

  String _formatDriverDistance(num distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }

    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildDriverAvatar(PassengerRideOffer offer) {
    final photoUrl = offer.photoUrl;

    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return const CircleAvatar(
        radius: 28,
        child: Icon(Icons.person, size: 30),
      );
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const CircleAvatar(
            radius: 28,
            child: Icon(Icons.person, size: 30),
          );
        },
      ),
    );
  }

  LatLng? _ridePoint(double? latitude, double? longitude) {
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  LatLng? _driverPoint(DriverLocation? location) {
    if (location == null) {
      return null;
    }

    return _ridePoint(location.latitude, location.longitude);
  }

  String _formatFare(String value) {
    final cents = fareAmountInCents(value);

    if (cents == null) {
      return value.trim();
    }

    final whole = cents ~/ 100;
    final decimals = (cents.abs() % 100).toString().padLeft(2, '0');

    return '$whole.$decimals';
  }

  String? _formatRideDistance(num distanceMeters) {
    final distance = distanceMeters.toDouble();

    if (!distance.isFinite || distance <= 0) {
      return null;
    }

    if (distance < 1000) {
      return '${distance.round()} m';
    }

    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  String? _formatRideDuration(num durationSeconds) {
    final duration = durationSeconds.toDouble();

    if (!duration.isFinite || duration <= 0) {
      return null;
    }

    final roundedMinutes = (duration / 60).round();
    final minutes = roundedMinutes < 1 ? 1 : roundedMinutes;

    return '$minutes min';
  }

  String _originLabel(PassengerRide ride) {
    final address = ride.originAddress.trim();

    if (address.isEmpty || address.toLowerCase() == 'origen') {
      return 'Tu ubicación actual';
    }

    return address;
  }

  String _destinationLabel(PassengerRide ride) {
    final address = ride.destinationAddress.trim();
    return address.isEmpty ? 'Destino' : address;
  }

  String _driverName(PassengerRideOffer offer) {
    final firstName = offer.driverFirstName.trim();
    final rawInitial = offer.driverLastNameInitial.trim().replaceAll('.', '');

    if (firstName.isEmpty || firstName == 'Conductor') {
      return 'Conductor';
    }

    if (rawInitial.isEmpty) {
      return firstName;
    }

    return '$firstName ${rawInitial[0].toUpperCase()}.';
  }

  String? _driverInitials(PassengerRideOffer offer) {
    final firstName = offer.driverFirstName.trim();
    final lastInitial = offer.driverLastNameInitial.trim().replaceAll('.', '');

    if (firstName.isEmpty || firstName == 'Conductor') {
      return null;
    }

    final buffer = StringBuffer();

    buffer.write(firstName[0].toUpperCase());

    if (lastInitial.isNotEmpty) {
      buffer.write(lastInitial[0].toUpperCase());
    }

    final initials = buffer.toString();
    return initials.isEmpty ? null : initials;
  }

  Widget _buildSearchingHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _cream,
        border: Border(bottom: BorderSide(color: _softBorder)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              'assets/images/tukituki_logo.png',
              width: 50,
              height: 50,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 50,
                  height: 50,
                  color: _green,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.two_wheeler,
                    color: Colors.white,
                    size: 26,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'TukiTuki',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _darkGreen,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: _secondaryCream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _border),
            ),
            child: IconButton(
              key: const ValueKey('cancel-search-close-button'),
              tooltip: 'Cancelar búsqueda',
              onPressed: _canceling || _selectingOfferId != null
                  ? null
                  : _cancelSearch,
              icon: const Icon(Icons.close_rounded),
              color: _darkGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRadar() {
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('ride-search-radar'),
          width: 100,
          height: 100,
          child: AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              Widget ring(double phase) {
                return Opacity(
                  opacity: (1 - phase).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.62 + (phase * 0.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _green.withValues(alpha: 0.42),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final firstPhase = _radarController.value;
              final secondPhase = (_radarController.value + 0.5) % 1;

              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: ring(firstPhase)),
                  Positioned.fill(child: ring(secondPhase)),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: _ctaYellow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.two_wheeler,
                      color: _darkGreen,
                      size: 28,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Buscando un conductor...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _primaryText,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Te avisaremos cuando llegue una propuesta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _secondaryText, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildPassengerOffer(PassengerRide ride) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _darkGreen.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              color: _ctaYellow,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'TU OFERTA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Text(
            'S/ ${_formatFare(ride.passengerOfferFare)}',
            key: const ValueKey('passenger-offer-fare'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(PassengerRide ride) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: _green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, size: 6, color: Colors.white),
              ),
              Container(width: 2, height: 52, color: _border),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _destinationColor, width: 3),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Origen',
                  style: TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _originLabel(ride),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 17),
                const Text(
                  'Destino',
                  style: TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _destinationLabel(ride),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required Key key,
    required IconData icon,
    required String label,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: _secondaryCream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _green),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      key: const ValueKey('ride-search-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2C3B5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _destinationColor, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _primaryText, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDriverAvatar(PassengerRideOffer offer) {
    final initials = _driverInitials(offer);
    final photoUrl = offer.photoUrl?.trim();
    final photoUri = photoUrl == null ? null : Uri.tryParse(photoUrl);

    Widget fallback() {
      return Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE7F1E8),
          shape: BoxShape.circle,
        ),
        child: initials == null
            ? const Icon(Icons.person_outline, color: _green, size: 27)
            : Text(
                initials,
                key: ValueKey('driver-initials-${offer.offerId}'),
                style: const TextStyle(
                  color: _darkGreen,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
      );
    }

    final hasValidPhoto =
        photoUri != null &&
        (photoUri.scheme == 'http' || photoUri.scheme == 'https') &&
        photoUri.host.isNotEmpty;

    if (!hasValidPhoto) {
      return fallback();
    }

    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  Widget _buildOfferCard(PassengerRideOffer offer) {
    final hasRating =
        offer.ratingCount > 0 &&
        offer.ratingAverage.isFinite &&
        offer.ratingAverage > 0;
    final driverDistance = _formatRideDistance(offer.distanceToOriginMeters);
    final selectingThisOffer = _selectingOfferId == offer.offerId;

    return Container(
      key: ValueKey('driver-offer-${offer.offerId}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _softBorder),
        boxShadow: [
          BoxShadow(
            color: _darkGreen.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildModernDriverAvatar(offer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _driverName(offer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _primaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasRating || driverDistance != null) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          if (hasRating)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFE8A600),
                                  size: 18,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  offer.ratingAverage.toStringAsFixed(1),
                                  key: ValueKey(
                                    'driver-rating-${offer.offerId}',
                                  ),
                                  style: const TextStyle(
                                    color: _primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          if (driverDistance != null)
                            Text(
                              'A $driverDistance de tu origen',
                              style: const TextStyle(
                                color: _secondaryText,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.hasDifferentProposedFare
                      ? 'Contraoferta del conductor'
                      : 'Acepta tu precio',
                  style: const TextStyle(
                    color: _secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'S/ ${_formatFare(offer.proposedFare)}',
                key: ValueKey('driver-fare-${offer.offerId}'),
                style: const TextStyle(
                  color: _darkGreen,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          if (offer.hasDifferentProposedFare) ...[
            const SizedBox(height: 4),
            Text(
              'Tu oferta: S/ ${_formatFare(offer.passengerOfferFare)}',
              style: const TextStyle(color: _secondaryText, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: ValueKey('accept-offer-${offer.offerId}'),
              onPressed: _selectingOfferId != null || _canceling
                  ? null
                  : () => _selectOffer(offer),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _green.withValues(alpha: 0.42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: selectingThisOffer
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 9),
                        Text('Aceptando...'),
                      ],
                    )
                  : const Text(
                      'Aceptar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingScaffold(PassengerRide ride) {
    final origin = _ridePoint(ride.originLatitude, ride.originLongitude);
    final destination = _ridePoint(
      ride.destinationLatitude,
      ride.destinationLongitude,
    );
    final distance = _formatRideDistance(ride.distanceMeters);
    final duration = _formatRideDuration(ride.estimatedDurationSeconds);

    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchingHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 156,
                  child: origin != null || destination != null
                      ? _RideRouteMap(origin: origin, destination: destination)
                      : Container(
                          key: const ValueKey('ride-search-map-placeholder'),
                          color: _secondaryCream,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_outlined, color: _green, size: 30),
                              SizedBox(height: 8),
                              Text(
                                'La ubicación del viaje no está disponible.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _secondaryText,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('ride-search-scroll'),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSearchRadar(),
                        const SizedBox(height: 18),
                        _buildPassengerOffer(ride),
                        const SizedBox(height: 16),
                        _buildRouteCard(ride),
                        if (distance != null || duration != null) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (distance != null)
                                _buildMetricChip(
                                  key: const ValueKey('ride-distance-chip'),
                                  icon: Icons.straighten_rounded,
                                  label: distance,
                                ),
                              if (duration != null)
                                _buildMetricChip(
                                  key: const ValueKey('ride-duration-chip'),
                                  icon: Icons.schedule_rounded,
                                  label: duration,
                                ),
                            ],
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 18),
                          _buildErrorBanner(_error!),
                        ],
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Conductores interesados',
                                style: TextStyle(
                                  color: _primaryText,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.25,
                                ),
                              ),
                            ),
                            Container(
                              key: const ValueKey('offers-count'),
                              constraints: const BoxConstraints(minWidth: 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _ctaYellow,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_offers.length}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _darkGreen,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_offers.isEmpty && _error == null)
                          Container(
                            key: const ValueKey('offers-empty-state'),
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _softBorder),
                            ),
                            child: Column(
                              children: [
                                if (_loadingOffers) ...[
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: _green,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                const Text(
                                  'Todavía no hay conductores interesados.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _primaryText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Seguimos buscando por ti.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _secondaryText),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final offer in _offers) ...[
                            _buildOfferCard(offer),
                            const SizedBox(height: 12),
                          ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey('cancel-search-button'),
                          onPressed: _canceling || _selectingOfferId != null
                              ? null
                              : _cancelSearch,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _destinationColor,
                            side: const BorderSide(color: Color(0xFFE6B6A8)),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: _canceling
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _destinationColor,
                                  ),
                                )
                              : const Icon(Icons.close_rounded),
                          label: Text(
                            _canceling ? 'Cancelando...' : 'Cancelar búsqueda',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _trackingMapHeight(String status) {
    switch (status) {
      case 'DRIVER_ARRIVING':
        return 300;

      case 'DRIVER_ARRIVED':
        return 150;

      default:
        return 200;
    }
  }

  Widget _buildTrackingStatusCard(PassengerRide ride) {
    late final String title;
    String? subtitle;
    late final IconData icon;

    switch (ride.status) {
      case 'DRIVER_ASSIGNED':
        title = '¡Conductor encontrado!';
        subtitle = 'Tu mototaxi está en camino';
        icon = Icons.two_wheeler;
        break;

      case 'DRIVER_ARRIVING':
        title = 'Tu conductor está en camino';
        subtitle = 'Sigue su ubicación en el mapa.';
        icon = Icons.two_wheeler;
        break;

      case 'DRIVER_ARRIVED':
        title = 'Tu conductor llegó';
        subtitle = 'Muéstrale tu código para iniciar el viaje.';
        icon = Icons.location_on;
        break;

      default:
        title = _statusText(ride.status);
        icon = _statusIcon(ride.status);
    }

    return Container(
      key: const ValueKey('driver-tracking-status-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _softBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: _ctaYellow,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _darkGreen, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('driver-tracking-status-title'),
                  style: const TextStyle(
                    color: _primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _secondaryText,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedDriverAvatar(AssignedDriver driver) {
    final photoUrl = driver.photoUrl?.trim();
    final photoUri = photoUrl == null || photoUrl.isEmpty
        ? null
        : Uri.tryParse(photoUrl);

    Widget fallback() {
      final firstName = driver.firstName.trim();
      final initial = firstName.isEmpty ? null : firstName[0].toUpperCase();

      return Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE7F1E8),
          shape: BoxShape.circle,
        ),
        child: initial == null
            ? const Icon(Icons.person_outline, color: _green, size: 28)
            : Text(
                initial,
                style: const TextStyle(
                  color: _darkGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
      );
    }

    final hasValidPhoto =
        photoUri != null &&
        (photoUri.scheme == 'http' || photoUri.scheme == 'https') &&
        photoUri.host.isNotEmpty;

    if (!hasValidPhoto) {
      return fallback();
    }

    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  Widget _buildAssignedDriverCard(AssignedDriver driver) {
    final vehicle = driver.vehicle;
    final firstName = driver.firstName.trim();
    final plate = vehicle?.plate.trim() ?? '';
    final vehicleDescription = vehicle == null
        ? ''
        : [
            vehicle.brand.trim(),
            vehicle.model.trim(),
            vehicle.color.trim(),
          ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      key: const ValueKey('assigned-driver-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAssignedDriverAvatar(driver),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (firstName.isNotEmpty)
                  Text(
                    firstName,
                    key: const ValueKey('assigned-driver-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (driver.hasRating || plate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if (driver.hasRating)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFE8A600),
                              size: 18,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              double.tryParse(
                                    driver.ratingAverage,
                                  )?.toStringAsFixed(1) ??
                                  driver.ratingAverage,
                              key: const ValueKey('assigned-driver-rating'),
                              style: const TextStyle(
                                color: _primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      if (plate.isNotEmpty)
                        Text(
                          plate,
                          key: const ValueKey('assigned-driver-plate'),
                          style: const TextStyle(
                            color: _secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
                if (vehicleDescription.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    vehicleDescription,
                    key: const ValueKey('assigned-driver-vehicle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreedFareCard(PassengerRide ride) {
    final fare = ride.agreedFare ?? ride.passengerOfferFare;

    return Container(
      key: const ValueKey('agreed-fare-card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _darkGreen.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.handshake_outlined,
              color: _ctaYellow,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'PRECIO ACORDADO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Text(
            'S/ ${_formatFare(fare)}',
            key: const ValueKey('agreed-fare-value'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowRideButton() {
    return SizedBox(
      key: const ValueKey('follow-ride-button'),
      height: 52,
      child: FilledButton(
        onPressed: () {
          setState(() {
            _assignedAcknowledged = true;
          });
        },
        style: FilledButton.styleFrom(
          backgroundColor: _ctaYellow,
          foregroundColor: _darkGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: const Text('Seguir mi viaje'),
      ),
    );
  }

  Widget _buildPinCard(PassengerRide ride) {
    return Container(
      key: const ValueKey('start-code-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'CÓDIGO PARA INICIAR EL VIAJE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _secondaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingStartCode)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _green,
                  ),
                ),
              ),
            )
          else if (_startCode != null) ...[
            Text(
              _startCode!.code,
              key: const ValueKey('start-code-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _darkGreen,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 12,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Muestra este código al conductor para confirmar que eres tú '
              'e iniciar el viaje.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _secondaryText,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_startCode!.remainingAttempts} intentos disponibles',
              key: const ValueKey('start-code-attempts'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ] else if (_startCodeError != null) ...[
            Text(
              _startCodeError!,
              key: const ValueKey('start-code-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _destinationColor,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('start-code-retry'),
              onPressed: () => _loadStartCodeForRide(ride.id),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ] else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildDriverTrackingScaffold(PassengerRide ride) {
    final origin = _ridePoint(ride.originLatitude, ride.originLongitude);
    final destination = _ridePoint(
      ride.destinationLatitude,
      ride.destinationLongitude,
    );
    final driverPoint = _driverPoint(ride.driverLocation);
    final driver = ride.driver;

    return Scaffold(
      backgroundColor: _cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchingHeader(),
            if (origin != null || destination != null || driverPoint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: _trackingMapHeight(ride.status),
                    child: _RideRouteMap(
                      origin: origin,
                      destination: destination,
                      driverLocation: driverPoint,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('driver-tracking-scroll'),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTrackingStatusCard(ride),
                        if (driver != null) ...[
                          const SizedBox(height: 16),
                          _buildAssignedDriverCard(driver),
                        ],
                        const SizedBox(height: 16),
                        _buildAgreedFareCard(ride),
                        const SizedBox(height: 16),
                        _buildRouteCard(ride),
                        if (ride.status == 'DRIVER_ARRIVED') ...[
                          const SizedBox(height: 16),
                          _buildPinCard(ride),
                        ],
                        if (ride.status == 'DRIVER_ASSIGNED' &&
                            !_assignedAcknowledged) ...[
                          const SizedBox(height: 24),
                          _buildFollowRideButton(),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final ride = _ride;

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TukiTuki')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ?? 'No encontramos un viaje activo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (ride.status == 'SEARCHING_DRIVER') {
      return _buildSearchingScaffold(ride);
    }

    if (ride.status == 'DRIVER_ASSIGNED' ||
        ride.status == 'DRIVER_ARRIVING' ||
        ride.status == 'DRIVER_ARRIVED') {
      return _buildDriverTrackingScaffold(ride);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TukiTuki'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              if (ride.status == 'SEARCHING_DRIVER')
                const Center(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(strokeWidth: 7),
                  ),
                )
              else
                Icon(_statusIcon(ride.status), size: 90),

              const SizedBox(height: 32),

              Text(
                _statusText(ride.status),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              if (ride.status == 'SEARCHING_DRIVER') ...[
                const Text('Tu oferta', textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  'S/ ${ride.passengerOfferFare}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else ...[
                Text(
                  'S/ ${ride.agreedFare ?? ride.passengerOfferFare}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.my_location),
                        title: const Text('Origen'),
                        subtitle: Text(ride.originAddress),
                      ),

                      const Divider(),

                      ListTile(
                        leading: const Icon(Icons.location_on),
                        title: const Text('Destino'),
                        subtitle: Text(ride.destinationAddress),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                '${(ride.distanceMeters / 1000).toStringAsFixed(1)} km'
                ' • '
                '${(ride.estimatedDurationSeconds / 60).round()} min',
                textAlign: TextAlign.center,
              ),

              if (ride.status == 'SEARCHING_DRIVER') ...[
                const SizedBox(height: 32),

                const Text(
                  'Conductores interesados',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                if (_offers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (_loadingOffers) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                          ],
                          const Text(
                            'Esperando propuestas de '
                            'conductores cercanos...',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final offer in _offers) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _buildDriverAvatar(offer),

                                const SizedBox(width: 14),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        offer.driverDisplayName,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 5),

                                      Row(
                                        children: [
                                          const Icon(Icons.star, size: 18),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              offer.ratingCount > 0
                                                  ? '${offer.ratingAverage.toStringAsFixed(1)} '
                                                        '(${offer.ratingCount})'
                                                  : 'Conductor nuevo',
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 5),

                                      Text(
                                        'A ${_formatDriverDistance(offer.distanceToOriginMeters)} '
                                        'de tu punto de recojo',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            Text(
                              offer.hasDifferentProposedFare
                                  ? 'Contraoferta del conductor'
                                  : 'Acepta tu precio',
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 6),

                            Text(
                              'S/ ${offer.proposedFare}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            if (offer.hasDifferentProposedFare) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Tu oferta fue '
                                'S/ ${offer.passengerOfferFare}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],

                            const SizedBox(height: 16),

                            FilledButton(
                              onPressed: _selectingOfferId != null || _canceling
                                  ? null
                                  : () => _selectOffer(offer),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: _selectingOfferId == offer.offerId
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Elegir conductor'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],

                const SizedBox(height: 12),

                OutlinedButton(
                  key: const ValueKey('cancel-search-button'),
                  onPressed: _canceling || _selectingOfferId != null
                      ? null
                      : _cancelSearch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: _canceling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cancelar búsqueda'),
                  ),
                ),
              ],

              if (ride.status == 'IN_PROGRESS') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.route, size: 54),
                        SizedBox(height: 12),
                        Text(
                          'Viaje iniciado',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'TukiTuki está en camino '
                          'al destino.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status == 'CANCELLED') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.cancel, size: 54),
                        SizedBox(height: 12),
                        Text(
                          'Viaje cancelado',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status == 'EXPIRED') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.timer_off, size: 54),
                        SizedBox(height: 12),
                        Text(
                          'No encontramos conductor',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),

                Text(_error!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RideRouteMap extends StatefulWidget {
  const _RideRouteMap({
    required this.origin,
    required this.destination,
    this.driverLocation,
  });

  final LatLng? origin;
  final LatLng? destination;

  /*
   * La ubicación del Driver NO participa del ajuste
   * de cámara (ver _scheduleCameraUpdate): solo agrega
   * un marker que se actualiza con cada rebuild del
   * polling, evitando saltos de cámara cada pocos
   * segundos.
   */
  final LatLng? driverLocation;

  @override
  State<_RideRouteMap> createState() => _RideRouteMapState();
}

class _RideRouteMapState extends State<_RideRouteMap> {
  GoogleMapController? _controller;
  String? _lastCameraGeometry;

  @override
  void didUpdateWidget(covariant _RideRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination) {
      _scheduleCameraUpdate();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _geometrySignature {
    final origin = widget.origin;
    final destination = widget.destination;

    return '${origin?.latitude},${origin?.longitude}|'
        '${destination?.latitude},${destination?.longitude}';
  }

  LatLng get _initialTarget {
    final origin = widget.origin;
    final destination = widget.destination;

    if (origin != null && destination != null) {
      return LatLng(
        (origin.latitude + destination.latitude) / 2,
        (origin.longitude + destination.longitude) / 2,
      );
    }

    return origin ?? destination ?? widget.driverLocation!;
  }

  bool _areDistinct(LatLng first, LatLng second) {
    return (first.latitude - second.latitude).abs() > 0.00001 ||
        (first.longitude - second.longitude).abs() > 0.00001;
  }

  void _scheduleCameraUpdate() {
    final controller = _controller;
    final geometry = _geometrySignature;

    if (controller == null || geometry == _lastCameraGeometry) {
      return;
    }

    _lastCameraGeometry = geometry;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _controller != controller) {
        return;
      }

      final origin = widget.origin;
      final destination = widget.destination;

      try {
        if (origin != null &&
            destination != null &&
            _areDistinct(origin, destination)) {
          final southwest = LatLng(
            origin.latitude < destination.latitude
                ? origin.latitude
                : destination.latitude,
            origin.longitude < destination.longitude
                ? origin.longitude
                : destination.longitude,
          );
          final northeast = LatLng(
            origin.latitude > destination.latitude
                ? origin.latitude
                : destination.latitude,
            origin.longitude > destination.longitude
                ? origin.longitude
                : destination.longitude,
          );

          await controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(southwest: southwest, northeast: northeast),
              42,
            ),
          );
        } else {
          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(origin ?? destination!, 16),
          );
        }
      } catch (error) {
        debugPrint('No se pudo ajustar el mapa del viaje: $error');
      }
    });
  }

  Set<Marker> get _markers {
    return {
      if (widget.origin != null)
        Marker(
          markerId: const MarkerId('ride-origin'),
          position: widget.origin!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Origen'),
        ),
      if (widget.destination != null)
        Marker(
          markerId: const MarkerId('ride-destination'),
          position: widget.destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      if (widget.driverLocation != null)
        Marker(
          markerId: const MarkerId('ride-driver'),
          position: widget.driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          infoWindow: const InfoWindow(title: 'Conductor'),
          zIndexInt: 2,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      key: const ValueKey('ride-search-google-map'),
      initialCameraPosition: CameraPosition(target: _initialTarget, zoom: 14),
      markers: _markers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onMapCreated: (controller) {
        _controller = controller;
        _scheduleCameraUpdate();
      },
    );
  }
}
