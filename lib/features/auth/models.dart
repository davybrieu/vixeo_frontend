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

/// Viewer profile ("Qui regarde ?", ProfileResource).
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.avatar,
    this.isKid = false,
    this.maxAgeRating,
    this.effectiveMaxAgeRating,
    this.hasPin = false,
    this.position = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as int,
    name: json['name'] as String,
    avatar: json['avatar'] as String?,
    isKid: json['is_kid'] as bool? ?? false,
    maxAgeRating: json['max_age_rating'] as int?,
    effectiveMaxAgeRating: json['effective_max_age_rating'] as int?,
    hasPin: json['has_pin'] as bool? ?? false,
    position: json['position'] as int? ?? 0,
  );

  final int id;
  final String name;
  final String? avatar;
  final bool isKid;
  final int? maxAgeRating;

  /// Age limit actually applied by the API (null = none).
  final int? effectiveMaxAgeRating;
  final bool hasPin;
  final int position;

  /// First letter, shown on the avatar tile.
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}
