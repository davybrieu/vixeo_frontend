import 'package:dio/dio.dart';

/// Error returned by the Vixeo API (messages are already in French), or a network failure.
class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.fieldErrors = const {}});

  /// Builds an exception from a Dio error, reading the API's `{message, errors}` body.
  factory ApiException.fromDio(DioException error) {
    final response = error.response;

    if (response == null) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => const ApiException('Le serveur met trop de temps à répondre. Réessayez.'),
        DioExceptionType.cancel => const ApiException('Requête annulée.'),
        _ => const ApiException('Impossible de joindre le serveur. Vérifiez votre connexion.'),
      };
    }

    final data = response.data;
    var message = 'Une erreur est survenue (${response.statusCode}).';
    final fields = <String, List<String>>{};

    if (data is Map) {
      if (data['message'] is String && (data['message'] as String).isNotEmpty) {
        message = data['message'] as String;
      }
      final errors = data['errors'];
      if (errors is Map) {
        for (final entry in errors.entries) {
          final value = entry.value;
          if (value is List) {
            fields[entry.key.toString()] = value.map((e) => e.toString()).toList();
          }
        }
      }
    }

    // A validation error's top message duplicates the first field error: prefer the latter.
    if (fields.isNotEmpty && response.statusCode == 422) {
      message = fields.values.first.first;
    }

    return ApiException(message, status: response.statusCode, fieldErrors: fields);
  }

  final String message;
  final int? status;

  /// Validation errors by field (`email`, `pin`…).
  final Map<String, List<String>> fieldErrors;

  String? field(String name) => fieldErrors[name]?.first;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;

  @override
  String toString() => message;
}
