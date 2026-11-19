// Reference host of the scraper sandbox (assets/scrapers/sandbox.js). The Dart `ScraperRunner`
// (lib/features/addons/scraper_runner.dart) does exactly this loop; the server's runner is a
// port of it. Real QuickJS, so what passes here behaves like Android and iOS.
import { readFile } from 'node:fs/promises';
import { getQuickJS, newQuickJSWASMModule } from 'quickjs-emscripten';
import { LIMITS, checkUrl } from './guard.mjs';

const PRELUDE = await readFile(new URL('../../assets/scrapers/sandbox.js', import.meta.url), 'utf8');

// QuickJS cannot free a runtime that ran out of memory (its own assertion aborts the WebAssembly
// module): when that happens the module is thrown away and the next run gets a fresh one.
let quickjs = getQuickJS();

/**
 * Runs one scraper's `getStreams` and returns its normalized streams.
 *
 * @param {object} o
 * @param {string} o.code        the scraper's JavaScript (a CommonJS bundle exporting getStreams)
 * @param {{tmdbId:string, mediaType:'movie'|'tv', season:number|null, episode:number|null}} o.params
 * @param {(req:{url:string,method:string,headers:object,body:string|null,redirect:string}) => Promise<object>} o.doFetch
 *        does ONE request (already checked) and resolves { status, statusText, headers, body, url }
 * @param {(entry:{level:string,msg:string}) => void} [o.onLog]
 */
export async function runScraper({ code, params, doFetch, onLog = () => {}, limits = LIMITS }) {
  const QuickJS = await quickjs;
  const runtime = QuickJS.newRuntime();
  runtime.setMemoryLimit(limits.memory);
  runtime.setMaxStackSize(limits.stack);
  const deadline = Date.now() + limits.runMs;
  runtime.setInterruptHandler(() => Date.now() > deadline);
  const vm = runtime.newContext();

  const evalJs = (source) => {
    const r = vm.evalCode(source);
    if (r.error) {
      const err = vm.dump(r.error);
      r.error.dispose();
      throw new Error(err && err.message ? err.message : String(err));
    }
    const value = vm.dump(r.value);
    r.value.dispose();
    return value;
  };

  const timers = new Set();
  const later = (fn, ms) => {
    const handle = setTimeout(() => {
      timers.delete(handle);
      fn();
    }, ms);
    timers.add(handle);
    return handle;
  };
  const inbox = []; // JS to evaluate in the sandbox (answers to its requests and timers)
  let wake = () => {};
  let activity = 0; // requests and timers the host still owes an answer for
  let requests = 0;
  let done = null;
  const post = (source) => {
    activity--;
    inbox.push(source);
    wake();
  };

  const handle = (m) => {
    if (m.t === 'log') return onLog({ level: m.level, msg: m.msg });
    if (m.t === 'done') return (done = m);
    if (m.t === 'timer') {
      activity++;
      later(() => post(`__vx.timer(${Number(m.id)})`), Math.min(Number(m.ms) || 0, limits.timerMs));
      return;
    }
    if (m.t !== 'fetch') return;
    const id = Number(m.id);
    const deliver = (res) => post(`__vx.deliver(${id}, ${JSON.stringify(res)})`);
    activity++;
    const refused = ++requests > limits.requests
      ? 'trop de requêtes'
      : (m.body && m.body.length > limits.requestBody ? 'corps trop gros' : checkUrl(String(m.url)));
    if (refused) return deliver({ error: refused });
    let timeout;
    Promise.race([
      doFetch({ url: String(m.url), method: String(m.method), headers: m.headers || {}, body: m.body ?? null,
        redirect: m.redirect }),
      new Promise((_, reject) => {
        timeout = later(() => reject(new Error('délai dépassé')), limits.requestMs);
      }),
    ]).then(deliver, (e) => deliver({ error: e && e.message ? e.message : String(e) })).finally(() => {
      clearTimeout(timeout);
      timers.delete(timeout);
    });
  };

  try {
    evalJs(PRELUDE);
    evalJs(`__vx.run(${JSON.stringify(code)}, ${JSON.stringify(params)})`);
    while (!done) {
      runtime.executePendingJobs();
      for (const m of JSON.parse(evalJs('__vx.take()'))) handle(m);
      if (done) break;
      if (Date.now() > deadline) throw new Error('délai dépassé');
      if (inbox.length === 0) {
        if (activity === 0) throw new Error('le scraper ne répond plus');
        await new Promise((resolve) => {
          const guard = later(resolve, Math.max(1, deadline - Date.now()));
          wake = () => {
            clearTimeout(guard);
            timers.delete(guard);
            resolve();
          };
        });
        continue;
      }
      for (const source of inbox.splice(0)) evalJs(source);
    }
  } finally {
    for (const handle of timers) clearTimeout(handle);
    try {
      vm.dispose();
      runtime.dispose();
    } catch {
      quickjs = newQuickJSWASMModule();
    }
  }
  if (!done.ok) throw new Error(done.error || 'le scraper a échoué');
  return normalizeStreams(done.streams, limits.streams);
}

/** What the app keeps of a scraper's answer (the Dart `ScraperStream.tryParse` does the same). */
export function normalizeStreams(list, max = LIMITS.streams) {
  const out = [];
  for (const s of Array.isArray(list) ? list : []) {
    if (!s || typeof s !== 'object' || typeof s.url !== 'string' || checkUrlLoose(s.url)) continue;
    const headers = {};
    if (s.headers && typeof s.headers === 'object') {
      for (const [k, v] of Object.entries(s.headers)) if (typeof v === 'string' || typeof v === 'number') headers[k] = String(v);
    }
    const text = (v) => (typeof v === 'string' && v.trim() ? v.trim() : null);
    out.push({
      url: s.url,
      name: text(s.name) ?? text(s.title) ?? text(s.provider),
      title: text(s.title),
      quality: text(s.quality) ?? (typeof s.quality === 'number' ? String(s.quality) : null),
      size: text(s.size) ?? (typeof s.size === 'number' ? String(s.size) : null),
      headers,
    });
    if (out.length >= max) break;
  }
  return out;
}

// A stream link must be http(s); unlike a request it may be http (a player, not a scraper, opens it).
function checkUrlLoose(raw) {
  try {
    const u = new URL(raw);
    return u.protocol === 'https:' || u.protocol === 'http:' ? null : 'protocole interdit';
  } catch {
    return 'adresse invalide';
  }
}
