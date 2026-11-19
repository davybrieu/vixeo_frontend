import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/features/addons/scraper_guard.dart';
import 'package:vixeo/features/addons/scraper_models.dart';
import 'package:vixeo/features/catalog/models.dart';

import 'scraper_fakes.dart';

void main() {
  group('ScraperGuard (the same cases as tools/scraper-runner/test.mjs)', () {
    test('refuses what a scraper must never reach', () {
      const refused = [
        'http://example.com/x',
        'https://localhost/x',
        'https://127.0.0.1/x',
        'https://10.1.2.3/x',
        'https://192.168.0.5/x',
        'https://172.20.0.1/x',
        'https://169.254.169.254/latest',
        'https://[::1]/x',
        'https://[fd00::1]/x',
        'https://[::ffff:127.0.0.1]/x',
        'https://nas.local/x',
        'https://intranet/x',
        'https://user:pw@example.com/x',
        'ftp://example.com/x',
        'https://0x7f000001/x',
        'https://2130706433/x',
        'https://[::]/x',
        'https://[0:0:0:0:0:0:0:1]/x',
        'https://[fe80::1]/x',
        'https://[ff02::1]/x',
        'https://[64:ff9b::7f00:1]/x',
        'https://[2002:7f00:1::]/x',
        'https://127.1/x',
        'https://[::ffff:10.0.0.1]/x',
        'pas une adresse',
      ];
      for (final url in refused) {
        expect(ScraperGuard.check(url), isNotNull, reason: url);
      }
    });

    test('lets public https addresses through', () {
      const allowed = [
        'https://example.com/x',
        'https://api.example.com/find?id=550&q=ab',
        'https://8.8.8.8/x',
        'https://[2606:4700:4700::1111]/x',
        'https://[::ffff:8.8.8.8]/x',
        'https://[64:ff9b::808:808]/x',
      ];
      for (final url in allowed) {
        expect(ScraperGuard.check(url), isNull, reason: url);
      }
    });

    test('explains the refusal', () {
      expect(ScraperGuard.check('http://example.com/'), 'seul https est autorisé');
      expect(ScraperGuard.check('https://192.168.0.5/'), 'adresse privée interdite');
      expect(ScraperGuard.check('https://nas.local/'), 'hôte local interdit');
    });
  });

  group('repository manifest', () {
    test('reads the scrapers, with their defaults', () {
      final manifest = RepositoryManifest.parse(manifestJson(), fallbackName: 'x');

      expect(manifest.name, 'Dépôt test');
      expect(manifest.version, '1.0.0');
      expect(manifest.scrapers.map((s) => s.id), ['films', 'series', 'tout']);
      expect(manifest.scrapers[0].types, {'movie'});
      expect(manifest.scrapers[0].version, '1.2.0');
      // No `supportedTypes`: both.
      expect(manifest.scrapers[2].types, {'movie', 'tv'});
      expect(manifest.scrapers[2].enabled, isTrue);
    });

    test('accepts `providers`, a bare list, and a repository without a name', () {
      final entry = {'id': 'a', 'filename': 'a.js'};
      expect(RepositoryManifest.parse({'providers': [entry]}, fallbackName: 'host.test').name, 'host.test');
      expect(RepositoryManifest.parse([entry], fallbackName: 'host.test').scrapers.single.name, 'a');
    });

    test('leaves out entries that cannot be used, and duplicates', () {
      final manifest = RepositoryManifest.parse({
        'scrapers': [
          {'id': 'ok', 'filename': 'ok.js', 'enabled': false, 'supportedTypes': ['movie', 'anime']},
          {'id': 'ok', 'filename': 'again.js'},
          {'id': 'sans fichier'},
          {'id': 'mauvais id !', 'filename': 'x.js'},
          {'filename': 'sans-id.js'},
          'texte',
          null,
        ],
      }, fallbackName: 'x');

      expect(manifest.scrapers.map((s) => s.id), ['ok']);
      expect(manifest.scrapers.single.filename, 'ok.js');
      expect(manifest.scrapers.single.enabled, isFalse);
      expect(manifest.scrapers.single.types, {'movie'});
    });

    test('refuses what is not a manifest, or has nothing usable', () {
      for (final json in [null, 'texte', 42, <String, Object?>{}, {'scrapers': <Object>[]}, {'scrapers': 'non'}]) {
        expect(() => RepositoryManifest.parse(json, fallbackName: 'x'), throwsA(isA<ScraperException>()), reason: '$json');
      }
    });
  });

  group('repository address', () {
    test('keeps a manifest address, and completes a folder with manifest.json', () {
      expect(ScraperRepo.normalizeUrl('  https://repo.test/a/manifest.json '), 'https://repo.test/a/manifest.json');
      expect(ScraperRepo.normalizeUrl('https://repo.test'), 'https://repo.test/manifest.json');
      expect(ScraperRepo.normalizeUrl('https://repo.test/plugins/'), 'https://repo.test/plugins/manifest.json');
      expect(ScraperRepo.normalizeUrl('https://repo.test/m.json#haut'), 'https://repo.test/m.json');
    });

    test('refuses an address that is not https, or not an address', () {
      for (final text in ['', '   ', 'repo.test/manifest.json', 'http://repo.test/m.json', 'ftp://repo.test/m.json', 'https://']) {
        expect(() => ScraperRepo.normalizeUrl(text), throwsA(isA<ScraperException>()), reason: text);
      }
      expect(() => ScraperRepo.normalizeUrl('https://u:p@repo.test/m.json'), throwsA(isA<ScraperException>()));
    });

    test('finds the file of a scraper from the manifest address', () {
      final repo = testRepo();
      expect(repo.fileOf(repo.scrapers[0]).toString(), 'https://repo.test/providers/films.js');
      expect(repo.fileOf(repo.scrapers[2]).toString(), 'https://cdn.test/tout.js');
    });
  });

  group('installed repositories', () {
    test('give each scraper a key and a provider id that find it again', () {
      final repo = testRepo();
      final films = repo.scrapers.first;

      expect(films.key, '${repo.id}:films');
      expect(films.providerId, 'scraper:${repo.id}:films');
      final found = findScraper([repo], films.providerId);
      expect(found?.scraper.id, 'films');
      expect(found?.repo.url, repoUrl);
      expect(findScraper([repo], 'scraper:inconnu:films'), isNull);
      expect(findScraper([repo], 'addon:12'), isNull);
      expect(findScraper(const [], films.providerId), isNull);
    });

    test('know which titles a scraper handles', () {
      final repo = testRepo();
      expect(repo.scrapers[0].supports(MediaType.movie), isTrue);
      expect(repo.scrapers[0].supports(MediaType.tv), isFalse);
      expect(repo.scrapers[1].supports(MediaType.tv), isTrue);
      expect(repo.scrapers[2].supports(MediaType.movie) && repo.scrapers[2].supports(MediaType.tv), isTrue);
    });

    test('are kept as JSON with the person’s choices, and unreadable data is an empty list', () {
      final repo = testRepo();
      final changed = repo.copyWith(
        scrapers: [
          repo.scrapers[0].copyWith(enabled: false, mode: ScraperMode.server),
          ...repo.scrapers.skip(1),
        ],
      );

      final back = ScraperRepo.decodeList(ScraperRepo.encodeList([changed]));

      expect(back.single.url, repoUrl);
      expect(back.single.id, repo.id);
      expect(back.single.scrapers.map((s) => s.id), ['films', 'series', 'tout']);
      expect(back.single.scrapers[0].enabled, isFalse);
      expect(back.single.scrapers[0].mode, ScraperMode.server);
      expect(back.single.scrapers[1].mode, ScraperMode.device);
      expect(back.single.scrapers[0].types, {'movie'});
      for (final bad in [null, '', 'pas du json', '{"a":1}', '[1,"x",{"url":null}]']) {
        expect(ScraperRepo.decodeList(bad), isEmpty, reason: '$bad');
      }
    });

    test('keep the person’s choices and order when the manifest is read again', () {
      final repo = testRepo();
      final chosen = repo.copyWith(
        scrapers: [
          repo.scrapers[2], // moved first
          repo.scrapers[0].copyWith(enabled: false, mode: ScraperMode.server),
          repo.scrapers[1],
        ],
      );
      final manifest = RepositoryManifest.parse({
        'name': 'Nouveau nom',
        'scrapers': [
          {'id': 'films', 'name': 'Films libres 2', 'filename': 'providers/films.js', 'version': '2.0.0'},
          {'id': 'tout', 'name': 'Tout', 'filename': 'https://cdn.test/tout.js'},
          {'id': 'neuf', 'name': 'Neuf', 'filename': 'providers/neuf.js'},
          // `series` is gone from the repository.
        ],
      }, fallbackName: 'x');

      final updated = chosen.updatedWith(manifest);

      expect(updated.name, 'Nouveau nom');
      expect(updated.scrapers.map((s) => s.id), ['tout', 'films', 'neuf']);
      expect(updated.scrapers[1].name, 'Films libres 2');
      expect(updated.scrapers[1].version, '2.0.0');
      expect(updated.scrapers[1].enabled, isFalse);
      expect(updated.scrapers[1].mode, ScraperMode.server);
      expect(updated.scrapers[2].enabled, isTrue);
    });
  });

  group('streams', () {
    test('keeps the playable links of a scraper’s answer and what describes them', () {
      final streams = ScraperStream.parseList([
        {
          'url': ' https://cdn.test/1.m3u8 ',
          'title': 'Serveur 1',
          'quality': 1080,
          'size': '1.2 GB',
          'headers': {'Referer': 'https://x.test/', 'n': 3, 'mauvais': {}},
        },
        {'url': 'javascript:alert(1)'},
        {'url': 'file:///etc/passwd'},
        {'url': 'https://'},
        {'name': 'sans lien'},
        null,
        'texte',
        {'url': 'http://cdn.test/2.mp4', 'name': '  Nom  '},
      ]);

      expect(streams.map((s) => s.url), ['https://cdn.test/1.m3u8', 'http://cdn.test/2.mp4']);
      expect(streams[0].name, 'Serveur 1');
      expect(streams[0].quality, '1080');
      expect(streams[0].size, '1.2 GB');
      expect(streams[0].headers, {'Referer': 'https://x.test/', 'n': '3'});
      expect(streams[0].streamType, 'm3u8');
      expect(streams[1].name, 'Nom');
      expect(streams[1].streamType, 'mp4');
      expect(ScraperStream.parseList('pas une liste'), isEmpty);
    });

    test('keeps 50 links at most', () {
      final many = [for (var i = 0; i < 80; i++) {'url': 'https://cdn.test/$i'}];
      expect(ScraperStream.parseList(many), hasLength(ScraperStream.maxPerScraper));
    });

    test('writes a label for the sources panel, which reads the quality in it', () {
      const stream = ScraperStream(url: 'https://cdn.test/a', name: 'Serveur 1', quality: '1080p', size: '1.2 GB');
      expect(stream.label('Films libres'), 'Serveur 1 · 1080p · 1.2 GB');
      expect(const ScraperStream(url: 'https://cdn.test/a').label('Films libres'), 'Films libres');
      expect(const ScraperStream(url: 'https://cdn.test/a', quality: '720p').label('Films libres'), 'Films libres · 720p');
      expect(const ScraperStream(url: 'https://cdn.test/a?x=.mp4').streamType, isNull);
    });
  });
}
