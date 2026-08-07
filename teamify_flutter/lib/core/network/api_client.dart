import 'dart:convert';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import '../observability/app_logger.dart';

class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;

  bool _isRefreshing = false;
  void Function()? onAuthFailure;

  ApiClient({
    Dio? dio,
    TokenStorage? tokenStorage,
    this.onAuthFailure,
  })  : dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            ),
        tokenStorage = tokenStorage ?? TokenStorage() {
    this.dio.transformer = BackgroundTransformer()
      ..jsonDecodeCallback = _parseAndDecode;
    this.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: _addAuthHeader,
            onResponse: _handleResponse,
            onError: _handleError,
          ),
        );
  }

  void _handleResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    final start = response.requestOptions.extra['start_time'] as DateTime?;
    if (start != null) {
      final duration = DateTime.now().difference(start);
      final path = response.requestOptions.path;
      AppLogger.trackLatency('api.$path', duration);
    }
    handler.next(response);
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<void> _addAuthHeader(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final skipAuth = options.extra['skipAuth'] == true;
    if (!skipAuth) {
      final token = await tokenStorage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    options.extra['start_time'] = DateTime.now();
    handler.next(options);
  }

  Future<void> _handleError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = error.response?.statusCode;
    final alreadyRetried = error.requestOptions.extra['retried'] == true;

    if (statusCode == 401 && !alreadyRetried && !_isRefreshing) {
      AppLogger.log(
          '401 Unauthorized for ${error.requestOptions.path}. Attempting token refresh...');
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        try {
          final retryOptions = error.requestOptions;
          retryOptions.extra['retried'] = true;
          final accessToken = await tokenStorage.readAccessToken();
          if (accessToken != null) {
            retryOptions.headers['Authorization'] = 'Bearer $accessToken';
          }
          AppLogger.recordMetric('api.retry', 1,
              tags: {'path': error.requestOptions.path});
          final response = await dio.fetch<dynamic>(retryOptions);
          handler.resolve(response);
          return;
        } catch (_) {
          await tokenStorage.clear();
          onAuthFailure?.call();
        }
      } else {
        await tokenStorage.clear();
        onAuthFailure?.call();
      }
    }

    if (error.type == DioExceptionType.cancel) {
      handler.reject(
        DioException(
          requestOptions: error.requestOptions,
          type: error.type,
          error: const ApiException('Request cancelled'),
          message: 'Request cancelled',
        ),
      );
      return;
    }

    AppLogger.error(
        'API Error [${error.response?.statusCode}]: ${error.message}', error);

    final apiException = ApiException.fromResponse(
      statusCode,
      error.response?.data,
    );
    handler.reject(
      DioException(
        requestOptions: error.requestOptions,
        response: error.response,
        type: error.type,
        error: apiException,
        message: apiException.message,
      ),
    );
  }

  Future<bool> _refreshAccessToken() async {
    _isRefreshing = true;
    try {
      final refreshToken = await tokenStorage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        options: Options(
          headers: {'Authorization': 'Bearer $refreshToken'},
          extra: {'skipAuth': true},
        ),
      );
      final token = response.data?['access_token']?.toString();
      if (token == null || token.isEmpty) return false;

      await tokenStorage.saveAccessToken(token);
      return true;
    } catch (_) {
      await tokenStorage.clear();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }
}

// Top-level function for Isolate JSON decoding
dynamic _parseAndDecode(String response) {
  return jsonDecode(response);
}
