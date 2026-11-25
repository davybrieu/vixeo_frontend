import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The social networks a profile can show (developer's request, 21/11/2026), in the order of the
/// profile pages; the same keys as the API (`social_links`, vixeo_backend/docs/social.md).
enum SocialNetwork {
  instagram('instagram', 'Instagram', FontAwesomeIcons.instagram),
  x('x', 'X', FontAwesomeIcons.xTwitter),
  tiktok('tiktok', 'TikTok', FontAwesomeIcons.tiktok),
  youtube('youtube', 'YouTube', FontAwesomeIcons.youtube),
  letterboxd('letterboxd', 'Letterboxd', FontAwesomeIcons.film),
  threads('threads', 'Threads', FontAwesomeIcons.threads),
  bluesky('bluesky', 'Bluesky', FontAwesomeIcons.bluesky),
  website('website', 'Site web', FontAwesomeIcons.globe);

  const SocialNetwork(this.key, this.label, this.icon);

  /// The API's key.
  final String key;
  final String label;
  final FaIconData icon;

  /// An account is a handle (`@lea`); the website is an address.
  bool get isWebsite => this == website;

  static SocialNetwork? of(String? key) => values.where((network) => network.key == key).firstOrNull;
}

/// One account of a profile: `{network, label, handle, url}` from the API.
class SocialLink {
  const SocialLink({required this.network, required this.handle, required this.url});

  /// Null for a network the API knows and this app doesn't (an older app): not shown.
  static SocialLink? fromJson(Map<String, dynamic> json) {
    final network = SocialNetwork.of(json['network'] as String?);
    final handle = json['handle'] as String? ?? '';
    final url = json['url'] as String? ?? '';
    if (network == null || handle.isEmpty || !url.startsWith('https://') && !url.startsWith('http://')) return null;
    return SocialLink(network: network, handle: handle, url: url);
  }

  static List<SocialLink> listOf(Object? json) => [
    if (json is List)
      for (final item in json.whereType<Map<String, dynamic>>()) ?fromJson(item),
  ];

  final SocialNetwork network;

  /// The account without its « @ » (`lea`), or the website's address.
  final String handle;

  /// The account's page.
  final String url;

  /// What the profile page writes: `@lea`, or the website without `https://` and `www.`.
  String get display {
    if (!network.isWebsite) return '@$handle';
    final short = handle.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').replaceFirst(RegExp('^www\\.'), '');
    return short.endsWith('/') ? short.substring(0, short.length - 1) : short;
  }
}
