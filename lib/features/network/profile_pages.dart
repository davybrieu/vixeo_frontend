import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';
import '../tmdb/tmdb.dart' show formatScore;
import 'actions.dart' show newListLocation;
import 'network.dart';
import 'profile_sections.dart';
import 'share_image.dart';
import 'widgets.dart';

// The whole pages behind the « Listes » and « Journal » tabs of a profile: every list, the whole
// diary, the « Bilan de l'année ». [username] null = the active profile.

/// The active profile's username, or [username].
String? _who(WidgetRef ref, String? username) => username ?? ref.watch(sessionProvider).profile?.username;

/// Every list of a profile (`/profil/listes`, `/membre/:username/listes`).
class ProfileListsScreen extends ConsumerWidget {
  const ProfileListsScreen({super.key, this.username});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final mine = username == null;
    final who = _who(ref, username) ?? '';
    final lists = mine ? ref.watch(myListsProvider(null)) : ref.watch(memberListsProvider(who));
    final value = lists.value;
    void reload() {
      if (mine) {
        ref.invalidate(myListsProvider);
      } else {
        ref.invalidate(memberListsProvider(who));
      }
    }

    return NetworkPage(
      title: mine ? 'Mes listes' : 'Listes de @$who',
      actions: [
        if (mine)
          VxIconAction(
            icon: Icons.add_rounded,
            label: 'Nouvelle liste',
            dense: true,
            onPressed: () => context.push(newListLocation()),
          ),
      ],
      onRefresh: () async {
        reload();
      },
      children: [
        if (value == null)
          NetworkLoading(
            error: lists.error,
            onRetry: reload,
          )
        else if (value.isEmpty)
          const EmptyState(icon: Icons.playlist_play_rounded, title: 'Aucune liste')
        else
          for (final (i, list) in value.indexed) ...[
            if (i > 0) SizedBox(height: layout.listGap),
            ListPost(list: list, showAuthor: false),
          ],
      ],
    );
  }
}

/// The whole diary of a profile (`/profil/journal`, `/membre/:username/journal`), by month. Mine:
/// a long press (or the menu key) removes an entry.
class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key, this.username});

  final String? username;

  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  final _scroll = ScrollController();
  final _entries = <DiaryEntry>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  String? get _username => widget.username ?? ref.read(sessionProvider).profile?.username;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final username = _username;
    if (username == null) return;
    if (reset) {
      _entries.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    }
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(networkRepositoryProvider).diary(username, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _page++;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(DiaryEntry entry) async {
    final profileId = ref.read(sessionProvider).profile?.id;
    if (profileId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showVxConfirm(
      context,
      title: 'Retirer du journal ?',
      message: '${entry.title.title}${entry.episodeLabel == null ? '' : ', ${entry.episodeLabel}'} ne sera plus dans votre journal (il reste marqué comme vu).',
      confirm: 'Retirer',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(networkRepositoryProvider).deleteDiaryEntry(profileId, entry.id);
      if (!mounted) return;
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
      ref.invalidate(diaryProvider);
      showVxSnackOn(messenger, 'Retiré du journal', icon: Icons.delete_outline_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final mine = widget.username == null;
    final children = <Widget>[];
    String? month;
    for (final entry in _entries) {
      final label = '${frenchMonths[entry.watchedAt.month - 1]} ${entry.watchedAt.year}';
      if (label != month) {
        month = label;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : layout.sectionGap, bottom: layout.space(VxSpace.xs)),
            child: Text(
              '${label[0].toUpperCase()}${label.substring(1)}',
              style: VxText.title(layout.sectionTitleSize),
            ),
          ),
        );
      }
      children.add(DiaryRow(entry: entry, onLongPress: mine ? () => _remove(entry) : null));
    }
    return NetworkPage(
      title: mine ? 'Mon journal' : 'Journal de @${widget.username}',
      controller: _scroll,
      onRefresh: () => _load(reset: true),
      actions: [
        VxIconAction(
          icon: Icons.insights_rounded,
          label: mine ? 'Mon année' : 'Son année',
          dense: true,
          onPressed: () => context.push(profileSectionLocation(widget.username, 'bilan')),
        ),
      ],
      children: [
        if (mine && _entries.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: layout.space(VxSpace.m)),
            child: Text(
              'Appui long sur une ligne pour la retirer du journal.',
              style: VxText.body(layout.captionSize, color: VxColors.textMuted),
            ),
          ),
        if (_entries.isEmpty && !_loading)
          _error != null
              ? ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
              : const EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'Journal vide',
                  message: 'Chaque film ou épisode marqué comme vu s’inscrit ici.',
                ),
        ...children,
        if (_loading) const NetworkLoading(),
      ],
    );
  }
}

