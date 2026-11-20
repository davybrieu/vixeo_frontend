/// Android / iOS (and the tests): the device itself makes a scraper's requests.
///
/// Not the [ApiClient] (`core/api`): that one carries the Vixeo token, which a third-party site
/// must never see. This client is plain: no token, no profile, nothing of the account.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'scraper_guard.dart';
import 'scraper_http.dart';
import 'scraper_models.dart';

/// A browser's way of introducing itself: many sites turn away anything else. A scraper may send
/// its own `user-agent` (Nuvio adds one too when the scraper sends none).
const _userAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Mobile Safari/537.36';

class DirectScraperHttp implements ScraperHttp {
  DirectScraperHttp({
    Dio? dio,
    this.limits = ScraperLimits.standard,
    Future<List<InternetAddress>> Function(String)? lookup,
  })
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: limits.request,
              receiveTimeout: limits.request,
              sendTimeout: limits.request,
            ),
          ),
      _lookup = lookup ?? InternetAddress.lookup;

  final Dio _dio;
  final ScraperLimits limits;
  final Future<List<InternetAddress>> Function(String host) _lookup;

  @override
  Future<ScraperHttpResponse> send(ScraperHttpRequest request) async {
    var url = ScraperGuard.upgrade(request.url);
    // As in Nuvio, the HTTP stack chooses the compression and undoes it: a scraper that asks for
    // another one (`br`…) would get bytes it cannot read.
    final headers = {
      for (final e in request.headers.entries)
        if (e.key.toLowerCase() != 'accept-encoding') e.key: e.value,
    };
    var method = request.method;
    var body = request.body;
    for (var hop = 0; hop <= limits.redirects; hop++) {
      final refused = ScraperGuard.check(url);
      if (refused != null) throw ScraperException(refused);
      await _checkResolved(Uri.parse(url).host);

      final cancel = CancelToken();
      final Response<ResponseBody> response;
      try {
        response = await _dio.request<ResponseBody>(
          url,
          data: body,
          cancelToken: cancel,
          options: Options(
            method: method,
            headers: {
              'user-agent': _userAgent,
              // Nuvio's default for a body (OkHttp's): scrapers written for it may not say.
              if (body != null) 'content-type': 'application/x-www-form-urlencoded',
              ...headers,
            },
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
      } on DioException catch (e) {
        throw ScraperException(_describe(e));
      }

      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      if (request.followRedirects && location != null && const {301, 302, 303, 307, 308}.contains(status)) {
        cancel.cancel();
        final next = Uri.tryParse(url)?.resolve(location);
        if (next == null) throw const ScraperException('redirection invalide');
        url = ScraperGuard.upgrade(next.toString());
        if (status != 307 && status != 308) {
          method = 'GET';
          body = null;
        }
        continue;
      }

      final (:bytes, :cut) = await _read(response.data!, cancel);
      return ScraperHttpResponse(
        status: status,
        statusText: response.statusMessage ?? '',
        headers: {for (final e in response.headers.map.entries) e.key.toLowerCase(): e.value.join(', ')},
        body: decodeScraperBody(bytes, response.headers.value('content-type')) + (cut ? ScraperGuard.truncated : ''),
        url: url,
      );
    }
    throw const ScraperException('trop de redirections');
  }

  /// The body, cut at the limit (the connection is dropped, the rest is not downloaded); [cut] says
  /// whether something was left out.
  Future<({Uint8List bytes, bool cut})> _read(ResponseBody body, CancelToken cancel) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      builder.add(chunk);
      if (builder.length > limits.responseBytes) {
        cancel.cancel();
        break;
      }
    }
    final all = builder.takeBytes();
    if (all.length <= limits.responseBytes) return (bytes: all, cut: false);
    return (bytes: Uint8List.sublistView(all, 0, limits.responseBytes), cut: true);
  }

  /// A name that leads to a private address is refused like a private address (a scraper could
  /// otherwise reach a box on the local network through a domain name). The name is resolved again
  /// by the HTTP stack just after: the server's proxy pins the checked address, a phone cannot.
  Future<void> _checkResolved(String host) async {
    if (InternetAddress.tryParse(host) != null) return;
    final List<InternetAddress> addresses;
    try {
      addresses = await _lookup(host);
    } on SocketException {
      throw const ScraperException('hôte introuvable');
    }
    for (final address in addresses) {
      final private = address.type == InternetAddressType.IPv4
          ? ScraperGuard.isPrivateV4(address.rawAddress)
          : ScraperGuard.isPrivateV6(address.address);
      if (private || address.isLoopback || address.isLinkLocal || address.isMulticast) {
        throw const ScraperException('adresse privée interdite');
      }
    }
  }

  static String _describe(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => 'délai dépassé',
    _ => 'requête impossible',
  };
}

/// The text of a body, in the charset its `Content-Type` names, as Nuvio reads it: Latin-1 for
/// `iso-8859-1` / `latin1` / `windows-1252` (old French sites), UTF-8 otherwise (and when nothing
/// is said).
String decodeScraperBody(List<int> bytes, String? contentType) {
  final charset = RegExp(r'charset\s*=\s*"?([\w.:-]+)', caseSensitive: false).firstMatch(contentType ?? '')?.group(1);
  return switch (charset?.toLowerCase()) {
    'iso-8859-1' || 'iso8859-1' || 'latin1' || 'latin-1' || 'windows-1252' || 'cp1252' => latin1.decode(bytes),
    _ => utf8.decode(bytes, allowMalformed: true),
  };
}
