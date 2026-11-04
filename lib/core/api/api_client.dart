import 'package:dio/dio.dart';

import '../config.dart';
import 'api_exception.dart';

/// HTTP client for the Vixeo API (`/api/v1`).
///
/// Adds the bearer token and the active profile (`X-Profile-Id`, used by the API
/// to apply the profile's age limit) to every request, and turns errors into
/// [ApiException]s carrying the API's French messages.
class ApiClient {
  ApiClient({
    required String? Function() token,
    required int? Function() profileId,
    void Function()? onUnauthorized,
    Dio? dio,
  }) : _token = token, // ignore: prefer_initializing_formals
       _profileId = profileId, // ignore: prefer_initializing_formals
       _onUnauthorized = onUnauthorized, // ignore: prefer_initializing_formals
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.apiBase,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               headers: {'Accept': 'application/json'},
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final profileId = _profileId();
          if (profileId != null) {
            options.headers['X-Profile-Id'] = '$profileId';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final String? Function() _token;
  final int? Function() _profileId;
  final void Function()? _onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<Map<String, dynamic>> post(String path, {Object? body, Map<String, String>? headers}) => _send(
    () => _dio.post<dynamic>(
      path,
      data: body,
      options: Options(headers: headers),
    ),
  );

  Future<Map<String, dynamic>> put(String path, {Object? body}) => _send(() => _dio.put<dynamic>(path, data: body));

  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _send(() => _dio.patch<dynamic>(path, data: body));

  Future<Map<String, dynamic>> delete(String path, {Map<String, String>? headers}) =>
      _send(() => _dio.delete<dynamic>(path, options: Options(headers: headers)));

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on DioException catch (error) {
      final exception = ApiException.fromDio(error);
      final isLogin = error.requestOptions.path.contains('/auth/');
      if (exception.isUnauthorized && !isLogin) {
        _onUnauthorized?.call();
      }
      throw exception;
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    return {
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value is bool ? ((entry.value as bool) ? 1 : 0) : entry.value,
    };
  }
}
