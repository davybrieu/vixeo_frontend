import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../search/search_filters.dart';
import 'network.dart';
import 'widgets.dart';

/// Chooses a movie or a TV show (a list, « Mes 4 favoris »): a search, the popular titles before
/// any text. Null when the page is closed. [chosen] (`movie:550`) are marked « Ajouté ».
Future<MediaItem?> pickTitle(BuildContext context, {String title = 'Ajouter un titre', Set<String> chosen = const {}}) =>
    Navigator.of(context, rootNavigator: true).push<MediaItem>(
      MaterialPageRoute(builder: (_) => _TitlePickerScreen(title: title, chosen: chosen)),
    );

class _TitlePickerScreen extends ConsumerStatefulWidget {
  const _TitlePickerScreen({required this.title, required this.chosen});

  final String title;
  final Set<String> chosen;

  @override
  ConsumerState<_TitlePickerScreen> createState() => _TitlePickerScreenState();
}

class _TitlePickerScreenState extends ConsumerState<_TitlePickerScreen> {
  final _search = TextEditingController();
  Timer? _typing;
  String _query = '';

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _clear() {
    _typing?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final List<MediaItem> titles;
    final AsyncValue<Object?> state;
    if (_query.length >= 2) {
      final results = ref.watch(searchProvider((_query, const SearchFilters())));
      state = results;
      final value = results.value;
      titles = value == null
          ? const []
          : [
              // Movies and TV shows mixed, the best results of each first.
              for (var i = 0; i < value.movies.length || i < value.shows.length; i++) ...[
                if (i < value.movies.length) value.movies[i],
                if (i < value.shows.length) value.shows[i],
              ],
            ];
    } else {
      final home = ref.watch(homeProvider);
      state = home;
      final seen = <String>{};
      titles = [
        for (final section in home.value?.sections ?? const <Section>[])
          for (final item in section.items)
            if (seen.add(itemIdOf(item.type, item.id))) item,
      ].take(40).toList();
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VxPageHeader(
              title: widget.title,
              back: true,
              search: VxSearchField(
                controller: _search,
                autofocus: !DeviceInfo.isTv,
                fontSize: layout.size(16, tv: 24),
                hintText: 'Rechercher un film, une série…',
                onChanged: _onChanged,
                onClear: _clear,
              ),
            ),
            Expanded(
              child: ListView(
                padding: pageContentPadding(context),
                children: [
                  if (_query.length < 2 && titles.isNotEmpty)
                    SectionHeader('Populaires', padding: EdgeInsets.only(bottom: layout.titleGap)),
                  if (titles.isEmpty)
                    state.isLoading
                        ? const NetworkLoading()
                        : state.hasError
                        ? NetworkLoading(error: state.error)
                        : const EmptyState(icon: Icons.search_off_rounded, title: 'Aucun résultat'),
                  for (final (i, item) in titles.indexed)
                    Padding(
                      padding: EdgeInsets.only(bottom: layout.space(VxSpace.xxs)),
                      child: _TitleChoice(
                        item: item,
                        chosen: widget.chosen.contains(itemIdOf(item.type, item.id)),
                        autofocus: i == 0 && DeviceInfo.isTv,
                        onPressed: () => Navigator.of(context).pop(item),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleChoice extends StatelessWidget {
  const _TitleChoice({required this.item, required this.chosen, required this.onPressed, this.autofocus = false});

  final MediaItem item;
  final bool chosen;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final kind = item.type == MediaType.movie ? 'Film' : 'Série';
    final detail = [kind, if (item.year != null) '${item.year}'].join(' · ');
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: '${item.title}, $detail${chosen ? ', déjà ajouté' : ''}',
      onPressed: chosen ? null : onPressed,
      child: Opacity(
        opacity: chosen ? 0.5 : 1,
        child: Padding(
          padding: EdgeInsets.all(layout.space(VxSpace.xs)),
          child: Row(
            children: [
              PosterThumb(url: item.posterUrl, width: layout.size(44, tv: 72), seed: item.id),
              SizedBox(width: layout.space(VxSpace.s)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                    ),
                    Text(detail, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                  ],
                ),
              ),
              Icon(
                chosen ? Icons.check_rounded : Icons.add_rounded,
                size: layout.size(22, tv: 34),
                color: chosen ? VxColors.accent : VxColors.textSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
