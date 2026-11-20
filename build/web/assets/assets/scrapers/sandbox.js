/*
 * Vixeo scraper sandbox: the prelude every scraper runs on top of (docs/scrapers.md).
 *
 * The SAME file runs on Android and iOS (QuickJS / JavaScriptCore), in a sandboxed iframe on the web,
 * and in the reference runner of the server (tools/scraper-runner). It gives a scraper what the
 * Nuvio app gives its plug-ins (console, fetch, URL, URLSearchParams, TextEncoder, atob, timers,
 * SCRAPER_ID, SCRAPER_SETTINGS, window / global / self, CryptoJS when the scraper uses it…), so
 * that a repository written for Nuvio works as it is, and NOTHING else: no network of its own, no
 * storage, no file, no DOM. Every request goes through the host (`__vx`), which checks it (https
 * only, no private address, size and count limits) and does it.
 *
 * Like Nuvio's, this `fetch` never throws on a network failure: it resolves a response with
 * `status: 0` and `ok: false` (a refused address too), and `response.json()` gives `null` when the
 * body is not JSON. Nuvio scrapers are written for that.
 *
 * Host protocol (a message is a plain JSON-able object):
 *   host  → eval("__vx.run(code, params, libs)") starts the scraper
 *                                               params = { tmdbId, mediaType, season, episode,
 *                                                          scraperId, settings }
 *                                               libs = sources to run first (crypto-js), or []
 *   sandbox → { t: 'fetch', id, url, method, headers, body, redirect }
 *   host  → eval("__vx.deliver(id, response)")  response = { status, statusText, headers, body, url }
 *                                               or { error: 'message' }
 *   sandbox → { t: 'timer', id, ms }           host → eval("__vx.timer(id)") after ms
 *   sandbox → { t: 'log', level, msg }
 *   sandbox → { t: 'done', ok: true, streams } | { t: 'done', ok: false, error }
 * Messages are drained with `__vx.take()` (a JSON array) or, when `__vx.emit` is set (the iframe
 * on the web), sent one by one to `__vx.emit(message)`.
 */
