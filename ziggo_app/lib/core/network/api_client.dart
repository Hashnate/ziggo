import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

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
    if (!kIsWeb) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
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
            // Directly use the IP fallback — no DNS, no probing, instant.
            final ipBase = '${HostResolver.fallbackHost}/api/v1';
            try {
              final req = e.requestOptions;
              req.baseUrl = ipBase;
              req.extra['ziggo_retry'] = true;
              final r = await _dio.fetch(req);
          // Direct IP worked — cache it for future requests
              HostResolver.override(HostResolver.fallbackHost);
              return handler.resolve(r);
            } catch (_) {}
          }

          final cleanMessage = sanitizeString(e.message ?? '');
          final cleanResponse = e.response != null
              ? Response(
                  requestOptions: e.response!.requestOptions,
                  data: sanitizeData(e.response!.data),
                  statusCode: e.response!.statusCode,
                  statusMessage: sanitizeString(e.response!.statusMessage ?? ''),
                  isRedirect: e.response!.isRedirect,
                  redirects: e.response!.redirects,
                  extra: e.response!.extra,
                  headers: e.response!.headers,
                )
              : null;
          final cleanRequestOptions = RequestOptions(
            path: sanitizeString(e.requestOptions.path),
            baseUrl: sanitizeString(e.requestOptions.baseUrl),
            headers: e.requestOptions.headers,
            queryParameters: e.requestOptions.queryParameters,
            data: sanitizeData(e.requestOptions.data),
            method: e.requestOptions.method,
            extra: e.requestOptions.extra,
            responseType: e.requestOptions.responseType,
            contentType: e.requestOptions.contentType,
            validateStatus: e.requestOptions.validateStatus,
            receiveTimeout: e.requestOptions.receiveTimeout,
            sendTimeout: e.requestOptions.sendTimeout,
            connectTimeout: e.requestOptions.connectTimeout,
          );
          final cleanException = DioException(
            requestOptions: cleanRequestOptions,
            response: cleanResponse,
            type: e.type,
            error: e.error,
            stackTrace: e.stackTrace,
            message: cleanMessage.isEmpty ? null : cleanMessage,
          );
          handler.next(cleanException);
        },
      ),
    );
  }

  static String sanitizeString(String text) {
    // Matches http://..., https://..., ws://..., wss://..., ftp://... up to a space, quote, or closing paren/bracket/comma
    final urlRegex = RegExp(r'(https?|wss?|ftp)://[^\s"')\]},]+', caseSensitive: false);
    // Matches IP addresses (like 187.127.152.141 or 10.0.2.2) with optional port
    final ipRegex = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?\b');
    // Matches any domain name ending with .lk or localhost
    final hostRegex = RegExp(r'\b(ziggo\.lk|localhost)(:\d+)?\b', caseSensitive: false);
    // Matches paths starting with /api/v1/ or /ws
    final pathRegex = RegExp(r'/(api/v1|ws)[^\s"')\]},]*', caseSensitive: false);

    var sanitized = text;
    sanitized = sanitized.replaceAll(urlRegex, '[endpoint]');
    sanitized = sanitized.replaceAll(ipRegex, '[endpoint]');
    sanitized = sanitized.replaceAll(hostRegex, '[endpoint]');
    sanitized = sanitized.replaceAll(pathRegex, '[endpoint]');

    // Clean up remaining references:
    sanitized = sanitized.replaceAll(RegExp(r'\s*\(?URL:\s*\[endpoint\]\)?', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'\s*\[?url:\s*\[endpoint\]\]?', caseSensitive: false), '');
    sanitized = sanitized.replaceAll(RegExp(r'\s*\(\s*\[endpoint\]\s*\)'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\s*\[endpoint\]'), '');
    return sanitized.trim();
  }

  static dynamic sanitizeData(dynamic data) {
    if (data is String) {
      return sanitizeString(data);
    } else if (data is Map) {
      return data.map((key, value) => MapEntry(key, sanitizeData(value)));
    } else if (data is List) {
      return data.map((e) => sanitizeData(e)).toList();
    }
    return data;
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
