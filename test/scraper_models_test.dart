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
        'https://192.0.0.8/x',
        'https://192.0.2.1/x',
        'https://0.0.0.0/x',
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
        // 192.0/16 is public apart from 192.0.0/24 and 192.0.2/24 (WordPress.com is in 192.0.78/24).
        'https://192.0.78.9/x',
        'https://172.67.1.1/x',
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

    test('makes a request in http:// in https://, and leaves anything else', () {
      expect(ScraperGuard.upgrade('http://example.com/a?b=1'), 'https://example.com/a?b=1');
      expect(ScraperGuard.upgrade('HTTP://Example.com/'), 'https://Example.com/');
      expect(ScraperGuard.upgrade('https://example.com/'), 'https://example.com/');
      expect(ScraperGuard.upgrade('ftp://example.com/'), 'ftp://example.com/');
      expect(ScraperGuard.check(ScraperGuard.upgrade('http://127.0.0.1/')), 'adresse privée interdite');
    });

    test('has the limits of the Nuvio app', () {
      const limits = ScraperLimits.standard;
      expect(limits.run, const Duration(seconds: 60));
      expect(limits.request, const Duration(seconds: 30));
      expect(limits.timer, limits.run);
      expect(limits.requests, greaterThanOrEqualTo(150));
      expect(limits.streams, ScraperStream.maxPerScraper);
      expect(ScraperGuard.truncated, '\n...[truncated]');
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
    });

    test('accepts `providers`, a bare list, and a repository without a name', () {
      final entry = {'id': 'a', 'filename': 'a.js'};
      expect(RepositoryManifest.parse({'providers': [entry]}, fallbackName: 'host.test').name, 'host.test');
      expect(RepositoryManifest.parse([entry], fallbackName: 'host.test').scrapers.single.name, 'a');
    });

    test('leaves out entries that cannot be used, and duplicates', () {
      final manifest = RepositoryManifest.parse({
        'scrapers': [
          {'id': 'ok', 'filename': 'ok.js', 'supportedTypes': ['movie', 'anime']},
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
      expect(manifest.scrapers.single.types, {'movie'});
    });

    test('leaves out, as Nuvio does, a scraper its author turned off or kept off this platform', () {
      final json = {
        'name': "Gowaru's Repo",
        'version': '1.2.4',
        'scrapers': [
          {'id': 'on', 'filename': 'providers/on.js', 'enabled': true, 'disabledPlatforms': <String>[]},
          {'id': 'off', 'filename': 'providers/off.js', 'enabled': false},
          {'id': 'not-tv', 'filename': 'providers/not-tv.js', 'disabledPlatforms': ['tv']},
          {'id': 'not-android', 'filename': 'providers/x.js', 'disabledPlatforms': ['Android']},
          {'id': 'ios-only', 'filename': 'providers/y.js', 'supportedPlatforms': ['ios']},
          {'id': 'series', 'filename': 'providers/z.js', 'supportedTypes': ['series']},
        ],
      };

      final android = RepositoryManifest.parse(json, fallbackName: 'x', platform: 'android');
      final ios = RepositoryManifest.parse(json, fallbackName: 'x', platform: 'ios');
      final web = RepositoryManifest.parse(json, fallbackName: 'x', platform: 'web');

      expect(android.scrapers.map((s) => s.id), ['on', 'not-tv', 'series']);
      expect(ios.scrapers.map((s) => s.id), ['on', 'not-tv', 'not-android', 'ios-only', 'series']);
      expect(web.scrapers.map((s) => s.id), ['on', 'not-tv', 'not-android', 'series']);
      // Nuvio's "series" is a series.
      expect(android.scrapers.last.types, {'tv'});
      expect(
        () => RepositoryManifest.parse({
          'scrapers': [
            {'id': 'off', 'filename': 'off.js', 'enabled': false},
          ],
        }, fallbackName: 'x'),
        throwsA(isA<ScraperException>()),
      );
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

    test('reads an address the way Nuvio does: folder, missing https, http', () {
      // The address gowaru-nuvio-providers gives in its README, with or without its last slash.
      const gowaru = 'https://raw.githubusercontent.com/Gowaru/gowaru-nuvio-providers/refs/heads/main';
      expect(ScraperRepo.normalizeUrl('$gowaru/'), '$gowaru/manifest.json');
      expect(ScraperRepo.normalizeUrl(gowaru), '$gowaru/manifest.json');
      expect(ScraperRepo.normalizeUrl('repo.test/manifest.json'), 'https://repo.test/manifest.json');
      expect(ScraperRepo.normalizeUrl('http://repo.test/m.json'), 'https://repo.test/m.json');
      expect(ScraperRepo.normalizeUrl('https://repo.test/repo?token=1'), 'https://repo.test/repo/manifest.json?token=1');
    });

    test('turns the GitHub page of a repository into the address of its raw manifest', () {
      expect(
        ScraperRepo.normalizeUrl('https://github.com/Gowaru/gowaru-nuvio-providers'),
        'https://raw.githubusercontent.com/Gowaru/gowaru-nuvio-providers/HEAD/manifest.json',
      );
      expect(
        ScraperRepo.normalizeUrl('github.com/owner/repo.git'),
        'https://raw.githubusercontent.com/owner/repo/HEAD/manifest.json',
      );
      expect(
        ScraperRepo.normalizeUrl('https://github.com/owner/repo/tree/dev/plugins'),
        'https://raw.githubusercontent.com/owner/repo/dev/plugins/manifest.json',
      );
      expect(
        ScraperRepo.normalizeUrl('https://github.com/owner/repo/blob/main/manifest.json'),
        'https://raw.githubusercontent.com/owner/repo/main/manifest.json',
      );
    });

    test('refuses an address that cannot be one', () {
      for (final text in ['', '   ', 'ftp://repo.test/m.json', 'https://', 'pas une adresse']) {
        expect(() => ScraperRepo.normalizeUrl(text), throwsA(isA<ScraperException>()), reason: text);
      }
      expect(() => ScraperRepo.normalizeUrl('https://u:p@repo.test/m.json'), throwsA(isA<ScraperException>()));
    });

    test('finds the file of a scraper from the manifest address', () {
      final repo = testRepo();
      expect(repo.fileOf(repo.scrapers[0]).toString(), 'https://repo.test/providers/films.js');
      expect(repo.fileOf(repo.scrapers[2]).toString(), 'https://cdn.test/tout.js');
      // As in Nuvio: a leading slash still means the manifest's folder; http becomes https.
      final nested = ScraperRepo.fromManifest(
        'https://raw.test/owner/repo/main/manifest.json?v=2',
        RepositoryManifest.parse({
          'scrapers': [
            {'id': 'a', 'filename': '/providers/a.js'},
            {'id': 'b', 'filename': 'http://cdn.test/b.js'},
          ],
        }, fallbackName: 'x'),
      );
      expect(nested.fileOf(nested.scrapers[0]).toString(), 'https://raw.test/owner/repo/main/providers/a.js');
      expect(nested.fileOf(nested.scrapers[1]).toString(), 'https://cdn.test/b.js');
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

    test('are kept as JSON, and unreadable data is an empty list', () {
      final repo = testRepo();

      final back = ScraperRepo.decodeList(ScraperRepo.encodeList([repo]));

      expect(back.single.url, repoUrl);
      expect(back.single.id, repo.id);
      expect(back.single.scrapers.map((s) => s.id), ['films', 'series', 'tout']);
      expect(back.single.mode, ScraperMode.device);
      expect(back.single.scrapers[0].types, {'movie'});
      for (final bad in [null, '', 'pas du json', '{"a":1}', '[1,"x",{"url":null}]']) {
        expect(ScraperRepo.decodeList(bad), isEmpty, reason: '$bad');
      }
    });

    test('take the manifest’s scrapers when it is read again, and stay on or off', () {
      final repo = testRepo().copyWith(enabled: false);
      final manifest = RepositoryManifest.parse({
        'name': 'Nouveau nom',
        'execution': 'server',
        'scrapers': [
          {'id': 'tout', 'name': 'Tout', 'filename': 'https://cdn.test/tout.js'},
          {'id': 'films', 'name': 'Films libres 2', 'filename': 'providers/films.js', 'version': '2.0.0'},
          {'id': 'neuf', 'name': 'Neuf', 'filename': 'providers/neuf.js'},
          // `series` is gone from the repository.
        ],
      }, fallbackName: 'x');

      final updated = repo.updatedWith(manifest);

      expect(updated.id, repo.id);
      expect(updated.name, 'Nouveau nom');
      expect(updated.mode, ScraperMode.server);
      expect(updated.enabled, isFalse);
      expect(updated.scrapers.map((s) => s.id), ['tout', 'films', 'neuf']);
      expect(updated.scrapers[1].name, 'Films libres 2');
      expect(updated.scrapers[1].version, '2.0.0');
    });

    test('are on by default, also when older data has no flag', () {
      expect(testRepo().enabled, isTrue);
      expect(ScraperRepo.decodeList('[{"url":"$repoUrl","scrapers":[]}]').single.enabled, isTrue);
      final off = ScraperRepo.decodeList(ScraperRepo.encodeList([testRepo().copyWith(enabled: false)]));
      expect(off.single.enabled, isFalse);
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

    test('keeps 100 links at most', () {
      final many = [for (var i = 0; i < 150; i++) {'url': 'https://cdn.test/$i'}];
      expect(ScraperStream.parseList(many), hasLength(ScraperStream.maxPerScraper));
      expect(ScraperStream.maxPerScraper, 100);
    });

    test('reads a stream as Nuvio does: url as an object, no "[object", language and type', () {
      final streams = ScraperStream.parseList([
        {
          'name': 'Coflix (VF)',
          'title': '[VF] Coflix [1080p]',
          'url': 'https://cdn.test/master',
          'quality': '1080p',
          'language': 'fr',
          'type': 'hls',
          'headers': {'Referer': 'https://coflix.test/', 'User-Agent': 'Mozilla/5.0'},
        },
        {
          'url': {'url': 'https://cdn.test/b.mkv'},
          'name': 'Objet',
          'title': '[object Object]',
        },
        {'url': 'https://cdn.test/[object Object]'},
        {'url': 'https://cdn.test/c', 'type': 'dash'},
      ]);

      expect(streams.map((s) => s.url), ['https://cdn.test/master', 'https://cdn.test/b.mkv', 'https://cdn.test/c']);
      final first = streams[0];
      expect((first.name, first.title, first.language, first.type), ('Coflix (VF)', '[VF] Coflix [1080p]', 'fr', 'hls'));
      expect(first.streamType, 'm3u8');
      expect(first.headers['Referer'], 'https://coflix.test/');
      // The title Nuvio shows; the quality is not written twice.
      expect(first.label('Coflix'), '[VF] Coflix [1080p]');
      expect(streams[1].title, isNull);
      expect(streams[1].streamType, 'mp4');
      expect(streams[1].label('x'), 'Objet');
      expect(streams[2].streamType, isNull);
    });

    test('writes a label for the sources panel, which reads the quality in it', () {
      const stream = ScraperStream(url: 'https://cdn.test/a', name: 'Serveur 1', quality: '1080p', size: '1.2 GB');
      expect(stream.label('Films libres'), 'Serveur 1 · 1080p · 1.2 GB');
      expect(const ScraperStream(url: 'https://cdn.test/a').label('Films libres'), 'Films libres');
      expect(const ScraperStream(url: 'https://cdn.test/a', quality: '720p').label('Films libres'), 'Films libres · 720p');
      expect(const ScraperStream(url: 'https://cdn.test/a?x=.mp4').streamType, isNull);
      const titled = ScraperStream(url: 'https://cdn.test/a', name: 'Src', title: 'Src - Vidmoly', quality: 'HD', size: '1.4 GB');
      expect(titled.label('x'), 'Src - Vidmoly · HD · 1.4 GB');
    });
  });
}
