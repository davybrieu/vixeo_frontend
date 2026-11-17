/// WebVTT subtitles (what the API serves, `/catalog/subtitles/{id}`), read into cues the player
/// shows itself: the same text, in the same place and style, whatever engine plays the video
/// (no `<track>` element on the web, no native caption view on Android / iOS).
library;

import 'package:flutter/foundation.dart';

/// One line of subtitles and when it is on screen.
@immutable
class CaptionCue {
  const CaptionCue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

final _time = RegExp(r'(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})');
final _tag = RegExp(r'<[^>]*>');

Duration? _parseTime(String value) {
  final match = _time.firstMatch(value);
  if (match == null) return null;
  return Duration(
    hours: int.tryParse(match.group(1) ?? '0') ?? 0,
    minutes: int.tryParse(match.group(2) ?? '0') ?? 0,
    seconds: int.tryParse(match.group(3) ?? '0') ?? 0,
    milliseconds: int.tryParse(match.group(4) ?? '0') ?? 0,
  );
}

String _plainText(String text) => text
    .replaceAll(_tag, '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .trim();

/// The cues of a WebVTT file (SRT times, with a comma, are read too). Header, notes, styles,
/// cue numbers, position settings (`line:0 align:start`) and tags (`<i>`, `<v Name>`) are left out.
List<CaptionCue> parseWebVtt(String input) {
  final cues = <CaptionCue>[];
  final blocks = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n{2,}'));
  for (final block in blocks) {
    final lines = block.split('\n');
    final index = lines.indexWhere((line) => line.contains('-->'));
    if (index < 0) continue;
    final parts = lines[index].split('-->');
    if (parts.length != 2) continue;
    final start = _parseTime(parts[0]);
    final end = _parseTime(parts[1]);
    final text = _plainText(lines.skip(index + 1).join('\n'));
    if (start != null && end != null && text.isNotEmpty) cues.add(CaptionCue(start, end, text));
  }
  return cues;
}

/// The text on screen at [position], if any.
String? captionAt(List<CaptionCue> cues, Duration position) {
  for (final cue in cues) {
    if (position >= cue.start && position < cue.end) return cue.text;
  }
  return null;
}
