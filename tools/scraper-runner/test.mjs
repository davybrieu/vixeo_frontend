import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LIMITS, checkUrl } from './guard.mjs';
import { normalizeStreams, runScraper } from './host.mjs';

const movie = { tmdbId: '550', mediaType: 'movie', season: null, episode: null };
const noNetwork = async () => {
  throw new Error('pas de réseau dans ce test');
};
const ok = (body, extra = {}) => ({ status: 200, statusText: 'OK', headers: { 'content-type': 'application/json' }, body, ...extra });

/** Runs a scraper whose body is `module.exports = { getStreams: async (...) => ... }`. */
const run = (code, { params = movie, doFetch = noNetwork, ...rest } = {}) => runScraper({ code, params, doFetch, ...rest });

test('a scraper gets its parameters and returns streams', async () => {
  const streams = await run(`module.exports = { getStreams: async (id, type, s, e) => [
    { url: 'https://cdn.example.com/' + id + '.m3u8', name: type + ':' + s + ':' + e, quality: '1080p', headers: { Referer: 'https://x.example' } } ] };`);
  assert.deepEqual(streams, [
    { url: 'https://cdn.example.com/550.m3u8', name: 'movie:null:null', title: null, quality: '1080p', size: null,
      headers: { Referer: 'https://x.example' } },
  ]);
});

test('an episode request carries season and episode as numbers', async () => {
  const streams = await run(
    `exports.getStreams = (id, type, s, e) => Promise.resolve([{ url: 'https://a.example/v', name: typeof s + typeof e + s + e }]);`,
    { params: { tmdbId: '1399', mediaType: 'tv', season: 2, episode: 5 } },
  );
  assert.equal(streams[0].name, 'numbernumber25');
});

test('fetch goes through the host: json, text, headers, status', async () => {
  const seen = [];
  const streams = await run(
    `module.exports.getStreams = async () => {
       const r = await fetch('https://api.example.com/find?id=550&q=a b', { headers: { 'X-Test': '1' } });
       const data = await r.json();
       const t = await (await fetch('https://api.example.com/text')).text();
       return [{ url: data.link, name: r.status + ':' + r.ok + ':' + r.headers.get('Content-Type') + ':' + t }];
     };`,
    {
      doFetch: async (req) => {
        seen.push(req);
        return req.url.endsWith('/text') ? ok('hello', { headers: {} }) : ok('{"link":"https://cdn.example.com/v.mp4"}');
      },
    },
  );
  assert.equal(seen[0].url, 'https://api.example.com/find?id=550&q=a b');
  assert.equal(seen[0].method, 'GET');
  assert.equal(seen[0].headers['x-test'], '1');
  assert.equal(streams[0].url, 'https://cdn.example.com/v.mp4');
  assert.equal(streams[0].name, '200:true:application/json:hello');
});

test('POST with URLSearchParams sends a form body', async () => {
  let sent;
  await run(
    `module.exports.getStreams = async () => {
       await fetch('https://api.example.com/x', { method: 'post', body: new URLSearchParams({ a: '1 2', b: 'é&' }) });
       return [];
     };`,
    { doFetch: async (req) => ((sent = req), ok('{}')) },
  );
  assert.equal(sent.method, 'POST');
  assert.equal(sent.body, 'a=1+2&b=%C3%A9%26');
  assert.equal(sent.headers['content-type'], 'application/x-www-form-urlencoded;charset=UTF-8');
});

test('requests run in parallel and timers fire in order', async () => {
  const order = [];
  const streams = await run(
    `module.exports.getStreams = async () => {
       const wait = (ms, v) => new Promise((r) => setTimeout(() => r(v), ms));
       const out = await Promise.all([wait(60, 'c'), wait(10, 'a'), wait(30, 'b')]);
       return [{ url: 'https://a.example/' + out.join('') }];
     };`,
  );
  assert.equal(streams[0].url, 'https://a.example/cab');
  assert.deepEqual(order, []);
});

test('URL and URLSearchParams agree with the WHATWG ones', async () => {
  const cases = [
    ['https://Example.com:443/a/b/../c?x=1&y=2#frag'],
    ['http://example.com:8080/p'],
    ['https://example.com'],
    ['https://user:pw@example.com/x'],
    ['/img/a.jpg', 'https://example.com/dir/page.html?q=1'],
    ['../up.js', 'https://example.com/a/b/c.html'],
    ['./same.js', 'https://example.com/a/b/c.html'],
    ['other.html', 'https://example.com/a/b'],
    ['?page=2', 'https://example.com/list?page=1#top'],
    ['#x', 'https://example.com/list?page=1'],
    ['//cdn.example.com/lib.js', 'https://example.com/'],
    ['https://example.com/a b?c=d e'],
  ];
  const probe = (input, base) => {
    const u = base === undefined ? new URL(input) : new URL(input, base);
    return [u.href, u.origin, u.protocol, u.host, u.hostname, u.port, u.pathname, u.search, u.hash];
  };
  const streams = await run(
    `module.exports.getStreams = async () => {
       const probe = ${probe.toString()};
       return [{ url: 'https://a.example/', name: JSON.stringify(${JSON.stringify(cases)}.map((c) => probe(c[0], c[1]))) }];
     };`,
  );
  const got = JSON.parse(streams[0].name);
  cases.forEach((c, i) => assert.deepEqual(got[i], probe(c[0], c[1]), `case ${JSON.stringify(c)}`));
});

