import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/features/tv/channel_row.dart';
import 'package:vixeo/features/tv/models.dart';

TvChannel channel(String id, String category) => TvChannel(id: id, name: id.toUpperCase(), categoryId: category);

/// « Title: id, id » per row (records holding lists don't compare deeply).
List<String> rows(List<ChannelSection> sections) => [
  for (final s in sections) '${s.title}: ${s.channels.map((c) => c.id).join(', ')}',
];

/// Home rows of live channels: généralistes, sport, info, enfants (developer's request).
void main() {
  test('« Chaînes TV » page: one row per category, in the order of the categories', () {
    final sections = channelCategorySections(
      const [
        TvCategory(id: 'sport', name: 'Sport'),
        TvCategory(id: 'vide', name: 'Sans chaîne'),
        TvCategory(id: 'gen', name: 'Généralistes'),
      ],
      [channel('tf1', 'gen'), channel('eurosport', 'sport'), channel('m6', 'gen'), channel('mtv', 'Musique')],
    );
    // An empty category is left out; a category the list doesn't name comes last, under its id.
    expect(rows(sections), ['Sport: eurosport', 'Généralistes: tf1, m6', 'Musique: mtv']);
    // The round arrow of a row shows its category.
    expect(sections.map((s) => s.categoryId), ['sport', 'gen', 'Musique']);

    final many = channelCategorySections(const [], [for (var i = 0; i < 40; i++) channel('c$i', 'Sport')]);
    expect(many.single.channels, hasLength(homeChannelLimit));
  });

  test('sorts the channels by theme, in order, from category names without a category list', () {
    // A provider whose categories are their names (no /tv/categories list needed).
    final sections = channelSections(const [], [
      channel('bfm', 'Info'),
      channel('tf1', 'Généralistes'),
      channel('gulli', 'Enfants'),
      channel('eurosport', 'Sport'),
      channel('mtv', 'Musique'),
      channel('m6', 'Généralistes'),
    ]);
    expect(rows(sections), [
      'Chaînes TV généralistes: tf1, m6',
      'Chaînes TV sport: eurosport',
      'Chaînes TV info: bfm',
      'Chaînes TV enfants: gulli',
    ]);
  });

  test("reads a panel's own category names, every matching category feeds the row", () {
    final sections = channelSections(
      const [
        TvCategory(id: '1', name: 'FR | SPORTS'),
        TvCategory(id: '2', name: 'UK Sport'),
        TvCategory(id: '3', name: 'Jeunesse'),
        TvCategory(id: '4', name: 'FR | NEWS'),
        TvCategory(id: '5', name: 'Cinéma'),
      ],
      [channel('a', '1'), channel('b', '2'), channel('c', '3'), channel('d', '4'), channel('e', '5')],
    );
    expect(rows(sections), ['Chaînes TV sport: a, b', 'Chaînes TV info: d', 'Chaînes TV enfants: c']);
  });

  test('a row keeps a few channels only', () {
    final many = [for (var i = 0; i < 40; i++) channel('s$i', 'Sport')];
    expect(channelSections(const [], many).single.channels, hasLength(homeChannelLimit));
  });

  test('no category matches: one « Chaînes TV » row, so the home page still shows channels', () {
    final sections = channelSections(const [], [channel('a', 'Divers'), channel('b', 'Autres')]);
    expect(rows(sections), ['Chaînes TV: a, b']);
    expect(channelSections(const [], const []), isEmpty);
  });
}
