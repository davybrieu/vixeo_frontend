// Which requests a scraper may make. The SAME rules apply on the device (lib/features/addons/
// scraper_guard.dart), in the server's /scrapers/fetch proxy and in this runner (docs/scrapers.md §5).

// The values follow the Nuvio app, which the scrapers of Nuvio repositories are written for: a
// scraper may take up to a minute and set timers that long, one request may wait 30 s (NuvioTV's
// HTTP timeout). The request count is a safety net Nuvio does not have, set well above what a real
// scraper asks.
export const LIMITS = {
  requests: 200, // fetch calls per run
  responseBytes: 5 * 1024 * 1024, // per response; the rest is cut (and TRUNCATED is added)
  requestBody: 256 * 1024,
  runMs: 60_000, // the whole run
  requestMs: 30_000, // one request
  timerMs: 60_000, // one setTimeout
  redirects: 5,
  streams: 100,
  memory: 256 * 1024 * 1024,
  stack: 1024 * 1024,
};

/** Added to a body cut at `responseBytes`, as Nuvio does: scrapers look for it. */
export const TRUNCATED = '\n...[truncated]';

/**
 * A request in `http://` is made in `https://` (Nuvio allows http; Vixeo never sends a scraper's
 * request in clear, and most sites answer both).
 */
export function upgradeUrl(raw) {
  return /^http:\/\//i.test(raw) ? `https://${raw.slice(7)}` : raw;
}

const BLOCKED_SUFFIXES = ['.local', '.localhost', '.internal', '.lan', '.home', '.corp', '.intranet'];

/** @returns {string|null} why the address is refused, or null when it is allowed. */
export function checkUrl(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    return 'adresse invalide';
  }
  if (url.protocol !== 'https:') return 'seul https est autorisé';
  if (url.username || url.password) return 'identifiants dans l’adresse interdits';
  const host = url.hostname.toLowerCase().replace(/\.$/, '');
  if (!host) return 'hôte manquant';
  if (host === 'localhost' || BLOCKED_SUFFIXES.some((s) => host.endsWith(s))) return 'hôte local interdit';
  if (!host.includes('.') && !host.startsWith('[')) return 'hôte sans domaine interdit';
  if (host.startsWith('[')) return isPrivateV6(host.slice(1, -1)) ? 'adresse privée interdite' : null;
  // Dotted-quad, or the decimal / hex forms the URL parser already turned into dotted-quad.
  const m = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(host);
  if (m) return isPrivateV4(m.slice(1).map(Number)) ? 'adresse privée interdite' : null;
  return null;
}

// Of 192.0/16, only 192.0.0/24 (IETF) and 192.0.2/24 (documentation) are reserved (Dart: isPrivateV4).
export function isPrivateV4([a, b, c]) {
  return (
    a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 192 && b === 0 && (c === 0 || c === 2)) ||
    a >= 224
  );
}

export function isPrivateV6(text) {
  const g = parseV6(text);
  if (!g) return true; // what cannot be read is refused
  if (g.slice(0, 6).every((x) => x === 0)) return true; // ::, ::1 and the old IPv4-compatible form
  if ((g[0] & 0xfe00) === 0xfc00) return true; // fc00::/7, unique local
  if ((g[0] & 0xffc0) === 0xfe80 || (g[0] & 0xffc0) === 0xfec0) return true; // link-local, site-local
  if (g[0] >> 8 === 0xff) return true; // multicast
  const v4 = (hi, lo) => isPrivateV4([hi >> 8, hi & 255, lo >> 8, lo & 255]);
  if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) return v4(g[6], g[7]); // ::ffff:a.b.c.d
  if (g[0] === 0x64 && g[1] === 0xff9b && g.slice(2, 6).every((x) => x === 0)) return v4(g[6], g[7]); // NAT64
  if (g[0] === 0x2002) return v4(g[1], g[2]); // 6to4
  return false;
}

/** The eight 16-bit groups of an IPv6 address (no brackets), or null when it is not one. */
export function parseV6(text) {
  let s = text.split('%')[0];
  let tail4 = null;
  if (s.includes('.')) {
    const cut = s.lastIndexOf(':');
    const parts = s.slice(cut + 1).split('.');
    if (parts.length !== 4) return null;
    const o = parts.map((p) => (/^\d+$/.test(p) ? Number(p) : NaN));
    if (o.some((x) => !(x >= 0 && x <= 255))) return null;
    tail4 = [(o[0] << 8) | o[1], (o[2] << 8) | o[3]];
    s = `${s.slice(0, cut + 1)}0:0`;
  }
  const halves = s.split('::');
  if (halves.length > 2) return null;
  const groups = (part) => {
    if (part === '') return [];
    const out = [];
    for (const x of part.split(':')) {
      if (!/^[0-9a-fA-F]{1,4}$/.test(x)) return null;
      out.push(parseInt(x, 16));
    }
    return out;
  };
  const head = groups(halves[0]);
  const tail = halves.length === 2 ? groups(halves[1]) : [];
  if (!head || !tail) return null;
  let all;
  if (halves.length === 2) {
    const missing = 8 - head.length - tail.length;
    if (missing < 1) return null;
    all = [...head, ...Array(missing).fill(0), ...tail];
  } else {
    all = [...head];
  }
  if (all.length !== 8) return null;
  if (tail4) [all[6], all[7]] = tail4;
  return all;
}
