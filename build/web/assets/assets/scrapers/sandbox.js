/*
 * Vixeo scraper sandbox: the prelude every scraper runs on top of (docs/scrapers.md).
 *
 * The SAME file runs on Android and iOS (QuickJS), in a sandboxed iframe on the web, and in the
 * reference runner of the server (tools/scraper-runner). It gives a scraper the few browser-like
 * globals Nuvio scrapers expect (console, fetch, URL, URLSearchParams, TextEncoder, atob, timers…)
 * and NOTHING else: no network of its own, no storage, no file, no DOM. Every request goes
 * through the host (`__vx`), which checks it (https only, no private address, size and count
 * limits) and does it.
 *
 * Host protocol (a message is a plain JSON-able object):
 *   host  → eval("__vx.run(code, params)")      starts the scraper
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
    outbox: [],
    emit: null,
    logs: 0,
    finished: false,
  };
  Object.defineProperty(g, '__vx', { value: vx, enumerable: false, writable: false, configurable: false });
  g.global = g;
  g.self = g;
  // The browser's own doors to the network and to the page do not exist for a scraper.
  ['XMLHttpRequest', 'WebSocket', 'EventSource', 'importScripts', 'Worker', 'SharedWorker', 'indexedDB',
    'localStorage', 'sessionStorage', 'navigator', 'open'].forEach(function (name) {
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
  g.clearTimeout = function (id) { delete vx.timers[id]; };
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
    json() {
      this.bodyUsed = true;
      var body = this._body;
      return new Promise(function (resolve) { resolve(JSON.parse(body)); });
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
      vx.pending[id] = { resolve: resolve, reject: reject };
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

  vx.deliver = function (id, res) {
    var p = vx.pending[id];
    if (!p) return;
    delete vx.pending[id];
    if (!res || res.error) {
      p.reject(new TypeError('Network request failed' + (res && res.error ? ': ' + res.error : '')));
      return;
    }
    p.resolve(new Response(res.body, res));
  };

  // ------------------------------------------------------------------------------------- run
  function finish(result) {
    if (vx.finished) return;
    vx.finished = true;
    result.t = 'done';
    push(result);
  }

  vx.run = function (code, params) {
    var module = { exports: {} };
    var require = function (name) { throw new Error("Cannot find module '" + name + "'"); };
    try {
      new Function('module', 'exports', 'require', code + '\n//# sourceURL=scraper.js')(module, module.exports, require);
    } catch (e) {
      return finish({ ok: false, error: 'Chargement du scraper impossible : ' + msg(e) });
    }
    var mod = module.exports || {};
    var getStreams = mod.getStreams || (mod.default && mod.default.getStreams) || g.getStreams;
    if (typeof getStreams !== 'function') {
      return finish({ ok: false, error: "Le scraper n'exporte pas getStreams." });
    }
    Promise.resolve()
      .then(function () { return getStreams(params.tmdbId, params.mediaType, params.season, params.episode); })
      .then(
        function (streams) { finish({ ok: true, streams: Array.isArray(streams) ? streams : [] }); },
        function (e) { finish({ ok: false, error: msg(e) }); },
      );
  };
})(globalThis);
