import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import 'rating_view.dart';
import 'ratings.dart';

/// The rating of the title page ([rating], the profile's site): a press shows every site's rating
/// ([showAllRatings]). A small arrow says it opens something.
class RatingButton extends StatelessWidget {
  const RatingButton({
    super.key,
    required this.rating,
    required this.title,
    required this.name,
    required this.tmdb,
    this.fontSize = 14,
  });

  final ShownRating rating;
  final TitleRef title;

  /// The title's name, written under « Notes ».
  final String name;

  /// TMDb's average, given with the title.
  final double tmdb;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final source = rating.source!;
    final value = rating.value!;
    return VxFocusable(
      borderRadius: fontSize * 0.5,
      semanticLabel: 'Note ${source.label} : ${source.spoken(value)}. Voir toutes les notes',
      onPressed: () => showAllRatings(context, title: title, name: name, tmdb: tmdb),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RatingLabel(source: source, value: value, fontSize: fontSize),
            SizedBox(width: fontSize * 0.1),
            Icon(Icons.chevron_right_rounded, size: fontSize * 1.3, color: VxColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// « Notes »: every site that rates [title], in the order of the « Source des notes » setting,
/// the profile's one marked. A sheet on a phone (above the tab bar), a window elsewhere (with
/// « Fermer », focused for the remote).
Future<void> showAllRatings(
  BuildContext context, {
  required TitleRef title,
  required String name,
  required double tmdb,
}) {
  final layout = Layout.of(context);
  final content = _AllRatings(title: title, name: name, tmdb: tmdb);
  if (layout.isPhone) {
    return showModalBottomSheet<void>(
      // Above the phone's tab bar, drawn over the pages' navigator (AppShell).
      useRootNavigator: true,
      context: context,
      backgroundColor: VxColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
        child: content,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: VxColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layout.isLarge ? layout.tv(620) : 480,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
        ),
        child: content,
      ),
    ),
  );
}

class _AllRatings extends ConsumerWidget {
  const _AllRatings({required this.title, required this.name, required this.tmdb});

  final TitleRef title;
  final String name;
  final double tmdb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final phone = layout.isPhone;
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    final chosen = ref.watch(ratingSourceProvider);
    // Asked even when the profile shows TMDb's rating (then not asked yet).
    final value = ref.watch(titleRatingsProvider(title));
    final ratings = value.value;
    final rows = [
      for (final site in RatingSource.values)
        if ((site == RatingSource.tmdb && tmdb > 0 ? tmdb : ratings?[site]) case final rating?) (site, rating),
    ];

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(24 * s, phone ? 0 : 24 * s, 24 * s, 24 * s),
      children: [
        Text('Notes', style: VxText.title(20 * s)),
        SizedBox(height: 4 * s),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: VxText.body(14 * s, color: VxColors.textSecondary),
        ),
        SizedBox(height: 12 * s),
        if (!value.hasValue)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24 * s),
            child: const Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final (i, (site, rating)) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, color: VxColors.line),
            _RatingRow(site: site, value: rating, chosen: site == chosen, scale: s),
          ],
          // MDBList had nothing (title too recent, service unavailable): TMDb's alone, or none.
          if (ratings == null || ratings.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 12 * s),
              child: Text(
                'Les notes des autres sites ne sont pas disponibles pour le moment.',
                style: VxText.body(14 * s, color: VxColors.textSecondary),
              ),
            ),
        ],
        if (!phone) ...[
          SizedBox(height: 20 * s),
          VxButton(label: 'Fermer', autofocus: true, expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ],
    );
  }
}

/// A site: its logo, its name and its rating on its scale ("8,8 / 10", "79 %").
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.site, required this.value, required this.chosen, required this.scale});

  final RatingSource site;
  final double value;

  /// The profile's site (« Source des notes »).
  final bool chosen;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Semantics(
      container: true,
      label: '${site.label} : ${site.spoken(value)}${chosen ? ', votre source' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12 * s),
        child: Row(
          children: [
            SizedBox(
              width: 104 * s,
              child: Align(alignment: Alignment.centerLeft, child: RatingLogo(site, size: 18 * s)),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(site.label, style: VxText.body(16 * s, weight: FontWeight.w500)),
                  if (chosen) Text('Votre source', style: VxText.body(12 * s, color: VxColors.accent)),
                ],
              ),
            ),
            SizedBox(width: 12 * s),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: site.format(value), style: VxText.title(20 * s)),
                  if (!site.isPercent)
                    TextSpan(
                      text: ' / ${site.scale}',
                      style: VxText.body(13 * s, color: VxColors.textSecondary),
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