/// « Bilan de l'année » (`/profil/bilan?annee=2026`, `/membre/:username/bilan`): titles watched,
/// hours, months, genres, best rated, the most watched show. Mine: « Partager mon année » (an
/// image, see share_image.dart).
class YearStatsScreen extends ConsumerStatefulWidget {
  const YearStatsScreen({super.key, this.username, this.year});

  final String? username;
  final int? year;

  @override
  ConsumerState<YearStatsScreen> createState() => _YearStatsScreenState();
}

class _YearStatsScreenState extends ConsumerState<YearStatsScreen> {
  late int _year = widget.year ?? DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final mine = widget.username == null;
    final who = _who(ref, widget.username);
    final name = mine ? ref.watch(sessionProvider).profile?.name ?? '' : '@${widget.username}';
    final now = DateTime.now().year;
    final stats = who == null ? null : ref.watch(yearStatsProvider((username: who, year: _year)));
    final value = stats?.value;
    return NetworkPage(
      title: mine ? 'Mon année' : 'Année de @${widget.username}',
      actions: [
        if (mine && value != null && value.entriesCount > 0 && !DeviceInfo.isTv)
          VxIconAction(
            icon: Icons.ios_share_rounded,
            label: 'Partager mon année',
            dense: true,
            onPressed: () => openStory(context, StoryContent.year(value, name)),
          ),
      ],
      children: [
        Row(
          children: [
            VxIconAction(
              icon: Icons.chevron_left_rounded,
              label: 'Année ${_year - 1}',
              dense: true,
              onPressed: _year > 2000 ? () => setState(() => _year--) : null,
            ),
            Expanded(
              child: Text(
                '$_year',
                textAlign: TextAlign.center,
                style: VxText.title(layout.size(28, tv: 48)),
              ),
            ),
            VxIconAction(
              icon: Icons.chevron_right_rounded,
              label: 'Année ${_year + 1}',
              dense: true,
              onPressed: _year < now ? () => setState(() => _year++) : null,
            ),
          ],
        ),
        SizedBox(height: layout.sectionGap),
        if (stats == null)
          const EmptyState(icon: Icons.person_off_outlined, title: 'Choisissez un pseudo pour avoir un bilan')
        else if (value == null)
          NetworkLoading(
            error: stats.error,
            onRetry: () => ref.invalidate(yearStatsProvider((username: who!, year: _year))),
          )
        else if (value.entriesCount == 0)
          EmptyState(
            icon: Icons.insights_rounded,
            title: 'Rien en $_year',
            message: mine ? 'Les films et épisodes marqués comme vus cette année feront votre bilan.' : null,
          )
        else
          _YearStatsBody(stats: value),
      ],
    );
  }
}

class _YearStatsBody extends StatelessWidget {
  const _YearStatsBody({required this.stats});

