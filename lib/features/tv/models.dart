class TvCategory {
  const TvCategory({required this.id, required this.name, this.parentId});

  final String id;
  final String name;
  final String? parentId;

  factory TvCategory.fromJson(Map<String, dynamic> json) =>
      TvCategory(id: '${json['id'] ?? ''}', name: '${json['name'] ?? ''}', parentId: json['parent_id']?.toString());

  @override
  bool operator ==(Object other) => other is TvCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class TvChannel {
  const TvChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.logo,
    this.number,
    this.epgChannelId,
  });

  final String id;
  final String name;
  final String categoryId;

  /// The provider's logo URL, shown as is by the app (never downloaded by the Vixeo server). An
  /// `http://` address is turned into `https://`: a release Android build refuses cleartext, and
  /// browsers upgrade images the same way. Empty → null.
  final String? logo;
  final int? number;
  final String? epgChannelId;

  factory TvChannel.fromJson(Map<String, dynamic> json) => TvChannel(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    categoryId: '${json['category_id'] ?? ''}',
    logo: _logoUrl(json['logo']),
    number: json['number'] is int ? json['number'] as int : int.tryParse('${json['number'] ?? ''}'),
    epgChannelId: json['epg_channel_id'] as String?,
  );
}

String? _logoUrl(Object? value) {
  final url = value is String ? value.trim() : '';
  if (url.isEmpty) return null;
  return url.startsWith('http://') ? 'https://${url.substring('http://'.length)}' : url;
}

class TvStream {
  const TvStream({required this.url, required this.format, this.headers = const {}});

  final String url;
  final String format; // hls | ts
  final Map<String, String> headers;

  factory TvStream.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) headers['$k'] = '$v';
      });
    }

    final url = '${json['url'] ?? ''}';

    return TvStream(url: url, format: '${json['format'] ?? 'hls'}', headers: headers);
  }
}

/// One programme of a channel's guide (`/tv/channels/{id}/epg`), times in local time.
class TvProgramme {
  const TvProgramme({
    required this.title,
    required this.start,
    required this.end,
    this.subtitle,
    this.description,
    this.category,
    this.image,
  });

  factory TvProgramme.fromJson(Map<String, dynamic> json) => TvProgramme(
    title: '${json['title'] ?? ''}',
    subtitle: _text(json['subtitle']),
    description: _text(json['description']),
    category: _text(json['category']),
    image: _text(json['image']),
    start: DateTime.parse('${json['start']}').toLocal(),
    end: DateTime.parse('${json['end']}').toLocal(),
  );

  final String title;
  final String? subtitle;
  final String? description;
  final String? category;
  final String? image;
  final DateTime start;
  final DateTime end;

  bool isOnAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// Share of the programme already shown, 0 to 1.
  double progressAt(DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0, 1).toDouble();
  }

  static String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// A channel's guide: [available] is false when the server has no guide at all.
class TvGuide {
  const TvGuide({required this.programmes, required this.available});

  factory TvGuide.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return TvGuide(
      programmes: data is List
          ? data.whereType<Map>().map((e) => TvProgramme.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      available: json['available'] as bool? ?? false,
    );
  }

  final List<TvProgramme> programmes;
  final bool available;
}
