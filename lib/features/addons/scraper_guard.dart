/// What a scraper may ask for, and how much (`docs/scrapers.md` §5). The same rules apply on the
/// device, on the server (`/scrapers/fetch`) and in `tools/scraper-runner/guard.mjs`: a scraper
/// is somebody else's code, so it never reaches the local network or an address that is not
/// `https://`.
library;

/// The limits of one scraper run. They follow the Nuvio app, which the scrapers of Nuvio
/// repositories are written for (a run may take a minute, a request 30 s like on NuvioTV, timers
/// may be as long as the run); the request count is a safety net Nuvio does not have, well above
/// what a real scraper asks.
class ScraperLimits {
  const ScraperLimits({
    this.run = const Duration(seconds: 60),
    this.request = const Duration(seconds: 30),
    this.timer = const Duration(seconds: 60),
    this.requests = 200,
    this.responseBytes = 5 * 1024 * 1024,
    this.requestBody = 256 * 1024,
    this.redirects = 5,
    this.streams = 100,
  });

  static const standard = ScraperLimits();

  /// The whole run (the JavaScript is stopped when it is over).
  final Duration run;

  /// One request.
  final Duration request;

  /// One `setTimeout` (a longer one is cut to this).
  final Duration timer;

  /// `fetch` calls per run.
  final int requests;

  /// One response (the rest is cut, and [ScraperGuard.truncated] is added, as Nuvio does).
  final int responseBytes;

  /// The body of one request.
  final int requestBody;
  final int redirects;
  final int streams;
}

abstract final class ScraperGuard {
  /// Added to a response cut at [ScraperLimits.responseBytes], exactly as Nuvio does: scrapers look
  /// for it before parsing a page.
  static const truncated = '\n...[truncated]';

  /// A request in `http://` is made in `https://`: Nuvio allows http, Vixeo never sends a scraper's
  /// request in clear, and most sites answer both. Anything else is returned as it is (trimmed).
  static String upgrade(String url) {
    final text = url.trim();
    return text.length > 7 && text.substring(0, 7).toLowerCase() == 'http://' ? 'https://${text.substring(7)}' : text;
  }

  static const _blockedSuffixes = ['.local', '.localhost', '.internal', '.lan', '.home', '.corp', '.intranet'];

  /// Looks like an IPv4 address in any notation (`127.1`, `2130706433`, `0x7f000001`).
  static final _numericHost = RegExp(r'^(0x[0-9a-f]*|\d+)(\.(0x[0-9a-f]*|\d+))*$');
  static final _dottedQuad = RegExp(r'^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$');

  /// Why [raw] is refused, in French, or null when a scraper may request it.
  static String? check(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return 'adresse invalide';
    if (uri.scheme != 'https') return 'seul https est autorisé';
    if (uri.userInfo.isNotEmpty) return 'identifiants dans l’adresse interdits';
    var host = uri.host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return 'hôte manquant';
    if (host == 'localhost' || _blockedSuffixes.any(host.endsWith)) return 'hôte local interdit';
    if (host.contains(':')) return isPrivateV6(host) ? 'adresse privée interdite' : null;
    if (_numericHost.hasMatch(host)) {
      // Only the plain dotted form is understood; the exotic ones are how filters get bypassed.
      if (!_dottedQuad.hasMatch(host)) return 'adresse IP non standard interdite';
      final octets = [for (final part in host.split('.')) int.parse(part)];
      if (octets.any((o) => o > 255)) return 'adresse invalide';
      return isPrivateV4(octets) ? 'adresse privée interdite' : null;
    }
    if (!host.contains('.')) return 'hôte sans domaine interdit';
    return null;
  }

  /// Loopback, private, link-local, shared (CGNAT), reserved and multicast addresses. Of 192.0/16,
  /// only 192.0.0/24 (IETF) and 192.0.2/24 (documentation) are reserved: the rest is public.
  static bool isPrivateV4(List<int> o) {
    final [a, b, c, ...] = o;
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 192 && b == 0 && (c == 0 || c == 2)) ||
        a >= 224;
  }

  /// [text] is an IPv6 address without brackets, in any notation. What cannot be read is refused.
  static bool isPrivateV6(String text) {
    final g = _parseV6(text);
    if (g == null) return true;
    final first96Zero = g.sublist(0, 6).every((x) => x == 0);
    if (first96Zero) return true; // ::, ::1 and the old IPv4-compatible form
    if ((g[0] & 0xfe00) == 0xfc00) return true; // fc00::/7, unique local
    if ((g[0] & 0xffc0) == 0xfe80 || (g[0] & 0xffc0) == 0xfec0) return true; // link-local, site-local
    if ((g[0] >> 8) == 0xff) return true; // multicast
    bool v4(int hi, int lo) => isPrivateV4([hi >> 8, hi & 255, lo >> 8, lo & 255]);
    if (g.sublist(0, 5).every((x) => x == 0) && g[5] == 0xffff) return v4(g[6], g[7]); // ::ffff:a.b.c.d
    if (g[0] == 0x64 && g[1] == 0xff9b && g.sublist(2, 6).every((x) => x == 0)) return v4(g[6], g[7]); // NAT64
    if (g[0] == 0x2002) return v4(g[1], g[2]); // 6to4
    return false;
  }

  /// The eight 16-bit groups of an IPv6 address, or null when it is not one.
  static List<int>? _parseV6(String text) {
    var s = text;
    final zone = s.indexOf('%');
    if (zone >= 0) s = s.substring(0, zone);
    List<int>? tail4;
    if (s.contains('.')) {
      final cut = s.lastIndexOf(':');
      final parts = s.substring(cut + 1).split('.');
      if (parts.length != 4) return null;
      final octets = [for (final p in parts) int.tryParse(p)];
      if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
      tail4 = [(octets[0]! << 8) | octets[1]!, (octets[2]! << 8) | octets[3]!];
      s = '${s.substring(0, cut + 1)}0:0';
    }
    final halves = s.split('::');
    if (halves.length > 2) return null;
    List<int>? groups(String part) {
      if (part.isEmpty) return [];
      final out = <int>[];
      for (final g in part.split(':')) {
        final v = int.tryParse(g, radix: 16);
        if (g.isEmpty || g.length > 4 || v == null) return null;
        out.add(v);
      }
      return out;
    }

    final head = groups(halves[0]);
    final tail = halves.length == 2 ? groups(halves[1]) : <int>[];
    if (head == null || tail == null) return null;
    final List<int> all;
    if (halves.length == 2) {
      final missing = 8 - head.length - tail.length;
      if (missing < 1) return null;
      all = [...head, ...List.filled(missing, 0), ...tail];
    } else {
      all = [...head];
    }
    if (all.length != 8) return null;
    if (tail4 != null) {
      all[6] = tail4[0];
      all[7] = tail4[1];
    }
    return all;
  }
}
