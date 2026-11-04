import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';

/// Answers every request with [status] and [body], and records the requests.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.status, this.body);

  final int status;
  final Object? body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient client(FakeAdapter adapter, {String? token, int? profileId, void Function()? onUnauthorized}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter;
  return ApiClient(token: () => token, profileId: () => profileId, onUnauthorized: onUnauthorized, dio: dio);
}

void main() {
  test('sends the token and the active profile', () async {
    final adapter = FakeAdapter(200, {'data': []});
    await client(adapter, token: 'abc', profileId: 7).get('/profiles');

    final headers = adapter.requests.single.headers;
    expect(headers['Authorization'], 'Bearer abc');
    expect(headers['X-Profile-Id'], '7');
  });

  test('sends neither header when signed out', () async {
    final adapter = FakeAdapter(200, {});
    await client(adapter).get('/catalog/config');

    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    expect(adapter.requests.single.headers.containsKey('X-Profile-Id'), isFalse);
  });

  test('drops null query parameters and turns booleans into 1 / 0', () async {
    final adapter = FakeAdapter(200, {});
    await client(adapter).get('/catalog/home', query: {'type': null, 'watched': false});

    expect(adapter.requests.single.queryParameters, {'watched': 0});
  });

  test('turns a validation error into field messages', () async {
    final adapter = FakeAdapter(422, {
      'message': 'Adresse e-mail ou mot de passe incorrect.',
      'errors': {
        'email': ['Adresse e-mail ou mot de passe incorrect.'],
      },
    });

    await expectLater(
      client(adapter).post('/auth/login', body: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 422)
            .having((e) => e.field('email'), 'email', 'Adresse e-mail ou mot de passe incorrect.')
            .having((e) => e.message, 'message', 'Adresse e-mail ou mot de passe incorrect.'),
      ),
    );
  });

  test('keeps the API message of other errors', () async {
    final adapter = FakeAdapter(403, {'message': "Ce contenu n'est pas disponible sur ce profil."});

    await expectLater(
      client(adapter).get('/catalog/movie/1'),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', "Ce contenu n'est pas disponible sur ce profil."),
      ),
    );
  });

  test('reports an expired session, except on the login request', () async {
    var expired = 0;
    final adapter = FakeAdapter(401, {'message': 'Non authentifié.'});
    final api = client(adapter, token: 'old', onUnauthorized: () => expired++);

    await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
    expect(expired, 1);

    await expectLater(api.post('/auth/login'), throwsA(isA<ApiException>()));
    expect(expired, 1);
  });

  test('explains network failures in French', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/me'),
      type: DioExceptionType.connectionError,
    );
    expect(ApiException.fromDio(error).message, 'Impossible de joindre le serveur. Vérifiez votre connexion.');
  });
}
