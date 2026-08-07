import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/data/auth_repository.dart';
import '../fare/data/fare_repository.dart';
import '../fare/domain/fare_estimate.dart';
import '../ride/data/ride_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends ConsumerState<HomeScreen> {
  bool _loading = false;
  FareEstimate? _quote;
  bool _requestingRide = false;

  Future<void> _requestRide() async {
    final quote = _quote;

    if (quote == null) {
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
          );

      if (!mounted) {
        return;
      }

      context.go('/ride/${ride.id}');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo solicitar el viaje.';

      if (error.response?.statusCode == 400) {
        message =
            'La cotización venció. '
            'Calcula una nueva tarifa.';
      } else if (error.response?.statusCode == 409) {
        message =
            'Ya tienes un viaje activo.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _estimateFare() async {
    setState(() {
      _loading = true;
    });

    try {
      final quote = await ref
          .read(fareRepositoryProvider)
          .estimateRide();

      if (!mounted) {
        return;
      }

      setState(() {
        _quote = quote;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo calcular la tarifa.';

      if (error.response?.statusCode == 400) {
        message =
            'El origen o destino está fuera de cobertura '
            'o no existe una tarifa disponible.';
      } else if (error.response?.statusCode == 401) {
        message =
            'Tu sesión ya no es válida.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final quote = _quote;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TukiTuki'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref
                  .read(authRepositoryProvider)
                  .logout();

              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Text(
                '¿A dónde vamos?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Por ahora usaremos una ruta de prueba '
                'dentro de Tarapoto.',
              ),

              const SizedBox(height: 32),

              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.my_location,
                        ),
                        title: Text('Origen'),
                        subtitle: Text(
                          'Centro de Tarapoto',
                        ),
                      ),
                      Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.location_on,
                        ),
                        title: Text('Destino'),
                        subtitle: Text(
                          'Destino de prueba Tarapoto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              FilledButton(
                onPressed:
                    _loading ? null : _estimateFare,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Calcular tarifa',
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
              ),

              if (quote != null) ...[
                const SizedBox(height: 28),

                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Tu viaje',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          'S/ ${quote.estimatedFare}',
                          textAlign:
                              TextAlign.center,
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '${(quote.distanceMeters / 1000).toStringAsFixed(1)} km'
                          ' • '
                          '${(quote.durationSeconds / 60).round()} min',
                          textAlign:
                              TextAlign.center,
                        ),

                        const SizedBox(height: 20),

                        Text(
                          quote.originAddress,
                        ),

                        const Padding(
                          padding:
                              EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          child: Icon(
                            Icons.arrow_downward,
                          ),
                        ),

                        Text(
                          quote.destinationAddress,
                        ),

                        const SizedBox(height: 20),

                        Text(
                          'Cotización válida hasta '
                          '${quote.expiresAt.toLocal()}',
                          textAlign:
                              TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 20),

                        FilledButton.icon(
                          onPressed:
                              _requestingRide ? null : _requestRide,
                          icon: _requestingRide
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.two_wheeler,
                                ),
                          label: Text(
                            _requestingRide
                                ? 'Solicitando...'
                                : 'Solicitar TukiTuki',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}