import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/ride_repository.dart';
import '../domain/ride_receipt.dart';

class RideReceiptScreen
    extends ConsumerStatefulWidget {
  const RideReceiptScreen({
    required this.rideId,
    super.key,
  });

  final String rideId;

  @override
  ConsumerState<RideReceiptScreen> createState() =>
      _RideReceiptScreenState();
}

class _RideReceiptScreenState
    extends ConsumerState<RideReceiptScreen> {
  final _commentController =
      TextEditingController();

  RideReceipt? _receipt;

  Timer? _paymentTimer;

  bool _loading = true;
  bool _refreshingReceipt = false;
  bool _sendingRating = false;
  bool _rated = false;

  int _score = 5;

  final Set<String> _selectedTags = {};

  String? _error;

  static const Map<String, String> _tags = {
    'SAFE_DRIVING': 'Conducción segura',
    'FRIENDLY': 'Amable',
    'CLEAN_VEHICLE': 'Vehículo limpio',
    'PUNCTUAL': 'Puntual',
    'GOOD_COMMUNICATION':
        'Buena comunicación',
    'RESPECTFUL': 'Respetuoso',
    'CLEAR_PICKUP_POINT':
        'Punto de recojo claro',
  };

  @override
  void initState() {
    super.initState();

    unawaited(
      _loadReceipt(),
    );
  }

  @override
  void dispose() {
    _paymentTimer?.cancel();

    _commentController.dispose();

    super.dispose();
  }

  Future<void> _loadReceipt({
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final receipt = await ref
          .read(rideRepositoryProvider)
          .getReceipt(
            widget.rideId,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _receipt = receipt;
        _loading = false;
        _error = null;
      });

      _configurePaymentPolling(
        receipt,
      );
    } catch (error) {
      debugPrint(
        'Error cargando recibo: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            'No se pudo cargar el recibo.';
      });
    }
  }

  void _configurePaymentPolling(
    RideReceipt receipt,
  ) {
    final status =
        receipt.payment?.status;

    if (status == 'PAID' ||
        _isTerminalPaymentStatus(status)) {
      _paymentTimer?.cancel();
      _paymentTimer = null;

      return;
    }

    if (_paymentTimer != null) {
      return;
    }

    debugPrint(
      'PASSENGER PAYMENT - '
      'iniciando polling, status=$status',
    );

    _paymentTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        unawaited(
          _refreshPayment(),
        );
      },
    );
  }

  Future<void> _refreshPayment() async {
    if (_refreshingReceipt) {
      return;
    }

    _refreshingReceipt = true;

    try {
      final receipt = await ref
          .read(rideRepositoryProvider)
          .getReceipt(
            widget.rideId,
          );

      if (!mounted) {
        return;
      }

      final previousStatus =
          _receipt?.payment?.status;

      final newStatus =
          receipt.payment?.status;

      setState(() {
        _receipt = receipt;
      });

      if (previousStatus != newStatus) {
        debugPrint(
          'PASSENGER PAYMENT '
          '$previousStatus -> $newStatus',
        );
      }

      _configurePaymentPolling(
        receipt,
      );
    } catch (error) {
      debugPrint(
        'Error actualizando pago: $error',
      );
    } finally {
      _refreshingReceipt = false;
    }
  }

  bool _isTerminalPaymentStatus(
    String? status,
  ) {
    return status == 'FAILED' ||
        status == 'EXPIRED' ||
        status == 'DISPUTED' ||
        status == 'VOIDED';
  }

  bool get _paymentConfirmed {
    return _receipt?.payment?.status ==
        'PAID';
  }

  Future<void> _submitRating() async {
    if (_sendingRating ||
        _rated) {
      return;
    }

    if (!_paymentConfirmed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Espera a que el conductor '
            'confirme el pago.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _sendingRating = true;
    });

    try {
      await ref
          .read(rideRepositoryProvider)
          .submitRating(
            rideId: widget.rideId,
            score: _score,
            comment:
                _commentController.text,
            tags:
                _selectedTags.toList(),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _rated = true;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            '¡Gracias por tu calificación!',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo enviar '
          'la calificación.';

      if (error.response?.statusCode ==
          409) {
        message =
            'Este viaje ya fue calificado.';

        setState(() {
          _rated = true;
        });
      } else if (error.response?.statusCode ==
          400) {
        message =
            'La calificación no es válida.';
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
          _sendingRating = false;
        });
      }
    }
  }

  String _formatDistance(
    num meters,
  ) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(
    num seconds,
  ) {
    if (seconds < 60) {
      return '${seconds.round()} s';
    }

    return '${(seconds / 60).round()} min';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child:
                CircularProgressIndicator(),
          ),
        ),
      );
    }

    final receipt = _receipt;

    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Recibo',
          ),
        ),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Text(
              _error ??
                  'No se encontró '
                      'el recibo.',
              textAlign:
                  TextAlign.center,
            ),
          ),
        ),
      );
    }

    final payment =
        receipt.payment;

    final paymentConfirmed =
        payment?.status == 'PAID';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Viaje completado',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.check_circle,
                size: 90,
              ),

              const SizedBox(height: 20),

              const Text(
                '¡Gracias por viajar!',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                paymentConfirmed
                    ? 'Total pagado'
                    : 'Total a pagar',
                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(height: 6),

              Text(
                'S/ ${payment?.amountDue ?? receipt.fare.finalFare}',
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 28),

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
                          receipt.originAddress,
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
                          receipt
                              .destinationAddress,
                        ),
                      ),

                      const Divider(),

                      _ReceiptRow(
                        label: 'Distancia',
                        value: _formatDistance(
                          receipt
                              .actualDistanceMeters,
                        ),
                      ),

                      _ReceiptRow(
                        label: 'Duración',
                        value: _formatDuration(
                          receipt
                              .actualDurationSeconds,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'Pago',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      _ReceiptRow(
                        label: 'Método',
                        value:
                            payment?.method ?? '-',
                      ),

                      _ReceiptRow(
                        label: 'Estado',
                        value:
                            payment?.status ?? '-',
                      ),

                      _ReceiptRow(
                        label: 'Total',
                        value:
                            'S/ ${payment?.amountDue ?? receipt.fare.finalFare}',
                      ),

                      if (payment?.cashReceived !=
                          null)
                        _ReceiptRow(
                          label:
                              'Efectivo recibido',
                          value:
                              'S/ ${payment!.cashReceived}',
                        ),

                      if (payment?.changeGiven !=
                          null)
                        _ReceiptRow(
                          label: 'Vuelto',
                          value:
                              'S/ ${payment!.changeGiven}',
                        ),

                      if (!paymentConfirmed &&
                          !_isTerminalPaymentStatus(
                            payment?.status,
                          )) ...[
                        const SizedBox(
                          height: 16,
                        ),

                        const Divider(),

                        const SizedBox(
                          height: 12,
                        ),

                        const LinearProgressIndicator(),

                        const SizedBox(
                          height: 14,
                        ),

                        const Text(
                          'Esperando confirmación '
                          'del pago por parte '
                          'del conductor...',
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              if (!paymentConfirmed &&
                  !_isTerminalPaymentStatus(
                    payment?.status,
                  )) ...[
                const Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 54,
                        ),

                        SizedBox(
                          height: 12,
                        ),

                        Text(
                          'Esperando el pago',
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
                          'Cuando el conductor '
                          'confirme el efectivo, '
                          'podrás calificar '
                          'el viaje.',
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (paymentConfirmed) ...[
                const Text(
                  '¿Cómo estuvo tu viaje?',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) {
                      final value =
                          index + 1;

                      return IconButton(
                        onPressed: _rated
                            ? null
                            : () {
                                setState(() {
                                  _score =
                                      value;
                                });
                              },
                        iconSize: 42,
                        disabledColor:
                            value <= _score
                                ? Theme.of(
                                    context,
                                  )
                                    .colorScheme
                                    .primary
                                : Theme.of(
                                    context,
                                  )
                                    .colorScheme
                                    .outline,
                        icon: Icon(
                          value <= _score
                              ? Icons.star
                              : Icons
                                  .star_border,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                if (!_rated) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment:
                        WrapAlignment.center,
                    children:
                        _tags.entries.map(
                      (entry) {
                        final selected =
                            _selectedTags
                                .contains(
                          entry.key,
                        );

                        return FilterChip(
                          label: Text(
                            entry.value,
                          ),
                          selected:
                              selected,
                          onSelected:
                              (value) {
                            setState(() {
                              if (value) {
                                if (_selectedTags
                                        .length <
                                    5) {
                                  _selectedTags
                                      .add(
                                    entry.key,
                                  );
                                }
                              } else {
                                _selectedTags
                                    .remove(
                                  entry.key,
                                );
                              }
                            });
                          },
                        );
                      },
                    ).toList(),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                  TextField(
                    controller:
                        _commentController,
                    maxLength: 500,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Comentario opcional',
                      border:
                          OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  FilledButton.icon(
                    onPressed:
                        _sendingRating
                            ? null
                            : _submitRating,
                    icon: _sendingRating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.star,
                          ),
                    label: Padding(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        vertical: 16,
                      ),
                      child: Text(
                        _sendingRating
                            ? 'Enviando...'
                            : 'Enviar calificación',
                      ),
                    ),
                  ),
                ],

                if (_rated) ...[
                  const Card(
                    child: Padding(
                      padding:
                          EdgeInsets.all(
                        20,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 50,
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          Text(
                            '¡Gracias por '
                            'calificarnos!',
                            textAlign:
                                TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],

              if (_isTerminalPaymentStatus(
                payment?.status,
              )) ...[
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      20,
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          size: 48,
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        Text(
                          'El pago está en estado '
                          '${payment?.status}.',
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              if (paymentConfirmed &&
                  _rated)
                OutlinedButton.icon(
                  onPressed: () {
                    context.go('/home');
                  },
                  icon: const Icon(
                    Icons.home,
                  ),
                  label: const Padding(
                    padding:
                        EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    child: Text(
                      'Volver al inicio',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 7,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label),
          ),

          const SizedBox(width: 16),

          Text(
            value,
            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}