  final YearStats stats;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final numbers = <(String, String)>[
      ('${stats.moviesCount}', stats.moviesCount > 1 ? 'films' : 'film'),
      ('${stats.episodesCount}', stats.episodesCount > 1 ? 'épisodes' : 'épisode'),
      ('${stats.showsCount}', stats.showsCount > 1 ? 'séries' : 'série'),
      ('${stats.hours}', stats.hours > 1 ? 'heures' : 'heure'),
      if (stats.averageRating != null) (formatScore(stats.averageRating!), 'note moyenne'),
      if (stats.rewatchesCount > 0) ('${stats.rewatchesCount}', stats.rewatchesCount > 1 ? 'revus' : 'revu'),
    ];
    final busiest = stats.months.isEmpty ? 0 : stats.months.reduce((a, b) => a > b ? a : b);
    final topGenre = stats.genres.isEmpty ? 1 : stats.genres.first.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: layout.cardGap,
          runSpacing: layout.cardGap,
          children: [
            for (final (value, label) in numbers)
              SizedBox(
                width: layout.size(104, tv: 200),
                child: VxCard(
                  padding: EdgeInsets.all(layout.space(VxSpace.s)),
                  child: Column(
                    children: [
                      Text(value, style: VxText.title(layout.size(26, tv: 44), color: VxColors.accent)),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (busiest > 0) ...[
          SizedBox(height: layout.sectionGap),
          Text('Mois par mois', style: VxText.title(layout.sectionTitleSize)),
          SizedBox(height: layout.titleGap),
          SizedBox(
            height: layout.size(120, tv: 200),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, count) in stats.months.indexed)
                  Expanded(
                    child: Semantics(
                      label: '${frenchMonths[i]} : $count',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: count == 0 ? 0.02 : count / busiest,
                              child: Container(
                                margin: EdgeInsets.symmetric(horizontal: layout.size(3, tv: 6)),
                                decoration: BoxDecoration(
                                  color: count == 0 ? VxColors.line : VxColors.accent,
                                  borderRadius: BorderRadius.circular(layout.size(4, tv: 6)),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: layout.space(VxSpace.xxs)),
                          Text(
                            frenchMonths[i].substring(0, 1).toUpperCase(),
                            style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (stats.genres.isNotEmpty) ...[
          SizedBox(height: layout.sectionGap),
          Text('Genres préférés', style: VxText.title(layout.sectionTitleSize)),
          SizedBox(height: layout.titleGap),
          for (final genre in stats.genres.take(5))
            Padding(
              padding: EdgeInsets.only(bottom: layout.space(VxSpace.xs)),
              child: Row(
                children: [
                  SizedBox(
                    width: layout.size(120, tv: 220),
                    child: Text(genre.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: VxText.body(layout.bodySize)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(layout.size(4, tv: 6)),
                      child: LinearProgressIndicator(
                        value: genre.count / topGenre,
                        minHeight: layout.size(10, tv: 16),
                        color: VxColors.accent,
                        backgroundColor: VxColors.line,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: layout.size(40, tv: 64),
                    child: Text(
                      '${genre.count}',
                      textAlign: TextAlign.end,
                      style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (stats.bestRated.isNotEmpty) ...[
          SizedBox(height: layout.sectionGap),
          Text('Mieux notés', style: VxText.title(layout.sectionTitleSize)),
          SizedBox(height: layout.titleGap),
          NumberedPosters(titles: [for (final best in stats.bestRated) best.title], numbered: true),
        ],
        if (stats.topShow case final show?) ...[
          SizedBox(height: layout.sectionGap),
          Text('Série la plus regardée', style: VxText.title(layout.sectionTitleSize)),
          SizedBox(height: layout.titleGap),
          TitleBanner(
            title: show,
            subtitle: '${stats.topShowEntries} ${stats.topShowEntries > 1 ? 'épisodes vus' : 'épisode vu'}',
          ),
        ],
        SizedBox(height: layout.sectionGap),
        Text(
          'Calculé d’après le journal : les titres marqués comme vus pendant l’année.',
          style: VxText.body(layout.captionSize, color: VxColors.textMuted),
        ),
      ],
    );
  }
}
