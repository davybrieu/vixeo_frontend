/// The requests a scraper makes, done by the app (never by the scraper itself).
///
/// A scraper has no network of its own: its `fetch` becomes a [ScraperHttpRequest] that the host
/// checks ([ScraperGuard]) and hands to a [ScraperHttp]. On Android and iOS that is
/// `DirectScraperHttp` (the device itself asks, `scraper_http_io.dart`); in a browser it is
/// [ProxyScraperHttp] (the Vixeo server asks, because a page cannot read most other sites: CORS).
library;

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import 'scraper_models.dart';

@immutable
class ScraperHttpRequest {
  const ScraperHttpRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.followRedirects = true,
  });

  factory ScraperHttpRequest.fromMessage(Map<dynamic, dynamic> message) => ScraperHttpRequest(
    url: '${message['url']}',
    method: '${message['method'] ?? 'GET'}'.toUpperCase(),
    headers: {
      for (final e in message['headers'] is Map ? (message['headers'] as Map).entries : const <MapEntry>[])
        '${e.key}'.toLowerCase(): '${e.value}',
    },
    body: message['body'] is String ? message['body'] as String : null,
    followRedirects: message['redirect'] != 'manual',
  );

  final String url;
  final String method;

  /// Header names in lower case.
  final Map<String, String> headers;
  final String? body;
  final bool followRedirects;
}

@immutable
class ScraperHttpResponse {
  const ScraperHttpResponse({
    required this.status,
    this.statusText = '',
    this.headers = const {},
    this.body = '',
    required this.url,
  });

  final int status;
  final String statusText;

  /// Header names in lower case.
  final Map<String, String> headers;

  /// The text of the answer (UTF-8), cut at [ScraperLimits.responseBytes].
  final String body;

  /// The address that finally answered (after the redirections).
  final String url;

  Map<String, Object?> toJson() => {
    'status': status,
    'statusText': statusText,
    'headers': headers,
    'body': body,
    'url': url,
  };
}

/// Does ONE request, after the guard let it through. Throws a [ScraperException] when it cannot.
abstract class ScraperHttp {
  Future<ScraperHttpResponse> send(ScraperHttpRequest request);
}

/// Asks the Vixeo server to do the request (`POST /scrapers/fetch`, `docs/scrapers.md` §6).
class ProxyScraperHttp implements ScraperHttp {
  ProxyScraperHttp(this._api);

  final ApiClient _api;

  @override
  Future<ScraperHttpResponse> send(ScraperHttpRequest request) async {
    try {
      final json = await _api.post(
        '/scrapers/fetch',
        body: {
          'url': request.url,
          'method': request.method,
          'headers': request.headers,
          'body': request.body,
          'redirect': request.followRedirects ? 'follow' : 'manual',
        },
        receiveTimeout: const Duration(seconds: 20),
      );
      final data = json['data'] is Map ? json['data'] as Map : json;
      return ScraperHttpResponse(
        status: (data['status'] as num?)?.toInt() ?? 502,
        statusText: data['status_text'] as String? ?? '',
        headers: {
          for (final e in data['headers'] is Map ? (data['headers'] as Map).entries : const <MapEntry>[])
            '${e.key}'.toLowerCase(): '${e.value}',
        },
        body: data['body'] as String? ?? '',
        url: data['url'] as String? ?? request.url,
      );
    } on ApiException catch (e) {
      throw ScraperException(e.message);
    }
  }
}
