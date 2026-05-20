import 'package:dio/dio.dart';

import '../storage/token_storage.dart';
import 'host_resolver.dart';

class ApiConfig {
  static String get baseHost => HostResolver.cached ?? HostResolver.fallbackHost;
  static String get baseUrl => '$baseHost/api/v1';
  static String wsUrl(String token) =>
      '${baseHost.replaceFirst('http', 'ws')}/ws?token=$token';
}

class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.baseUrl = ApiConfig.baseUrl;
          final token = await TokenStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await TokenStorage.clear();
          }
          final isConn = e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout;
          final alreadyRetried = e.requestOptions.extra['ziggo_retry'] == true;
          if (isConn && !alreadyRetried) {
            await HostResolver.resolve(forceRefresh: true);
            try {
              final req = e.requestOptions;
              req.baseUrl = ApiConfig.baseUrl;
              req.extra['ziggo_retry'] = true;
              final r = await _dio.fetch(req);
              return handler.resolve(r);
            } catch (_) {}
          }
          handler.next(e);
        },
      ),
    );
  }

  static final ApiClient _instance = ApiClient._();
  static ApiClient get instance => _instance;

  late final Dio _dio;
  Dio get dio => _dio;

  static Future<void> init() async {
    await HostResolver.resolve();
    _instance._dio.options.baseUrl = ApiConfig.baseUrl;
  }
}
