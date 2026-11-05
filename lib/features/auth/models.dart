/// Account returned by `GET /me` (UserResource).
class User {
  const User({required this.id, required this.name, required this.email, required this.parentalControl});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    parentalControl: json['parental_control'] as bool? ?? false,
  );

  final int id;
  final String name;
  final String email;

  /// A parental PIN is set on the account.
  final bool parentalControl;
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

/// How a profile wants titles drawn in rows and grids.
enum PosterFormat {
  /// Vertical poster (2:3). Default.
  portrait,

  /// Horizontal image (16:9).
  landscape;

  static PosterFormat parse(Object? value) => value == 'landscape' ? landscape : portrait;

  String get label => this == portrait ? 'Vertical' : 'Horizontal';
}

/// Viewer profile ("Qui regarde ?", ProfileResource).
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.avatar,
    this.posterFormat = PosterFormat.portrait,
    this.isKid = false,
    this.maxAgeRating,
    this.effectiveMaxAgeRating,
    this.hasPin = false,
    this.position = 0,
    this.allowUnrated = false,
    this.audioLanguage,
    this.subtitleLanguage,
    this.skipIntro = false,
    this.skipRecap = false,
    this.skipCredits = false,
    this.skipPreview = false,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as int,
    name: json['name'] as String,
    avatar: json['avatar'] as String?,
    posterFormat: PosterFormat.parse(json['poster_format']),
    isKid: json['is_kid'] as bool? ?? false,
    maxAgeRating: json['max_age_rating'] as int?,
    effectiveMaxAgeRating: json['effective_max_age_rating'] as int?,
    hasPin: json['has_pin'] as bool? ?? false,
    position: json['position'] as int? ?? 0,
    allowUnrated: json['allow_unrated'] as bool? ?? false,
    audioLanguage: json['audio_language'] as String?,
    subtitleLanguage: json['subtitle_language'] as String?,
    skipIntro: json['skip_intro'] as bool? ?? false,
    skipRecap: json['skip_recap'] as bool? ?? false,
    skipCredits: json['skip_credits'] as bool? ?? false,
    skipPreview: json['skip_preview'] as bool? ?? false,
  );

  final int id;
  final String name;

  /// Avatar id from `GET /avatars` (null = initial letter).
  final String? avatar;
  final PosterFormat posterFormat;
  final bool isKid;
  final int? maxAgeRating;

  /// Age limit actually applied by the API (null = none).
  final int? effectiveMaxAgeRating;
  final bool hasPin;
  final int position;

  /// With an age limit: also show titles without a known age rating.
  final bool allowUnrated;

  /// Preferred audio language ("fr"…), null = original version (docs: vixeo_backend/docs/lecture.md).
  final String? audioLanguage;

  /// Preferred subtitles ("fr", "pt-BR"…), null = none.
  final String? subtitleLanguage;

  /// Moments the player skips by itself; otherwise it shows a "Passer" button.
  final bool skipIntro;
  final bool skipRecap;
  final bool skipCredits;
  final bool skipPreview;

  /// First letter, shown on the avatar tile.
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}
