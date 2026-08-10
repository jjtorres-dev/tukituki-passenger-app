import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/passenger_ride.dart';
import '../domain/passenger_ride_offer.dart';
import '../domain/passenger_ride_start_code.dart';
import '../domain/ride_receipt.dart';

final rideRepositoryProvider =
    Provider<RideRepository>((ref) {
  return RideRepository(
    ref.watch(dioProvider),
  );
});

class RideRepository {
  RideRepository(this._dio);

  final Dio _dio;

  Future<PassengerRide> createRide({
    required String fareQuoteId,
    required String passengerOfferFare,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'passenger/rides',
      data: {
        'fareQuoteId': fareQuoteId,
        'passengerOfferFare': passengerOfferFare,
        'paymentMethod': 'CASH',
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return PassengerRide.fromJson(data);
  }

  Future<PassengerRide?> getActiveRide() async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>(
        'passenger/rides/active',
      );

      final data = response.data;

      if (data == null) {
        return null;
      }

      return PassengerRide.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  Future<PassengerRide> getRide(
    String rideId,
  ) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'passenger/rides/$rideId',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El viaje no pudo ser consultado.',
      );
    }

    return PassengerRide.fromJson(data);
  }

  Future<List<PassengerRideOffer>> getRideOffers(
    String rideId,
  ) async {
    final response =
        await _dio.get<List<dynamic>>(
      'passenger/rides/$rideId/offers',
    );

    final data =
        response.data ?? const <dynamic>[];

    final offers = <PassengerRideOffer>[];

    for (final item in data) {
      if (item is! Map) {
        if (kDebugMode) {
          debugPrint(
            'Ignorando propuesta inválida: '
            'el elemento no es un objeto JSON.',
          );
        }

        continue;
      }

      try {
        final offer = PassengerRideOffer.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (offer.offerId.trim().isEmpty ||
            offer.rideId.trim().isEmpty) {
          throw const FormatException(
            'La propuesta no tiene offerId o rideId.',
          );
        }

        offers.add(offer);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'Ignorando propuesta inválida: $error',
          );
        }
      }
    }

    return offers;
  }

  Future<PassengerRide> selectRideOffer({
    required String rideId,
    required String offerId,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'passenger/rides/$rideId/offers/$offerId/select',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return PassengerRide.fromJson(data);
  }

  Future<PassengerRideStartCode> getStartCode(
    String rideId,
  ) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'passenger/rides/$rideId/start-code',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'No se pudo obtener el código de inicio.',
      );
    }

    return PassengerRideStartCode.fromJson(data);
  }

  Future<RideReceipt> getReceipt(
    String rideId,
  ) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'passenger/rides/$rideId/receipt',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'No se pudo obtener el recibo.',
      );
    }

    return RideReceipt.fromJson(data);
  }

  Future<void> submitRating({
    required String rideId,
    required int score,
    String? comment,
    List<String> tags = const [],
  }) async {
    await _dio.post<Map<String, dynamic>>(
      'passenger/rides/$rideId/rating',
      data: {
        'score': score,
        if (comment != null &&
            comment.trim().isNotEmpty)
          'comment': comment.trim(),
        if (tags.isNotEmpty)
          'tags': tags,
      },
    );
  }
}
