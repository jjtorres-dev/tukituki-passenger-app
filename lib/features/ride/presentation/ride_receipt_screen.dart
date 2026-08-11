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
  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _cream = Color(0xFFFFF9EC);
  static const Color _primaryText = Color(0xFF16241C);

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

  String _paymentMethodLabel(
    String? method,
  ) {
    if (method == 'CASH') {
      return 'Efectivo';
    }

    return method ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _cream,
        body: SafeArea(
          child: Center(
            child:
                CircularProgressIndicator(
              color: _green,
            ),
          ),
        ),
      );
    }

    final receipt = _receipt;

    if (receipt == null) {
      return Scaffold(
        backgroundColor: _cream,
        appBar: AppBar(
          backgroundColor: _darkGreen,
          foregroundColor: Colors.white,
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
              style: const TextStyle(
                color: _primaryText,
              ),
            ),
          ),
        ),
      );
    }

    final payment =
        receipt.payment;

    final status = payment?.status;

    final paymentConfirmed =
        status == 'PAID';

    final isTerminal =
        _isTerminalPaymentStatus(status);

    final isPendingFlow =
        !paymentConfirmed && !isTerminal;

    final totalValue =
        payment?.amountDue ??
            receipt.fare.finalFare;

    final hasDistance =
        receipt.actualDistanceMeters > 0;

    final hasDuration =
        receipt.actualDurationSeconds > 0;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _darkGreen,
        foregroundColor: Colors.white,
        title: const Text(
          'Viaje completado',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey(
            'receipt-scroll',
          ),
          padding:
              const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              _Header(
                paymentConfirmed:
                    paymentConfirmed,
                totalValue: totalValue,
              ),

              const SizedBox(height: 24),

              _RouteCard(
                originAddress:
                    receipt.originAddress,
                destinationAddress: receipt
                    .destinationAddress,
                distanceText: hasDistance
                    ? _formatDistance(
                        receipt
                            .actualDistanceMeters,
                      )
                    : null,
                durationText: hasDuration
                    ? _formatDuration(
                        receipt
                            .actualDurationSeconds,
                      )
                    : null,
              ),

              const SizedBox(height: 16),

              _PaymentCard(
                methodLabel:
                    _paymentMethodLabel(
                  payment?.method,
                ),
                totalValue: totalValue,
                cashReceived:
                    payment?.cashReceived,
                changeGiven:
                    payment?.changeGiven,
                paymentConfirmed:
                    paymentConfirmed,
                isTerminal: isTerminal,
                isPendingFlow:
                    isPendingFlow,
                status: status,
              ),

              if (isPendingFlow) ...[
                const SizedBox(height: 16),
                const _RatingLockedCard(),
              ],

              if (paymentConfirmed) ...[
                const SizedBox(height: 24),
                _RatingSection(
                  score: _score,
                  tags: _tags,
                  selectedTags:
                      _selectedTags,
                  sending: _sendingRating,
                  rated: _rated,
                  commentController:
                      _commentController,
                  onScoreChanged: (value) {
                    setState(() {
                      _score = value;
                    });
                  },
                  onTagToggled:
                      (key, selected) {
                    setState(() {
                      if (selected) {
                        if (_selectedTags
                                .length <
                            5) {
                          _selectedTags
                              .add(key);
                        }
                      } else {
                        _selectedTags
                            .remove(key);
                      }
                    });
                  },
                  onSubmit: _submitRating,
                ),
              ],

              const SizedBox(height: 24),

              if (paymentConfirmed &&
                  _rated)
                OutlinedButton.icon(
                  key: const ValueKey(
                    'receipt-home-button',
                  ),
                  style: OutlinedButton
                      .styleFrom(
                    foregroundColor:
                        _darkGreen,
                    side: const BorderSide(
                      color: _darkGreen,
                    ),
                  ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.paymentConfirmed,
    required this.totalValue,
  });

  final bool paymentConfirmed;
  final String totalValue;

  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _secondaryText = Color(0xFF6F7E72);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 46,
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          '¡Gracias por viajar!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: _darkGreen,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          'Tu viaje ha finalizado.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: _secondaryText,
          ),
        ),

        const SizedBox(height: 24),

        Text(
          paymentConfirmed
              ? 'Total pagado'
              : 'Total a pagar',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _secondaryText,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          'S/ $totalValue',
          key: const ValueKey(
            'receipt-total-amount',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: _darkGreen,
          ),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.originAddress,
    required this.destinationAddress,
    required this.distanceText,
    required this.durationText,
  });

  final String originAddress;
  final String destinationAddress;
  final String? distanceText;
  final String? durationText;

  static const Color _green = Color(0xFF1F7A3E);
  static const Color _destinationColor = Color(0xFFD8542C);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _softBorder = Color(0xFFEFE8D4);

  @override
  Widget build(BuildContext context) {
    final hasMetrics =
        distanceText != null ||
            durationText != null;

    return Container(
      decoration: BoxDecoration(
        color: _secondaryCream,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _AddressRow(
            key: const ValueKey(
              'trip-origin',
            ),
            icon: Icons.my_location,
            iconColor: _green,
            label: 'Origen',
            address: originAddress,
          ),

          Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 10,
            ),
            child: Divider(
              height: 1,
              color: _softBorder,
            ),
          ),

          _AddressRow(
            key: const ValueKey(
              'trip-destination',
            ),
            icon: Icons.location_on,
            iconColor: _destinationColor,
            label: 'Destino',
            address: destinationAddress,
          ),

          if (hasMetrics)
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 10,
              ),
              child: Divider(
                height: 1,
                color: _softBorder,
              ),
            ),

          if (distanceText != null)
            _InfoRow(
              key: const ValueKey(
                'receipt-distance-row',
              ),
              label: 'Distancia',
              value: distanceText!,
            ),

          if (durationText != null)
            _InfoRow(
              key: const ValueKey(
                'receipt-duration-row',
              ),
              label: 'Duración',
              value: durationText!,
            ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF6F7E72);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: iconColor,
          size: 22,
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _secondaryText,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                address,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _primaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.methodLabel,
    required this.totalValue,
    required this.cashReceived,
    required this.changeGiven,
    required this.paymentConfirmed,
    required this.isTerminal,
    required this.isPendingFlow,
    required this.status,
  });

  final String methodLabel;
  final String totalValue;
  final String? cashReceived;
  final String? changeGiven;
  final bool paymentConfirmed;
  final bool isTerminal;
  final bool isPendingFlow;
  final String? status;

  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _softBorder = Color(0xFFEFE8D4);
  static const Color _pendingColor = Color(0xFFB8790C);
  static const Color _pendingBackground = Color(0xFFFFF3D9);
  static const Color _destinationColor = Color(0xFFD8542C);
  static const Color _terminalBackground = Color(0xFFFBE7DE);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _secondaryCream,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                color: _darkGreen,
              ),

              const SizedBox(width: 8),

              const Text(
                'Pago',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkGreen,
                ),
              ),

              const Spacer(),

              _StatusPill(
                paymentConfirmed:
                    paymentConfirmed,
                isTerminal: isTerminal,
                status: status,
              ),
            ],
          ),

          const SizedBox(height: 14),

          _InfoRow(
            key: const ValueKey(
              'payment-method-value',
            ),
            label: 'Método',
            value: methodLabel,
          ),

          _InfoRow(
            label: 'Total',
            value: 'S/ $totalValue',
          ),

          if (cashReceived != null)
            _InfoRow(
              key: const ValueKey(
                'payment-cash-received',
              ),
              label: 'Efectivo recibido',
              value: 'S/ $cashReceived',
            ),

          if (changeGiven != null)
            _InfoRow(
              key: const ValueKey(
                'payment-change-given',
              ),
              label: 'Vuelto',
              value: 'S/ $changeGiven',
            ),

          if (isPendingFlow) ...[
            const SizedBox(height: 14),

            const Divider(
              height: 1,
              color: _softBorder,
            ),

            const SizedBox(height: 14),

            const LinearProgressIndicator(
              color: _pendingColor,
              backgroundColor:
                  _pendingBackground,
            ),

            const SizedBox(height: 14),

            const Text(
              'Esperando confirmación '
              'del pago por parte '
              'del conductor...',
              key: ValueKey(
                'payment-waiting-message',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _pendingColor,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Entrega el efectivo '
              'directamente a tu conductor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6F7E72),
              ),
            ),
          ],

          if (isTerminal) ...[
            const SizedBox(height: 14),

            const Divider(
              height: 1,
              color: _softBorder,
            ),

            const SizedBox(height: 14),

            Container(
              key: const ValueKey(
                'payment-status-terminal-note',
              ),
              width: double.infinity,
              padding:
                  const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _terminalBackground,
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: _destinationColor,
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'El pago está en estado '
                      '$status.',
                      style: const TextStyle(
                        color: _destinationColor,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.paymentConfirmed,
    required this.isTerminal,
    required this.status,
  });

  final bool paymentConfirmed;
  final bool isTerminal;
  final String? status;

  static const Color _green = Color(0xFF1F7A3E);
  static const Color _paidBackground = Color(0xFFE3F1E7);
  static const Color _pendingColor = Color(0xFFB8790C);
  static const Color _pendingBackground = Color(0xFFFFF3D9);
  static const Color _destinationColor = Color(0xFFD8542C);
  static const Color _terminalBackground = Color(0xFFFBE7DE);

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color foreground;
    late final Color background;
    late final ValueKey<String> key;

    if (paymentConfirmed) {
      label = 'Pagado';
      foreground = _green;
      background = _paidBackground;
      key = const ValueKey(
        'payment-status-paid',
      );
    } else if (isTerminal) {
      label = status ?? '-';
      foreground = _destinationColor;
      background = _terminalBackground;
      key = const ValueKey(
        'payment-status-terminal',
      );
    } else {
      label = 'Pendiente';
      foreground = _pendingColor;
      background = _pendingBackground;
      key = const ValueKey(
        'payment-status-pending',
      );
    }

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _RatingLockedCard extends StatelessWidget {
  const _RatingLockedCard();

  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);
  static const Color _secondaryText = Color(0xFF6F7E72);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _secondaryCream,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(
            Icons.star_border,
            size: 40,
            color: _secondaryText,
          ),

          const SizedBox(height: 10),

          const Text(
            'Calificar viaje',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _darkGreen,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Podrás calificar tu viaje '
            'cuando el conductor confirme '
            'el pago.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _secondaryText,
            ),
          ),

          const SizedBox(height: 14),

          OutlinedButton.icon(
            key: const ValueKey(
              'rating-disabled-cta',
            ),
            onPressed: null,
            icon: const Icon(
              Icons.star_border,
            ),
            label: const Text(
              'Calificar viaje',
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingSection extends StatelessWidget {
  const _RatingSection({
    required this.score,
    required this.tags,
    required this.selectedTags,
    required this.sending,
    required this.rated,
    required this.commentController,
    required this.onScoreChanged,
    required this.onTagToggled,
    required this.onSubmit,
  });

  final int score;
  final Map<String, String> tags;
  final Set<String> selectedTags;
  final bool sending;
  final bool rated;
  final TextEditingController
      commentController;
  final ValueChanged<int> onScoreChanged;
  final void Function(String key, bool selected)
      onTagToggled;
  final VoidCallback onSubmit;

  static const Color _darkGreen = Color(0xFF123B26);
  static const Color _green = Color(0xFF1F7A3E);
  static const Color _ctaYellow = Color(0xFFFFC72C);
  static const Color _secondaryCream = Color(0xFFFBF7EA);
  static const Color _border = Color(0xFFE7E0CB);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _secondaryCream,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            '¿Cómo estuvo tu viaje?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _darkGreen,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: List.generate(
              5,
              (index) {
                final value = index + 1;

                return IconButton(
                  onPressed: rated
                      ? null
                      : () => onScoreChanged(
                            value,
                          ),
                  iconSize: 40,
                  disabledColor:
                      value <= score
                          ? _ctaYellow
                          : _border,
                  color: value <= score
                      ? _ctaYellow
                      : _border,
                  icon: Icon(
                    value <= score
                        ? Icons.star
                        : Icons.star_border,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          if (!rated) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment:
                  WrapAlignment.center,
              children: tags.entries.map(
                (entry) {
                  final selected =
                      selectedTags.contains(
                    entry.key,
                  );

                  return FilterChip(
                    label: Text(
                      entry.value,
                    ),
                    selected: selected,
                    selectedColor:
                        _ctaYellow
                            .withValues(
                      alpha: 0.35,
                    ),
                    onSelected: (value) =>
                        onTagToggled(
                      entry.key,
                      value,
                    ),
                  );
                },
              ).toList(),
            ),

            const SizedBox(height: 18),

            TextField(
              controller:
                  commentController,
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

            const SizedBox(height: 14),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
              ),
              onPressed:
                  sending ? null : onSubmit,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
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
                  sending
                      ? 'Enviando...'
                      : 'Enviar calificación',
                ),
              ),
            ),
          ],

          if (rated) ...[
            const SizedBox(height: 8),

            const Icon(
              Icons.favorite,
              size: 44,
              color: _green,
            ),

            const SizedBox(height: 8),

            const Text(
              '¡Gracias por calificarnos!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _darkGreen,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  static const Color _primaryText = Color(0xFF16241C);
  static const Color _secondaryText = Color(0xFF6F7E72);

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
            child: Text(
              label,
              style: const TextStyle(
                color: _secondaryText,
              ),
            ),
          ),

          const SizedBox(width: 16),

          Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
