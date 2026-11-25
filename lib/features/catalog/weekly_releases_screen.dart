import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'weekly_releases.dart';
import '../../core/widgets/common.dart';

/// Weekly editorial calendar of worldwide movie, TV and episode releases.
class WeeklyReleasesScreen extends ConsumerStatefulWidget {
  const WeeklyReleasesScreen({super.key});

  @override
  ConsumerState<WeeklyReleasesScreen> createState() => _WeeklyReleasesScreenState();
}

class _WeeklyReleasesScreenState extends ConsumerState<WeeklyReleasesScreen> {
  static const _filters = [
    ('all', 'Tout'),
    ('movie', 'Films'),
    ('tv', 'Séries'),
    ('episode', 'Épisodes'),
  ];

  late DateTime _weekStart;
  String _type = 'all';
  DateTime? _selectedDay;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {};

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(DateTime.now());
    _selectedDay = DateTime.now();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static DateTime _monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _month(DateTime date) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return months[date.month - 1];
  }

  static String _weekday(DateTime date) {
    const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    return days[date.weekday - 1];
  }

  static String _dateLabel(DateTime date) =>
      '${_weekday(date)[0].toUpperCase()}${_weekday(date).substring(1)} ${date.day} ${_month(date)}';

  String get _period {
    final end = _weekStart.add(const Duration(days: 6));
    if (_weekStart.year != end.year) {
      return '${_weekStart.day} ${_month(_weekStart)} ${_weekStart.year} – ${end.day} ${_month(end)} ${end.year}';
    }
    if (_weekStart.month != end.month) {
      return '${_weekStart.day} ${_month(_weekStart)} – ${end.day} ${_month(end)} ${end.year}';
    }
    return '${_weekStart.day} – ${end.day} ${_month(end)} ${end.year}';
  }

  void _changeWeek(int amount) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * amount));
      _selectedDay = _weekStart;
    });
  }

  void _goToday() {
    final today = DateTime.now();
    setState(() {
      _weekStart = _monday(today);
      _selectedDay = today;
    });
    _scrollTo(today);
  }

  void _scrollTo(DateTime day) {
    final key = _dayKeys[_key(day)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.02,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final end = _weekStart.add(const Duration(days: 6));
    final range = (from: _weekStart, to: end, type: _type);
    final releases = ref.watch(weeklyReleasesProvider(range));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sorties de la semaine', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(_period, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Semaine précédente',
                    onPressed: () => _changeWeek(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    tooltip: 'Semaine suivante',
                    onPressed: () => _changeWeek(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  TextButton(onPressed: _goToday, child: const Text("Aujourd'hui")),
                ],
              ),
            ),
            SizedBox(
              height: 66,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = _weekStart.add(Duration(days: index));
                  final selected = _selectedDay != null && _key(_selectedDay!) == _key(day);
                  final today = _key(DateTime.now()) == _key(day);
                  return ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _selectedDay = day);
                      _scrollTo(day);
                    },
                    label: SizedBox(
                      width: 48,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_weekday(day).substring(0, 3), style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 2),
                          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (today) Text('Auj.', style: TextStyle(fontSize: 9, color: colors.primary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final filter in _filters)
                    ChoiceChip(
                      label: Text(filter.$2),
                      selected: _type == filter.$1,
                      onSelected: (_) => setState(() => _type = filter.$1),
                    ),
                ],
              ),
            ),
            Expanded(
              child: releases.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorPanel(
                  error: error,
                  onRetry: () => ref.invalidate(weeklyReleasesProvider(range)),
                ),
                data: (items) => RefreshIndicator(
                  onRefresh: () async { await ref.refresh(weeklyReleasesProvider(range).future); },
                  child: _calendar(items),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendar(List<WeeklyRelease> items) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.event_busy_rounded, size: 48),
          SizedBox(height: 16),
          Text('Aucune sortie annoncée sur cette période.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('Les dates dépendent des informations publiées par TMDB et peuvent évoluer.', textAlign: TextAlign.center),
        ],
      );
    }

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        for (var index = 0; index < 7; index++)
          _daySection(_weekStart.add(Duration(days: index)), items),
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            'Calendrier mondial basé sur les dates disponibles dans TMDB. Les épisodes et sorties par pays ne sont pas toujours renseignés.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _daySection(DateTime day, List<WeeklyRelease> all) {
    final dayKey = _key(day);
    final items = all.where((item) => item.releaseDate != null && _key(item.releaseDate!) == dayKey).toList();
    final today = dayKey == _key(DateTime.now());

    return Container(
      key: _dayKeys.putIfAbsent(dayKey, GlobalKey.new),
      margin: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLabel(day),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (today)
                  const Text('AUJOURD’HUI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${items.length}', style: Theme.of(context).textTheme.labelMedium),
                  ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('Aucune sortie annoncée', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            )
          else
            for (final item in items) _releaseCard(item),
        ],
      ),
    );
  }

  Widget _releaseCard(WeeklyRelease item) {
    final colors = Theme.of(context).colorScheme;
    final subtitle = item.isEpisode
        ? '${item.episodeCode} · ${item.episodeName ?? 'Épisode'}'
        : item.releaseType ?? item.categoryLabel;
    final extra = [
      if (item.countryCode != null && item.countryCode!.isNotEmpty) item.countryCode!,
      if (item.isEpisode) 'Épisode',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.tmdbId > 0 ? () => context.push('/titre/${item.navigationType}/${item.tmdbId}') : null,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 76,
                  height: 112,
                  child: item.posterUrl == null
                      ? Container(color: colors.surfaceContainerHighest, child: const Icon(Icons.movie_outlined, size: 30))
                      : Image.network(
                          item.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: colors.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined, size: 30),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.categoryLabel.toUpperCase(), style: TextStyle(color: colors.primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
                      const SizedBox(height: 5),
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      if (extra.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(extra, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                      if (item.overview != null && item.overview!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(item.overview!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