test('URL throws on a relative address without a base; searchParams stays linked', async () => {
  const streams = await run(
    `module.exports.getStreams = async () => {
       let threw = false;
       try { new URL('/relative'); } catch (e) { threw = e instanceof TypeError; }
       const u = new URL('https://example.com/p?a=1');
       u.searchParams.append('b', 'x y');
       u.searchParams.set('a', '2');
       return [{ url: 'https://a.example/', name: threw + '|' + u.href + '|' + [...u.searchParams.keys()].join(',') }];
     };`,
  );
  assert.equal(streams[0].name, 'true|https://example.com/p?a=2&b=x+y|a,b');
});

test('URLSearchParams round trips like the standard one', async () => {
  const inputs = ['a=1&b=2', '?q=hello+world&r=%C3%A9', 'x=&y&=z', 'k=a%26b%3Dc', "p=!'()~"];
  const streams = await run(
    `module.exports.getStreams = async () => [{ url: 'https://a.example/', name: JSON.stringify(
       ${JSON.stringify(inputs)}.map((s) => { const p = new URLSearchParams(s); return [p.toString(), [...p.entries()]]; })) }];`,
  );
  const got = JSON.parse(streams[0].name);
  inputs.forEach((s, i) => {
    const p = new URLSearchParams(s);
    assert.deepEqual(got[i], JSON.parse(JSON.stringify([p.toString(), [...p.entries()]])), s);
  });
});

test('atob, btoa and TextEncoder / TextDecoder', async () => {
  const text = 'héllo wörld ✓ 😀';
  const streams = await run(
    `module.exports.getStreams = async () => {
       const bytes = new TextEncoder().encode(${JSON.stringify(text)});
       return [{ url: 'https://a.example/', name: JSON.stringify({
         b: btoa('Many hands make light work.'), a: atob('TWFueSBoYW5kcw=='), pad: btoa('ab'),
         urlsafe: atob('_-8'), bytes: Array.from(bytes), back: new TextDecoder().decode(bytes) }) }];
     };`,
  );
  const got = JSON.parse(streams[0].name);
  assert.equal(got.b, Buffer.from('Many hands make light work.').toString('base64'));
  assert.equal(got.a, 'Many hands');
  assert.equal(got.pad, 'YWI=');
  assert.equal(got.urlsafe, Buffer.from('_-8', 'base64').toString('latin1'));
  assert.deepEqual(got.bytes, [...Buffer.from(text)]);
  assert.equal(got.back, text);
});

test('requests to local, private or non-https addresses are refused before the network', async () => {
  const urls = [
    'http://example.com/x', 'https://localhost/x', 'https://127.0.0.1/x', 'https://10.1.2.3/x',
    'https://192.168.0.5/x', 'https://172.20.0.1/x', 'https://169.254.169.254/latest', 'https://[::1]/x',
    'https://[fd00::1]/x', 'https://[::ffff:127.0.0.1]/x', 'https://nas.local/x', 'https://intranet/x',
    'https://user:pw@example.com/x', 'ftp://example.com/x', 'https://0x7f000001/x', 'https://2130706433/x',
    'https://[::]/x', 'https://[0:0:0:0:0:0:0:1]/x', 'https://[fe80::1]/x', 'https://[ff02::1]/x',
    'https://[64:ff9b::7f00:1]/x', 'https://[2002:7f00:1::]/x', 'https://127.1/x', 'https://[::ffff:10.0.0.1]/x',
  ];
  let reached = 0;
  const streams = await run(
    `module.exports.getStreams = async () => {
       const out = [];
       for (const u of ${JSON.stringify(urls)}) {
         try { await fetch(u); out.push('reached ' + u); } catch (e) { out.push('refused'); }
       }
       return [{ url: 'https://a.example/', name: out.join(',') }];
     };`,
    { doFetch: async () => (reached++, ok('{}')) },
  );
  assert.equal(reached, 0);
  assert.equal(streams[0].name, urls.map(() => 'refused').join(','));
  assert.equal(checkUrl('https://example.com/x'), null);
  assert.equal(checkUrl('https://8.8.8.8/x'), null);
  assert.equal(checkUrl('https://[2606:4700:4700::1111]/x'), null);
  assert.equal(checkUrl('https://[::ffff:8.8.8.8]/x'), null);
  assert.equal(checkUrl('https://[64:ff9b::808:808]/x'), null);
});

