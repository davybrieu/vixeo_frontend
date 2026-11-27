import '../social/social_links.dart';

/// Account returned by `GET /me` (UserResource).
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.hasPassword = true,
    this.providers = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    hasPassword: json['has_password'] as bool? ?? true,
    providers: [for (final p in json['providers'] as List? ?? const []) p as String],
  );

  final int id;
  final String name;
  final String email;

  /// False for an account created with Google or Apple that never chose a password: « Mon compte »
  /// offers to create one.
  final bool hasPassword;

  /// Google and Apple accounts linked to this one (`google`, `apple`).
  final List<String> providers;
}

/// A signed-in device of the account (one API token): `GET /me/devices`.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.current,
    this.signedInAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    current: json['current'] as bool? ?? false,
    signedInAt: DateTime.tryParse(json['signed_in_at'] as String? ?? '')?.toLocal(),
    lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? '')?.toLocal(),
    expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '')?.toLocal(),
  );

  final int id;
  final String name;

  /// The device making the request (this app).
  final bool current;
  final DateTime? signedInAt;
  final DateTime? lastUsedAt;

  /// After this date the device has to sign in again.
  final DateTime? expiresAt;
}

/// Viewer profile ("Qui regarde ?", ProfileResource).
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.username,
    this.bio,
    this.avatar,
    this.photoUrl,
    this.cover,
    this.coverUrl,
    this.position = 0,
    this.audioLanguage,
    this.subtitleLanguage,
    this.noSpoiler = false,
    this.skipIntro = false,
    this.skipRecap = false,
    this.skipCredits = false,
    this.skipPreview = false,
    this.isPrivate = false,
    this.socialLinks = const [],
    this.rateAfterWatching = true,
    this.onboarded = true,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as int,
    name: json['name'] as String,
    username: json['username'] as String?,
    bio: json['bio'] as String?,
    avatar: json['avatar'] as String?,
    photoUrl: json['photo_url'] as String?,
    cover: json['cover'] as String?,
    coverUrl: json['cover_url'] as String?,
    position: json['position'] as int? ?? 0,
    audioLanguage: json['audio_language'] as String?,
    subtitleLanguage: json['subtitle_language'] as String?,
    noSpoiler: json['no_spoiler'] as bool? ?? false,
    skipIntro: json['skip_intro'] as bool? ?? false,
    skipRecap: json['skip_recap'] as bool? ?? false,
    skipCredits: json['skip_credits'] as bool? ?? false,
    skipPreview: json['skip_preview'] as bool? ?? false,
    isPrivate: json['is_private'] as bool? ?? false,
    socialLinks: SocialLink.listOf(json['social_links']),
    rateAfterWatching: json['rate_after_watching'] as bool? ?? true,
    // An older API doesn't say: no first launch.
    onboarded: json['onboarded'] as bool? ?? true,
  );

  final int id;
  final String name;
  final String? username;
  final String? bio;

  /// Avatar id from `GET /avatars` (null = initial letter).
  final String? avatar;

  /// Its own photo (`photo_url`), shown instead of [avatar]; null = the avatar.
  final String? photoUrl;

  /// Cover id from `GET /covers`: the banner of its page.
  final String? cover;

  /// Its own cover image (`cover_url`), shown instead of [cover]; null = [cover].
  final String? coverUrl;

  final int position;

  /// Preferred audio language ("fr"…), null = original version (docs: vixeo_backend/docs/lecture.md).
  final String? audioLanguage;

  /// Preferred subtitles ("fr", "pt-BR"…), null = none.
  final String? subtitleLanguage;

  /// Hide episode artwork, titles and descriptions until selected.
  final bool noSpoiler;

  /// Moments the player skips by itself; otherwise it shows a "Passer" button.
  final bool skipIntro;
  final bool skipRecap;
  final bool skipCredits;
  final bool skipPreview;

  /// A private account (like Twitter): only its accepted followers see its lists and reviews
  /// (vixeo_backend/docs/social.md).
  final bool isPrivate;

  /// Its accounts on social networks (« Modifier mon profil »), shown on its page.
  final List<SocialLink> socialLinks;

  /// At the end of a movie or an episode, the player proposes to rate it (« Paramètres du
  /// profil » → « Proposer de noter à la fin »).
  final bool rateAfterWatching;

  /// The first launch (rate known titles, accounts to follow) was done or skipped.
  final bool onboarded;

  /// First letter, shown on the avatar tile.
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}
