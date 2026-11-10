import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/features/tv/tv_repository.dart';

/// Answers each request with the response whose path matches, and records the requests.
class RoutingAdapter implements HttpClientAdapter {
  RoutingAdapter(this.routes);

  final List<(String, Object, int)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    requests.add(options);
    for (final (path, body, status) in routes) {
      if (options.path == path) {
        return ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }
    }
    return ResponseBody.fromString(
      '{}',
      404,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TvRepository repository(RoutingAdapter adapter) => TvRepository(
  ApiClient(
    token: () => 't',
    profileId: () => 2,
    dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
  ),
);

void main() {
  test('lists categories from the neutral /tv endpoint', () async {
    final adapter = RoutingAdapter([
      (
        '/tv/categories',
        {
          'data': [
            {'id': 'Sport', 'name': 'Sport', 'parent_id': null},
            {'id': 'Info', 'name': 'Info'},
          ],
        },
        200,
      ),
    ]);

    final categories = await repository(adapter).categories();

    expect(categories.map((c) => c.id), ['Sport', 'Info']);
    expect(categories.first.name, 'Sport');
    expect(adapter.requests.single.path, '/tv/categories');
  });

  test('passes category_id and q to the channels endpoint', () async {
    final adapter = RoutingAdapter([
      (
        '/tv/channels',
        {
          'data': [
            {'id': 'tf1', 'name': 'TF1', 'category_id': 'Généralistes', 'logo': 'https://logo.test/tf1.png'},
          ],
        },
        200,
      ),
    ]);

    final channels = await repository(adapter).channels(categoryId: 'Généralistes', query: 'tf');

    expect(channels.single.id, 'tf1');
    expect(channels.single.logo, 'https://logo.test/tf1.png');
    final request = adapter.requests.single;
    expect(request.path, '/tv/channels');
    expect(request.queryParameters, {'category_id': 'Généralistes', 'q': 'tf'});
  });

  test('resolves a channel stream, keeping the headers to send', () async {
    final adapter = RoutingAdapter([
      (
        '/tv/channels/tf1/stream',
        {
          'data': {
            'url': 'https://cdn.test/tf1/master.m3u8',
            'format': 'hls',
            'headers': {'User-Agent': 'SomeApp/1'},
          },
        },
        200,
      ),
    ]);

    final stream = await repository(adapter).stream('tf1');

    expect(stream.url, 'https://cdn.test/tf1/master.m3u8');
    expect(stream.format, 'hls');
    expect(stream.headers['User-Agent'], 'SomeApp/1');
    expect(adapter.requests.single.path, '/tv/channels/tf1/stream');
  });

  test('rejects a stream without a URL', () async {
    final adapter = RoutingAdapter([
      (
        '/tv/channels/tf1/stream',
        {
          'data': {'url': '', 'format': 'hls'},
        },
        200,
      ),
    ]);

    expect(() => repository(adapter).stream('tf1'), throwsA(isA<ApiException>()));
  });

  test('tolerates a non-list payload for channels', () async {
    final adapter = RoutingAdapter([
      ('/tv/channels', {'data': 'nope'}, 200),
    ]);

    expect(await repository(adapter).channels(), isEmpty);
  });
}