test('too many requests are cut, and the scraper can recover', async () => {
  let calls = 0;
  const streams = await run(
    `module.exports.getStreams = async () => {
       let refused = 0;
       for (let i = 0; i < 10; i++) { try { await fetch('https://a.example/' + i); } catch (e) { refused++; } }
       return [{ url: 'https://a.example/', name: String(refused) }];
     };`,
    { limits: { ...LIMITS, requests: 6 }, doFetch: async () => (calls++, ok('{}')) },
  );
  assert.equal(calls, 6);
  assert.equal(streams[0].name, '4');
});

test('a network failure is a rejected fetch, not a crash', async () => {
  const streams = await run(
    `module.exports.getStreams = async () => {
       try { await fetch('https://a.example/'); return []; }
       catch (e) { return [{ url: 'https://a.example/', name: e.name + ':' + e.message }]; }
     };`,
    { doFetch: async () => { throw new Error('boom'); } },
  );
  assert.equal(streams[0].name, 'TypeError:Network request failed: boom');
});

test('a slow request is cut at the request timeout', async () => {
  const streams = await run(
    `module.exports.getStreams = async () => {
       try { await fetch('https://a.example/'); return []; } catch (e) { return [{ url: 'https://a.example/', name: e.message }]; }
     };`,
    { limits: { ...LIMITS, requestMs: 50 }, doFetch: () => new Promise(() => {}) },
  );
  assert.match(streams[0].name, /délai dépassé/);
});

test('an endless loop is interrupted by the run deadline', async () => {
  await assert.rejects(
    run(`module.exports.getStreams = async () => { for (;;) {} };`, { limits: { ...LIMITS, runMs: 300 } }),
    /interrupted|délai/i,
  );
});

test('a scraper that never answers is reported, not waited for', async () => {
  await assert.rejects(
    run(`module.exports.getStreams = () => new Promise(() => {});`),
    /ne répond plus/,
  );
});

test('memory is capped', async () => {
  await assert.rejects(
    run(`module.exports.getStreams = async () => { const a = []; for (;;) a.push(new Array(100000).fill('x')); };`,
      { limits: { ...LIMITS, memory: 8 * 1024 * 1024, runMs: 5000 } }),
  );
});

test('errors are reported: no getStreams, a throw, a broken file', async () => {
  await assert.rejects(run(`module.exports = { other() {} };`), /n'exporte pas getStreams/);
  await assert.rejects(run(`module.exports.getStreams = async () => { throw new Error('site en panne'); };`), /site en panne/);
  await assert.rejects(run(`this is not javascript`), /Chargement du scraper impossible/);
});

test('the sandbox has no way out: no require, no browser network objects', async () => {
  const streams = await run(
    `module.exports.getStreams = async () => {
       let req = 'ok';
       try { require('fs'); req = 'loaded'; } catch (e) { req = 'blocked'; }
       const names = ['XMLHttpRequest', 'WebSocket', 'importScripts', 'localStorage', 'process', 'window', 'document']
         .map((n) => typeof globalThis[n]);
       let write = 'ok';
       try { globalThis.__vx = {}; write = globalThis.__vx.take ? 'kept' : 'replaced'; } catch (e) { write = 'kept'; }
       return [{ url: 'https://a.example/', name: [req, ...names, write].join(',') }];
     };`,
  );
  assert.equal(streams[0].name, 'blocked,' + 'undefined,'.repeat(7) + 'kept');
});

test('a scraper can use setTimeout inside AbortController timeouts', async () => {
  const streams = await run(
    `module.exports.getStreams = async () => {
       const c = new AbortController();
       setTimeout(() => c.abort(), 20);
       try { await fetch('https://a.example/', { signal: c.signal }); return []; }
       catch (e) { return [{ url: 'https://a.example/', name: e.name }]; }
     };`,
    { doFetch: () => new Promise(() => {}) },
  );
  assert.equal(streams[0].name, 'AbortError');
});

test('stream normalization keeps playable links and drops the rest', () => {
  const out = normalizeStreams([
    { url: 'https://a.example/1.m3u8', title: 'Serveur 1', quality: 1080, size: '1.2 GB', headers: { A: 'b', n: 3, bad: {} } },
    { url: 'javascript:alert(1)' },
    { url: 'file:///etc/passwd' },
    { name: 'sans lien' },
    null,
    'texte',
    { url: 'http://a.example/2.mp4', name: '  Nom  ' },
  ]);
  assert.deepEqual(out.map((s) => s.url), ['https://a.example/1.m3u8', 'http://a.example/2.mp4']);
  assert.deepEqual(out[0], { url: 'https://a.example/1.m3u8', name: 'Serveur 1', title: 'Serveur 1', quality: '1080', size: '1.2 GB',
    headers: { A: 'b', n: '3' } });
  assert.equal(out[1].name, 'Nom');
  assert.deepEqual(normalizeStreams('pas une liste'), []);
  assert.equal(normalizeStreams(Array.from({ length: 80 }, (_, i) => ({ url: `https://a.example/${i}` }))).length, LIMITS.streams);
});
