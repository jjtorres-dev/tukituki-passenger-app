import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref.watch(dioProvider));
});

final healthReadyProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(healthRepositoryProvider).checkReady();
});

class HealthRepository {
  HealthRepository(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> checkReady() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'health/ready',
    );

    return response.data ?? <String, dynamic>{};
  }
}