(function (g) {
  'use strict';

  var vx = {
    seq: 0,
    pending: Object.create(null),
    timers: Object.create(null),
    intervals: Object.create(null),
    outbox: [],
    emit: null,
    logs: 0,
    finished: false,
  };
  Object.defineProperty(g, '__vx', { value: vx, enumerable: false, writable: false, configurable: false });
  g.global = g;
  g.self = g;
  // Nuvio gives `window` too (many bundles look for it); a browser frame already has its own.
  if (typeof g.window === 'undefined') g.window = g;
  // The browser's own doors to the network and to the page do not exist for a scraper, nor the
  // bridge of the engine's package (flutter_js's `sendMessage`: its own timers and console).
  ['XMLHttpRequest', 'WebSocket', 'EventSource', 'importScripts', 'Worker', 'SharedWorker', 'indexedDB',
    'localStorage', 'sessionStorage', 'navigator', 'open', 'sendMessage'].forEach(function (name) {
    try { delete g[name]; } catch (e) { /* not deletable: the iframe's CSP still blocks it */ }
  });

  function push(message) {
    if (typeof vx.emit === 'function') vx.emit(message);
    else vx.outbox.push(message);
  }

  vx.take = function () {
    var out = vx.outbox;
    vx.outbox = [];
    return JSON.stringify(out);
  };

  function msg(e) {
    return e && e.message ? String(e.message) : String(e);
  }

  // ---------------------------------------------------------------------------------- console
  function show(value) {
    if (typeof value === 'string') return value;
    if (value instanceof Error) return value.stack || value.message;
    try { return JSON.stringify(value); } catch (e) { return String(value); }
  }
  function log(level) {
    return function () {
      if (vx.logs >= 100) return;
      vx.logs++;
      var text = Array.prototype.map.call(arguments, show).join(' ');
      push({ t: 'log', level: level, msg: text.length > 500 ? text.slice(0, 500) + '…' : text });
    };
  }
  g.console = { log: log('log'), info: log('info'), debug: log('debug'), warn: log('warn'), error: log('error') };

  // ------------------------------------------------------------------------------------ timers
  g.setTimeout = function (fn, ms) {
    var extra = Array.prototype.slice.call(arguments, 2);
    var id = ++vx.seq;
    vx.timers[id] = function () { fn.apply(undefined, extra); };
    push({ t: 'timer', id: id, ms: Math.max(0, Number(ms) || 0) });
    return id;
  };
  // Nuvio's mobile app has setInterval too: each tick is a new host timer.
  g.setInterval = function (fn, ms) {
    var extra = Array.prototype.slice.call(arguments, 2);
    var delay = Math.max(4, Number(ms) || 0);
    var id = ++vx.seq;
    function arm() {
      vx.timers[id] = tick;
      push({ t: 'timer', id: id, ms: delay });
    }
    function tick() {
      if (!vx.intervals[id]) return;
      arm();
      fn.apply(undefined, extra);
    }
    vx.intervals[id] = true;
    arm();
    return id;
  };
  g.clearTimeout = g.clearInterval = function (id) {
    delete vx.timers[id];
    delete vx.intervals[id];
  };
  vx.timer = function (id) {
    var fn = vx.timers[id];
    if (!fn) return;
    delete vx.timers[id];
    fn();
  };
  if (typeof g.queueMicrotask !== 'function') {
    g.queueMicrotask = function (fn) { Promise.resolve().then(fn); };
  }

  // ------------------------------------------------------------------------------ atob / btoa
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  g.btoa = function (input) {
    var s = String(input), out = '';
    for (var i = 0; i < s.length; i += 3) {
      var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      if (a > 255 || b > 255 || c > 255) throw new Error('InvalidCharacterError');
      var n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] +
        (i + 1 < s.length ? B64[(n >> 6) & 63] : '=') + (i + 2 < s.length ? B64[n & 63] : '=');
    }
    return out;
  };
  g.atob = function (input) {
    var s = String(input).replace(/[\s=]+/g, '').replace(/-/g, '+').replace(/_/g, '/'), out = '';
    if (s.length % 4 === 1) throw new Error('InvalidCharacterError');
    for (var i = 0; i < s.length; i += 4) {
      var n = 0, k;
      for (k = 0; k < 4; k++) {
        var idx = i + k < s.length ? B64.indexOf(s[i + k]) : 0;
        if (idx < 0) throw new Error('InvalidCharacterError');
        n = (n << 6) | idx;
      }
      out += String.fromCharCode((n >> 16) & 255);
      if (i + 2 < s.length) out += String.fromCharCode((n >> 8) & 255);
      if (i + 3 < s.length) out += String.fromCharCode(n & 255);
    }
    return out;
  };

  // ------------------------------------------------------------------- TextEncoder / Decoder
  function utf8Bytes(str) {
    var bytes = [];
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (c >= 0xd800 && c < 0xdc00 && i + 1 < str.length) {
        var d = str.charCodeAt(i + 1);
        if (d >= 0xdc00 && d < 0xe000) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
      }
      if (c < 0x80) bytes.push(c);
      else if (c < 0x800) bytes.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else bytes.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return bytes;
  }
  g.TextEncoder = class TextEncoder {
    get encoding() { return 'utf-8'; }
    encode(str) { return new Uint8Array(utf8Bytes(str === undefined ? '' : String(str))); }
  };
  g.TextDecoder = class TextDecoder {
    get encoding() { return 'utf-8'; }
    decode(buffer) {
      if (buffer === undefined) return '';
      var b = buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : new Uint8Array(buffer.buffer || buffer);
      var out = '', i = 0;
      while (i < b.length) {
        var c = b[i++], cp = 0xfffd;
        if (c < 0x80) cp = c;
        else if (c >= 0xc2 && c < 0xe0 && i < b.length) cp = ((c & 31) << 6) | (b[i++] & 63);
        else if (c >= 0xe0 && c < 0xf0 && i + 1 < b.length) cp = ((c & 15) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
        else if (c >= 0xf0 && c < 0xf5 && i + 2 < b.length) {
          cp = ((c & 7) << 18) | ((b[i++] & 63) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
        }
        out += cp > 0xffff ? String.fromCharCode(0xd800 + ((cp - 0x10000) >> 10), 0xdc00 + ((cp - 0x10000) & 1023))
          : String.fromCharCode(cp);
      }
      return out;
    }
  };

  // ------------------------------------------------------------- URLSearchParams and URL
  function formEncode(s) {
    return encodeURIComponent(s).replace(/%20/g, '+').replace(/[!'()~]/g, function (ch) {
      return '%' + ch.charCodeAt(0).toString(16).toUpperCase();
    });
  }
  function formDecode(s) {
    s = s.replace(/\+/g, ' ');
    try { return decodeURIComponent(s); } catch (e) { return s; }
  }

  class URLSearchParams {
    constructor(init) {
      this._list = [];
      this._onChange = null;
      if (init == null) return;
      if (typeof init === 'string') {
        if (init[0] === '?') init = init.slice(1);
        init.split('&').forEach(function (pair) {
          if (!pair) return;
          var eq = pair.indexOf('=');
          this._list.push([formDecode(eq < 0 ? pair : pair.slice(0, eq)), formDecode(eq < 0 ? '' : pair.slice(eq + 1))]);
        }, this);
      } else if (init instanceof URLSearchParams) {
        this._list = init._list.map(function (p) { return [p[0], p[1]]; });
      } else if (typeof init[Symbol.iterator] === 'function') {
        for (var pair of init) this._list.push([String(pair[0]), String(pair[1])]);
      } else {
        Object.keys(init).forEach(function (k) { this._list.push([k, String(init[k])]); }, this);
      }
    }
    _changed() { if (this._onChange) this._onChange(this.toString()); }
    append(k, v) { this._list.push([String(k), String(v)]); this._changed(); }
    delete(k) { this._list = this._list.filter(function (p) { return p[0] !== String(k); }); this._changed(); }
    get(k) { var p = this._list.find(function (q) { return q[0] === String(k); }); return p ? p[1] : null; }
    getAll(k) { return this._list.filter(function (q) { return q[0] === String(k); }).map(function (q) { return q[1]; }); }
    has(k) { return this._list.some(function (q) { return q[0] === String(k); }); }
    set(k, v) {
      k = String(k); v = String(v);
      var found = false;
      this._list = this._list.filter(function (p) {
        if (p[0] !== k) return true;
        if (found) return false;
        found = true; p[1] = v; return true;
      });
      if (!found) this._list.push([k, v]);
      this._changed();
    }
    sort() { this._list.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; }); this._changed(); }
    forEach(cb, thisArg) { this._list.slice().forEach(function (p) { cb.call(thisArg, p[1], p[0], this); }, this); }
    keys() { return this._list.map(function (p) { return p[0]; })[Symbol.iterator](); }
    values() { return this._list.map(function (p) { return p[1]; })[Symbol.iterator](); }
    entries() { return this._list.map(function (p) { return [p[0], p[1]]; })[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
    toString() { return this._list.map(function (p) { return formEncode(p[0]) + '=' + formEncode(p[1]); }).join('&'); }
  }
  g.URLSearchParams = URLSearchParams;

  var DEFAULT_PORT = { 'http:': '80', 'https:': '443', 'ftp:': '21', 'ws:': '80', 'wss:': '443' };
  function normalizePath(path) {
    if (path.charAt(0) !== '/') return path;
    var out = [];
    path.split('/').slice(1).forEach(function (seg, i, all) {
      if (seg === '..') { out.pop(); if (i === all.length - 1) out.push(''); }
      else if (seg === '.') { if (i === all.length - 1) out.push(''); }
      else out.push(seg);
    });
    return '/' + out.join('/');
  }
  function parseAbsolute(s) {
    var m = /^([a-zA-Z][a-zA-Z0-9+.\-]*:)(?:\/\/([^\/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/.exec(s);
    if (!m) return null;
    var r = { protocol: m[1].toLowerCase(), username: '', password: '', hostname: '', port: '',
      pathname: m[3] || '', search: m[4] === '?' ? '' : m[4] || '', hash: m[5] === '#' ? '' : m[5] || '', authority: m[2] !== undefined };
    if (r.authority) {
      var auth = m[2], at = auth.lastIndexOf('@'), hostport = auth;
      if (at >= 0) {
        var ui = auth.slice(0, at), c = ui.indexOf(':');
        hostport = auth.slice(at + 1);
        r.username = c < 0 ? ui : ui.slice(0, c);
        r.password = c < 0 ? '' : ui.slice(c + 1);
      }
      var pm = /^(\[[^\]]*\]|[^:]*)(?::(\d*))?$/.exec(hostport);
      if (!pm) return null;
      r.hostname = pm[1].toLowerCase();
      r.port = pm[2] || '';
      if (DEFAULT_PORT[r.protocol] === r.port) r.port = '';
      if (r.protocol in DEFAULT_PORT) {
        if (!r.hostname) return null;
        if (r.pathname === '') r.pathname = '/';
      }
    }
    r.pathname = normalizePath(r.pathname);
    return r;
  }
  function encodeSpaces(s) { return s.replace(/ /g, '%20'); }

  class URL {
    constructor(input, base) {
      var s = encodeSpaces(String(input).trim());
      var r = parseAbsolute(s);
      if (!r) {
        if (base === undefined) throw new TypeError('Invalid URL: ' + input);
        var b = base instanceof URL ? base : new URL(base);
        r = { protocol: b.protocol, username: b.username, password: b.password, hostname: b.hostname, port: b.port,
          authority: true, pathname: b.pathname, search: b.search, hash: '' };
        if (s.indexOf('//') === 0) {
          r = parseAbsolute(b.protocol + s);
          if (!r) throw new TypeError('Invalid URL: ' + input);
        } else if (s.charAt(0) === '/') {
          var q = /^([^?#]*)(\?[^#]*)?(#.*)?$/.exec(s);
          r.pathname = normalizePath(q[1]); r.search = q[2] === '?' ? '' : q[2] || ''; r.hash = q[3] === '#' ? '' : q[3] || '';
        } else if (s.charAt(0) === '?') {
          var q2 = /^(\?[^#]*)(#.*)?$/.exec(s);
          r.search = q2[1] === '?' ? '' : q2[1]; r.hash = q2[2] === '#' ? '' : q2[2] || '';
        } else if (s.charAt(0) === '#') {
          r.hash = s === '#' ? '' : s;
        } else if (s !== '') {
          var q3 = /^([^?#]*)(\?[^#]*)?(#.*)?$/.exec(s);
          r.pathname = normalizePath(b.pathname.slice(0, b.pathname.lastIndexOf('/') + 1) + q3[1]);
          r.search = q3[2] === '?' ? '' : q3[2] || ''; r.hash = q3[3] === '#' ? '' : q3[3] || '';
        } else {
          r.hash = '';
        }
      }
      this.protocol = r.protocol; this.username = r.username; this.password = r.password;
      this.hostname = r.hostname; this.port = r.port; this.pathname = r.pathname;
      this.search = r.search; this.hash = r.hash;
      var self = this;
      this.searchParams = new URLSearchParams(this.search);
      this.searchParams._onChange = function (text) { self.search = text ? '?' + text : ''; };
    }
    get host() { return this.hostname + (this.port ? ':' + this.port : ''); }
    get origin() { return this.hostname ? this.protocol + '//' + this.host : 'null'; }
    get href() {
      var auth = this.username ? this.username + (this.password ? ':' + this.password : '') + '@' : '';
      return this.protocol + (this.hostname ? '//' + auth + this.host : '') + this.pathname + this.search + this.hash;
    }
    toString() { return this.href; }
    toJSON() { return this.href; }
  }
  g.URL = URL;

  // ------------------------------------------------------------ AbortController / Headers
  function abortError() {
    var e = new Error('The operation was aborted');
    e.name = 'AbortError';
    return e;
  }
  class AbortSignal {
    constructor() { this.aborted = false; this.reason = undefined; this._listeners = []; }
    addEventListener(type, fn) { if (type === 'abort') this._listeners.push(fn); }
    removeEventListener(type, fn) { this._listeners = this._listeners.filter(function (f) { return f !== fn; }); }
  }
  class AbortController {
    constructor() { this.signal = new AbortSignal(); }
    abort(reason) {
      var s = this.signal;
      if (s.aborted) return;
      s.aborted = true;
      s.reason = reason;
      s._listeners.slice().forEach(function (fn) { try { fn({ type: 'abort' }); } catch (e) { /* ignored */ } });
    }
  }
  g.AbortController = AbortController;
  g.AbortSignal = AbortSignal;

  class Headers {
    constructor(init) {
      this._map = Object.create(null);
      if (!init) return;
      if (init instanceof Headers) init.forEach(function (v, k) { this.append(k, v); }, this);
      else if (Array.isArray(init)) init.forEach(function (p) { this.append(p[0], p[1]); }, this);
      else Object.keys(init).forEach(function (k) { this.append(k, init[k]); }, this);
    }
    append(k, v) {
      k = String(k).toLowerCase();
      this._map[k] = k in this._map ? this._map[k] + ', ' + v : String(v);
    }
    set(k, v) { this._map[String(k).toLowerCase()] = String(v); }
    get(k) { k = String(k).toLowerCase(); return k in this._map ? this._map[k] : null; }
    has(k) { return String(k).toLowerCase() in this._map; }
    delete(k) { delete this._map[String(k).toLowerCase()]; }
    forEach(cb, thisArg) { Object.keys(this._map).forEach(function (k) { cb.call(thisArg, this._map[k], k, this); }, this); }
    keys() { return Object.keys(this._map)[Symbol.iterator](); }
    values() { var m = this._map; return Object.keys(m).map(function (k) { return m[k]; })[Symbol.iterator](); }
    entries() { var m = this._map; return Object.keys(m).map(function (k) { return [k, m[k]]; })[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
  }
  g.Headers = Headers;

  // ---------------------------------------------------------------------------------- fetch
  class Response {
    constructor(body, init) {
      init = init || {};
      this._body = body == null ? '' : String(body);
      this.status = init.status === undefined ? 200 : init.status;
      this.statusText = init.statusText || '';
      this.url = init.url || '';
      this.headers = new Headers(init.headers);
      this.ok = this.status >= 200 && this.status < 300;
      this.redirected = false;
      this.bodyUsed = false;
    }
    text() { this.bodyUsed = true; return Promise.resolve(this._body); }
    // Like Nuvio: a body that is not JSON (an error page, nothing) gives null, not a rejection.
    json() {
      this.bodyUsed = true;
      var body = this._body;
      return new Promise(function (resolve) {
        try { resolve(body === '' ? null : JSON.parse(body)); } catch (e) { resolve(null); }
      });
    }
    arrayBuffer() { this.bodyUsed = true; return Promise.resolve(new TextEncoder().encode(this._body).buffer); }
    clone() { return new Response(this._body, this); }
  }
  g.Response = Response;

  function headerObject(init) {
    var out = {};
    new Headers(init).forEach(function (v, k) { out[k] = v; });
    return out;
  }

  g.fetch = function (input, init) {
    init = init || {};
    return new Promise(function (resolve, reject) {
      var url = typeof input === 'string' ? input : input && input.href ? input.href : String(input);
      var signal = init.signal;
      if (signal && signal.aborted) return reject(abortError());
      var headers = headerObject(init.headers);
      var body = init.body;
      if (body != null) {
        if (body instanceof URLSearchParams) {
          body = body.toString();
          if (!('content-type' in headers)) headers['content-type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
        } else if (typeof body !== 'string') {
          body = String(body);
        }
      }
      var id = ++vx.seq;
      vx.pending[id] = { resolve: resolve, reject: reject, url: url };
      if (signal) {
        signal.addEventListener('abort', function () {
          if (!vx.pending[id]) return;
          delete vx.pending[id];
          reject(abortError());
        });
      }
      push({ t: 'fetch', id: id, url: url, method: String(init.method || 'GET').toUpperCase(), headers: headers,
        body: body == null ? null : body, redirect: init.redirect === 'manual' ? 'manual' : 'follow' });
    });
  };

  // A request that could not be made (network, refused address, too many requests…) is, as in
  // Nuvio, a response with status 0: `ok` is false, the body empty, statusText says why.
  vx.deliver = function (id, res) {
    var p = vx.pending[id];
    if (!p) return;
    delete vx.pending[id];
    if (!res || res.error) {
      p.resolve(new Response('', { status: 0, statusText: res && res.error ? String(res.error) : 'Network request failed',
        url: p.url }));
      return;
    }
    p.resolve(new Response(res.body, res));
  };

  // ---------------------------------------------- QuickJS and `for (… of yield x)` in a generator
  // QuickJS (every version tried, from 2021 to 2025) cannot compile a generator that has `yield` in
  // the head of a for…of loop: it stops with "stack underflow" or "nip_catch: no catch op". esbuild
  // writes exactly that when a scraper's `for (const x of await f())` is built for an old target
  // (async functions become generators), so some Nuvio scrapers would not even load. When the
  // compiler fails that way, the operand is moved out of the loop head and the file compiled again:
  //   for (let x of yield f()) body   →   var __vxOf0 = yield f(); for (let x of __vxOf0) body
  // Only a loop that starts a statement of a list (after `{`, `}`, `;`, a label or `case …:`), or
  // whose body is a block, is rewritten; anything else is left alone (and the file still fails).
  var EXPR_KEYWORDS = { 'return': 1, 'typeof': 1, 'instanceof': 1, 'in': 1, 'of': 1, 'new': 1, 'delete': 1,
    'void': 1, 'throw': 1, 'case': 1, 'do': 1, 'else': 1, 'yield': 1, 'await': 1 };
  var NUMBER = /(?:0[xXoObB][0-9a-fA-F_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?)n?/y;

  function isSpace(c) {
    return c === ' ' || c === '\n' || c === '\t' || c === '\r' || c === '\v' || c === '\f' || c === '\u00a0' ||
      c === '\ufeff' || c === '\u2028' || c === '\u2029';
  }
  function isIdPart(c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c === '_' || c === '$' ||
      c === '\\' || c > '\x7f';
  }

  function hoistForOfYield(src) {
    var n = src.length, i = 0;
    var toks = []; // the last significant tokens: { v: text, k: 'id' | 'prop' | 'num' | 'str' | 'p', s: start }
    var stack = []; // open brackets: { c: '(' | '[' | '{' | '${', loop, wrap }
    var found = []; // the loops to rewrite
    var pending = null; // a loop in the body of an if / while…: rewritten only if its own body is a block
    function last(k) { return toks[toks.length - 1 - (k || 0)]; }
    function push(v, k, s) {
      toks.push({ v: v, k: k, s: s });
      if (toks.length > 8) toks.shift();
    }
    function regexAllowed() {
      var t = last();
      if (!t) return true;
      if (t.k === 'id') return EXPR_KEYWORDS[t.v] === 1;
      if (t.k !== 'p') return false;
      if (t.v === '++' || t.v === '--') {
        var before = last(1);
        return !(before && (before.k === 'id' || before.k === 'prop' || before.k === 'num' || before.v === ')' || before.v === ']'));
      }
      return t.v !== ')' && t.v !== ']';
    }
    function skipString(q) {
      for (i++; i < n; i++) {
        var c = src[i];
        if (c === '\\') i++;
        else if (c === q) { i++; return; }
      }
    }
    // From inside a template literal: stops after its closing backquote (false) or after `${` (true).
    function skipTemplate() {
      for (; i < n; i++) {
        var c = src[i];
        if (c === '\\') i++;
        else if (c === '`') { i++; return false; }
        else if (c === '$' && src[i + 1] === '{') { i += 2; stack.push({ c: '${' }); return true; }
      }
      return false;
    }
    function skipRegex() {
      var inClass = false;
      for (i++; i < n; i++) {
        var c = src[i];
        if (c === '\\') i++;
        else if (c === '\n' || c === '\r') return;
        else if (inClass) { if (c === ']') inClass = false; }
        else if (c === '[') inClass = true;
        else if (c === '/') { i++; break; }
      }
      while (i < n && isIdPart(src[i])) i++;
    }
    function atWord(j, word) {
      return src.substr(j, word.length) === word && !isIdPart(src[j + word.length] || '');
    }
    function skipSpace(j) {
      for (;;) {
        while (j < n && isSpace(src[j])) j++;
        if (src[j] === '/' && src[j + 1] === '*') {
          var e = src.indexOf('*/', j + 2);
          j = e < 0 ? n : e + 2;
        } else if (src[j] === '/' && src[j + 1] === '/') {
          while (j < n && src[j] !== '\n' && src[j] !== '\r') j++;
        } else return j;
      }
    }
    function isBoundary(t) {
      return !t || (t.k === 'p' && (t.v === '{' || t.v === '}' || t.v === ';'));
    }
    // The head of a loop with `of yield …` just closed (at `)`): where can the operand go?
    function loopClosed(loop, closeAt) {
      var t1 = loop.before[0], t2 = loop.before[1], t3 = loop.before[2];
      var rec = { insertAt: loop.forAt, yieldAt: loop.yieldAt, closeAt: closeAt, wrap: false, blockEnd: -1 };
      if (isBoundary(t1)) return found.push(rec);
      if (t1.k === 'p' && t1.v === ':') {
        // `label: for` → before the label (it must stay on the loop); `case x:` / `default:` → here.
        if (t2 && t2.k === 'id' && t2.v !== 'default' && isBoundary(t3)) rec.insertAt = t2.s;
        return found.push(rec);
      }
      if ((t1.k === 'p' && t1.v === ')') || (t1.k === 'id' && (t1.v === 'else' || t1.v === 'do'))) {
        rec.wrap = true;
        pending = rec;
      }
    }

    while (i < n) {
      var c = src[i], s = i;
      if (isSpace(c)) { i++; continue; }
      if (c === '/' && (src[i + 1] === '/' || src[i + 1] === '*')) { i = skipSpace(i); continue; }
      if (pending) {
        if (c === '{') stack.push({ c: '{', wrap: pending });
        pending = null;
        if (c === '{') { i++; push('{', 'p', s); continue; }
      }
      if (c === '"' || c === "'") { skipString(c); push('', 'str', s); continue; }
      if (c === '`') {
        i++;
        if (skipTemplate()) push('${', 'p', s);
        else push('', 'str', s);
        continue;
      }
      if (c === '/') {
        if (regexAllowed()) { skipRegex(); push('', 'str', s); }
        else { i++; push('/', 'p', s); }
        continue;
      }
      if ((c >= '0' && c <= '9') || (c === '.' && src[i + 1] >= '0' && src[i + 1] <= '9')) {
        NUMBER.lastIndex = i;
        var m = NUMBER.exec(src);
        i = m && m[0].length ? i + m[0].length : i + 1;
        push('', 'num', s);
        continue;
      }
      if (isIdPart(c)) {
        while (i < n && isIdPart(src[i])) i++;
        var word = src.slice(s, i);
        var prev = last();
        var prop = !!prev && prev.k === 'p' && prev.v === '.';
        var top = stack[stack.length - 1];
        if (!prop && word === 'of' && top && top.loop && !top.loop.sawOf) {
          top.loop.sawOf = true;
          var j = skipSpace(i);
          if (atWord(j, 'yield')) top.loop.yieldAt = j;
        }
        push(word, prop ? 'prop' : 'id', s);
        continue;
      }
      i++;
      if (c === '(') {
        var p1 = last();
        var loop = p1 && p1.k === 'id' && p1.v === 'for'
          ? { forAt: p1.s, before: [last(1), last(2), last(3)], yieldAt: -1, sawOf: false } : null;
        stack.push({ c: '(', loop: loop });
      } else if (c === ')') {
        var open = stack.pop();
        if (open && open.loop && open.loop.yieldAt >= 0) loopClosed(open.loop, s);
      } else if (c === '[' || c === '{') {
        stack.push({ c: c });
      } else if (c === ']') {
        stack.pop();
      } else if (c === '}') {
        var closed = stack.pop();
        if (closed && closed.c === '${') {
          if (skipTemplate()) push('${', 'p', s);
          else push('', 'str', s);
          continue;
        }
        if (closed && closed.wrap) {
          closed.wrap.blockEnd = i;
          found.push(closed.wrap);
        }
      } else if ((c === '+' || c === '-') && src[i] === c) {
        i++;
        push(c + c, 'p', s);
        continue;
      }
      push(c, 'p', s);
    }

    if (!found.length) return null;
    var edits = [];
    found.forEach(function (r, k) {
      var name = '__vxOf' + k;
      edits.push({ at: r.insertAt, end: r.insertAt, text: (r.wrap ? '{' : '') + 'var ' + name + '=' + src.slice(r.yieldAt, r.closeAt) + ';' });
      edits.push({ at: r.yieldAt, end: r.closeAt, text: name });
      if (r.wrap) edits.push({ at: r.blockEnd, end: r.blockEnd, text: '}' });
    });
    edits.sort(function (a, b) { return a.at - b.at || a.end - b.end; });
    for (var k = 1; k < edits.length; k++) if (edits[k].at < edits[k - 1].end) return null; // nested: give up
    var out = '', pos = 0;
    edits.forEach(function (e) {
      out += src.slice(pos, e.at) + e.text;
      pos = e.end;
    });
    return out + src.slice(pos);
  }

  // ------------------------------------------------------------------------------------- run
  function finish(result) {
    if (vx.finished) return;
    vx.finished = true;
    result.t = 'done';
    push(result);
  }

  // The modules Nuvio lends to `require`: CryptoJS when the host loaded it for this scraper (it does
  // when the code mentions it). cheerio is not lent: Nuvio bundles carry their own.
  function requireModule(name) {
    if (name === 'crypto-js' && g.CryptoJS) return g.CryptoJS;
    throw new Error("Module '" + name + "' is not available");
  }

  function compile(code) {
    return new Function('module', 'exports', 'require', code + '\n//# sourceURL=scraper.js');
  }

  vx.run = function (code, params, libs) {
    var module = { exports: {} };
    // Libraries the host lends to this scraper (CryptoJS), each run as a classic browser script.
    try {
      (libs || []).forEach(function (lib) { new Function('module', 'exports', 'define', lib).call(g); });
    } catch (e) {
      return finish({ ok: false, error: 'Chargement d\u2019une bibliothèque impossible : ' + msg(e) });
    }
    // What Nuvio sets before a scraper runs: its id and its settings (Vixeo has no settings page
    // for a scraper: always the defaults).
    g.SCRAPER_ID = params.scraperId ? String(params.scraperId) : '';
    g.SCRAPER_SETTINGS = params.settings && typeof params.settings === 'object' ? params.settings : {};
    var factory;
    try {
      try {
        factory = compile(code);
      } catch (e) {
        var fixed = e && e.name === 'InternalError' ? hoistForOfYield(code) : null;
        if (!fixed) throw e;
        try { factory = compile(fixed); } catch (e2) { throw e; }
      }
      factory(module, module.exports, requireModule);
    } catch (e) {
      return finish({ ok: false, error: 'Chargement du scraper impossible : ' + msg(e) });
    }
    var mod = module.exports || {};
    var getStreams = mod.getStreams || (mod.default && mod.default.getStreams) || g.getStreams;
    if (typeof getStreams !== 'function') {
      return finish({ ok: false, error: "Le scraper n'exporte pas getStreams." });
    }
    // Like Nuvio: a film has no season nor episode (undefined, not null).
    var season = params.season == null ? undefined : params.season;
    var episode = params.episode == null ? undefined : params.episode;
    Promise.resolve()
      .then(function () { return getStreams(String(params.tmdbId), params.mediaType, season, episode); })
      .then(
        function (streams) { finish({ ok: true, streams: Array.isArray(streams) ? streams : [] }); },
        function (e) { finish({ ok: false, error: msg(e) }); },
      );
  };
})(globalThis);
