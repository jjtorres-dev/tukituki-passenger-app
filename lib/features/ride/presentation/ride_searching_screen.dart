import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/ride_repository.dart';
import '../domain/passenger_ride.dart';
import '../domain/passenger_ride_offer.dart';
import '../domain/passenger_ride_start_code.dart';

class RideSearchingScreen extends ConsumerStatefulWidget {
  const RideSearchingScreen({
    required this.rideId,
    super.key,
  });

  final String rideId;

  @override
  ConsumerState<RideSearchingScreen> createState() =>
      _RideSearchingScreenState();
}

class _RideSearchingScreenState
    extends ConsumerState<RideSearchingScreen> {
  PassengerRide? _ride;
  PassengerRideStartCode? _startCode;

  List<PassengerRideOffer> _offers = const [];

  Timer? _timer;

  bool _loading = true;
  bool _loadingStartCode = false;
  bool _loadingOffers = false;
  bool _navigatingAway = false;

  String? _selectingOfferId;
  String? _error;

  @override
  void initState() {
    super.initState();

    _loadRide();

    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadRide(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadRide() async {
    if (_navigatingAway) {
      return;
    }

    try {
      final repository =
          ref.read(rideRepositoryProvider);

      // Primero consultamos el viaje activo real.
      // Si ya terminó, active puede devolver 404,
      // por eso luego consultamos el viaje por ID.
      final activeRide =
          await repository.getActiveRide();

      PassengerRide ride;

      if (activeRide != null) {
        ride = activeRide;
      } else {
        ride = await repository.getRide(
          widget.rideId,
        );
      }

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _ride = ride;
        _loading = false;
        _error = null;
      });

      if (ride.status == 'SEARCHING_DRIVER') {
        await _loadRideOffers(ride.id);
      } else if (_offers.isNotEmpty) {
        setState(() {
          _offers = const [];
        });
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

        context.go(
          '/ride/${ride.id}/receipt',
        );

        return;
      }

      // Si el conductor ya llegó,
      // obtenemos automáticamente
      // el código de inicio.
      if (ride.status == 'DRIVER_ARRIVED' &&
          _startCode == null &&
          !_loadingStartCode) {
        await _loadStartCodeForRide(
          ride.id,
        );
      }

      // Cuando el viaje ya empezó,
      // dejamos de mostrar el código.
      if (ride.status == 'IN_PROGRESS' &&
          _startCode != null) {
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
      debugPrint(
        'Error actualizando viaje del pasajero: $error',
      );

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            'No se pudo actualizar el viaje.';
      });
    }
  }

  Future<void> _loadRideOffers(
    String rideId,
  ) async {
    if (_loadingOffers ||
        _navigatingAway ||
        _selectingOfferId != null) {
      return;
    }

    _loadingOffers = true;

    try {
      final offers = await ref
          .read(rideRepositoryProvider)
          .getRideOffers(rideId);

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _offers = offers;
      });
    } on DioException catch (error) {
      debugPrint(
        'PASSENGER OFFERS ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (error.response?.statusCode != 409 &&
          error.response?.statusCode != 404 &&
          mounted) {
        setState(() {
          _error =
              'No se pudieron actualizar '
              'las propuestas de conductores.';
        });
      }
    } catch (error) {
      debugPrint(
        'PASSENGER OFFERS ERROR inesperado: $error',
      );
    } finally {
      _loadingOffers = false;
    }
  }

  Future<void> _selectOffer(
    PassengerRideOffer offer,
  ) async {
    if (_selectingOfferId != null ||
        _navigatingAway) {
      return;
    }

    setState(() {
      _selectingOfferId = offer.offerId;
    });

    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .selectRideOffer(
            rideId: widget.rideId,
            offerId: offer.offerId,
          );

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _ride = ride;
        _offers = const [];
        _error = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Elegiste a ${offer.driverDisplayName} '
            'por S/ ${offer.proposedFare}.',
          ),
        ),
      );
    } on DioException catch (error) {
      debugPrint(
        'PASSENGER SELECT OFFER ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      String message =
          'No se pudo elegir este conductor.';

      if (error.response?.statusCode == 409) {
        message =
            'Esta propuesta ya no está disponible.';
      } else if (error.response?.statusCode == 404) {
        message =
            'No encontramos esta propuesta.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );

      await _loadRide();
    } finally {
      if (mounted && !_navigatingAway) {
        setState(() {
          _selectingOfferId = null;
        });
      }
    }
  }

  Future<void> _loadStartCodeForRide(
    String rideId,
  ) async {
    if (_loadingStartCode ||
        _navigatingAway) {
      return;
    }

    setState(() {
      _loadingStartCode = true;
    });

    try {
      final code = await ref
          .read(rideRepositoryProvider)
          .getStartCode(rideId);

      if (!mounted || _navigatingAway) {
        return;
      }

      setState(() {
        _startCode = code;
      });
    } catch (error) {
      debugPrint(
        'Error obteniendo código de inicio: $error',
      );

      if (!mounted || _navigatingAway) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo obtener el código de inicio.',
          ),
        ),
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

  String _formatDriverDistance(
    num distanceMeters,
  ) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }

    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildDriverAvatar(
    PassengerRideOffer offer,
  ) {
    final photoUrl = offer.photoUrl;

    if (photoUrl == null ||
        photoUrl.trim().isEmpty) {
      return const CircleAvatar(
        radius: 28,
        child: Icon(
          Icons.person,
          size: 30,
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return const CircleAvatar(
            radius: 28,
            child: Icon(
              Icons.person,
              size: 30,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final ride = _ride;

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Tu TukiTuki',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ??
                  'No encontramos un viaje activo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tu TukiTuki',
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              if (ride.status ==
                  'SEARCHING_DRIVER')
                const Center(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 7,
                    ),
                  ),
                )
              else
                Icon(
                  _statusIcon(ride.status),
                  size: 90,
                ),

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
                const Text(
                  'Tu oferta',
                  textAlign: TextAlign.center,
                ),
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
                  padding:
                      const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.my_location,
                        ),
                        title: const Text(
                          'Origen',
                        ),
                        subtitle: Text(
                          ride.originAddress,
                        ),
                      ),

                      const Divider(),

                      ListTile(
                        leading: const Icon(
                          Icons.location_on,
                        ),
                        title: const Text(
                          'Destino',
                        ),
                        subtitle: Text(
                          ride.destinationAddress,
                        ),
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
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (_offers.isEmpty)
                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (_loadingOffers) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                          ],
                          const Text(
                            'Esperando propuestas de '
                            'conductores cercanos...',
                            textAlign:
                                TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final offer in _offers) ...[
                    Card(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _buildDriverAvatar(
                                  offer,
                                ),

                                const SizedBox(
                                  width: 14,
                                ),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        offer.driverDisplayName,
                                        style:
                                            const TextStyle(
                                          fontSize: 19,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 5,
                                      ),

                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            size: 18,
                                          ),
                                          const SizedBox(
                                            width: 4,
                                          ),
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

                                      const SizedBox(
                                        height: 5,
                                      ),

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
                              offer.isCounterOffer
                                  ? 'Contraoferta del conductor'
                                  : 'Acepta tu precio',
                              textAlign:
                                  TextAlign.center,
                            ),

                            const SizedBox(height: 6),

                            Text(
                              'S/ ${offer.proposedFare}',
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                fontSize: 30,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            if (offer.isCounterOffer) ...[
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                'Tu oferta fue '
                                'S/ ${offer.passengerOfferFare}',
                                textAlign:
                                    TextAlign.center,
                                style:
                                    const TextStyle(
                                  fontSize: 13,
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            FilledButton(
                              onPressed:
                                  _selectingOfferId != null
                                      ? null
                                      : () =>
                                          _selectOffer(offer),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child:
                                    _selectingOfferId ==
                                            offer.offerId
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Elegir conductor',
                                          ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
              ],

              if (ride.status ==
                  'DRIVER_ARRIVED') ...[
                const SizedBox(height: 32),

                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.pin,
                          size: 48,
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        const Text(
                          'Código para iniciar',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        if (_loadingStartCode)
                          const CircularProgressIndicator()
                        else if (_startCode !=
                            null) ...[
                          Text(
                            _startCode!.code,
                            textAlign:
                                TextAlign.center,
                            style:
                                const TextStyle(
                              fontSize: 48,
                              fontWeight:
                                  FontWeight.bold,
                              letterSpacing: 14,
                            ),
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          const Text(
                            'Muéstrale este código '
                            'al conductor para iniciar '
                            'el viaje.',
                            textAlign:
                                TextAlign.center,
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          Text(
                            'Intentos disponibles: '
                            '${_startCode!.remainingAttempts}',
                            textAlign:
                                TextAlign.center,
                          ),
                        ] else
                          FilledButton(
                            onPressed: () {
                              _loadStartCodeForRide(
                                ride.id,
                              );
                            },
                            child: const Text(
                              'Obtener código',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status ==
                  'IN_PROGRESS') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.route,
                          size: 54,
                        ),
                        SizedBox(
                          height: 12,
                        ),
                        Text(
                          'Viaje iniciado',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          height: 8,
                        ),
                        Text(
                          'Tu TukiTuki está en camino '
                          'al destino.',
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status ==
                  'CANCELLED') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cancel,
                          size: 54,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Viaje cancelado',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status ==
                  'EXPIRED') ...[
                const SizedBox(height: 32),

                const Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.timer_off,
                          size: 54,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No encontramos conductor',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight:
                                FontWeight.bold,
                          ),
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),

                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}