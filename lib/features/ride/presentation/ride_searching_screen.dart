import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ride_repository.dart';
import '../domain/passenger_ride.dart';

class RideSearchingScreen
    extends ConsumerStatefulWidget {
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
  Timer? _timer;
  bool _loading = true;
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
    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .getRide(widget.rideId);

      if (!mounted) {
        return;
      }

      setState(() {
        _ride = ride;
        _loading = false;
        _error = null;
      });

      if (_isFinalStatus(ride.status)) {
        _timer?.cancel();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            'No se pudo actualizar el viaje.';
      });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final ride = _ride;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu TukiTuki'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null && ride == null
              ? Center(
                  child: Text(_error!),
                )
              : Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),

                    if (ride?.status ==
                        'SEARCHING_DRIVER')
                      const Center(
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 7,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.two_wheeler,
                        size: 90,
                      ),

                    const SizedBox(height: 32),

                    Text(
                      _statusText(
                        ride?.status ?? '',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (ride != null) ...[
                      Text(
                        'S/ ${ride.estimatedPassengerFare}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

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
                                title:
                                    const Text('Origen'),
                                subtitle: Text(
                                  ride.originAddress,
                                ),
                              ),
                              const Divider(),
                              ListTile(
                                leading: const Icon(
                                  Icons.location_on,
                                ),
                                title:
                                    const Text('Destino'),
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
                    ],

                    const Spacer(),

                    if (_error != null)
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}