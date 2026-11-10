class TvCategory {
  const TvCategory({required this.id, required this.name, this.parentId});

  final String id;
  final String name;
  final String? parentId;

  factory TvCategory.fromJson(Map<String, dynamic> json) =>
      TvCategory(id: '${json['id'] ?? ''}', name: '${json['name'] ?? ''}', parentId: json['parent_id']?.toString());
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
  final String? logo;
  final int? number;
  final String? epgChannelId;

  factory TvChannel.fromJson(Map<String, dynamic> json) => TvChannel(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    categoryId: '${json['category_id'] ?? ''}',
    logo: json['logo'] as String?,
    number: json['number'] is int ? json['number'] as int : int.tryParse('${json['number'] ?? ''}'),
    epgChannelId: json['epg_channel_id'] as String?,
  );
}

class TvStream {
  const TvStream({required this.url, required this.format, this.headers = const {}, this.sources = const []});

  final String url;
  final String format; // hls | ts
  final Map<String, String> headers;

  /// Every playable URL the server resolved for this channel, best first. The player falls back
  /// to the next one when a stream refuses to start. Always contains [url].
  final List<String> sources;

  factory TvStream.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) headers['$k'] = '$v';
      });
    }

    final url = '${json['url'] ?? ''}';
    final rawSources = json['sources'];
    final sources = <String>[];
    if (rawSources is List) {
      for (final entry in rawSources) {
        final value = '$entry';
        if (value.isNotEmpty && !sources.contains(value)) sources.add(value);
      }
    }
    if (url.isNotEmpty && !sources.contains(url)) sources.insert(0, url);

    return TvStream(url: url, format: '${json['format'] ?? 'hls'}', headers: headers, sources: sources);
  }
}
