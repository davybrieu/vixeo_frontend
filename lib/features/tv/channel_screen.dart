import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import 'channel_search.dart';
import 'models.dart';
import 'tv_repository.dart';

/// Path of a channel page.
String channelPath(String id) => '/chaine/${Uri.encodeComponent(id)}';

/// Opens the channel page (like a movie or TV show page), with the channel already known.
void openChannel(BuildContext context, TvChannel channel) => context.push(channelPath(channel.id), extra: channel);

/// "14:05", or "Demain 08:30" / "mer. 08:30" for another day.
String programmeTime(DateTime time, DateTime now) {
  final hm = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = day.difference(today).inDays;
  if (days == 0) return hm;
  if (days == 1) return 'Demain $hm';
  const names = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  return '${names[time.weekday - 1]} $hm';
}

/// A live channel's page: its image, name and category, « Regarder », what is on now
/// and the programme guide (EPG). Opened from every channel tile; « Regarder » plays it.
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({super.key, required this.id, this.initial});

  final String id;

  /// The channel of the tile pressed: shown at once, before the API answers (and on its own if a
  /// link opens the page directly, once loaded).
  final TvChannel? initial;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // What is on, and its progress, follow the clock.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final guide = ref.read(tvGuideProvider(widget.id)).value;
      // The last programme of the guide is over: ask for the next ones.
      if (guide != null && guide.programmes.isNotEmpty && !guide.programmes.last.end.isAfter(_now)) {
        ref.invalidate(tvGuideProvider(widget.id));
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(tvChannelProvider(widget.id));
    final channel = loaded.value ?? widget.initial;

    if (channel == null) {
      return Scaffold(
        body: AsyncView(
          value: loaded,
          onRetry: () => ref.invalidate(tvChannelProvider(widget.id)),
          data: (_) => const SizedBox.shrink(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
        floatingActionButton: const _BackButton(),
      );
    }

    final guide = ref.watch(tvGuideProvider(widget.id));
    final programmes = (guide.value?.programmes ?? const <TvProgramme>[]).where((p) => p.end.isAfter(_now)).toList();
    final current = programmes.where((p) => p.isOnAt(_now)).firstOrNull;
    final categories = ref.watch(tvCategoriesProvider).value ?? const <TvCategory>[];
    final category =
        categories.where((c) => c.id == channel.categoryId).firstOrNull?.name ??
        // Some providers name their categories by their id ("Sport").
        (int.tryParse(channel.categoryId) == null && channel.categoryId.isNotEmpty ? channel.categoryId : null);

    return Scaffold(
      body: _Page(
        channel: channel,
        category: category,
        current: current,
        background: current?.image ?? programmes.where((p) => p.image != null).firstOrNull?.image,
        guide: _Guide(
          value: guide,
          programmes: programmes,
          now: _now,
          onRetry: () => ref.invalidate(tvGuideProvider(widget.id)),
        ),
        now: _now,
      ),
    );
  }
}

class _Page extends ConsumerWidget {
  const _Page({
    required this.channel,
    required this.category,
    required this.current,
    required this.background,
    required this.guide,
    required this.now,
  });

  final TvChannel channel;
  final String? category;
  final TvProgramme? current;
  final String? background;
  final Widget guide;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final large = layout.isLarge;
    final heroHeight = large ? layout.tv(560) : 300.0;
    final logoSize = large ? layout.tv(180) : 96.0;

    return Stack(
      children: [
        // The programme on now as the backdrop, fading into the page.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (background != null) NetImage(url: background, seed: channel.id.hashCode),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: background == null
                        ? const [VxColors.surface, VxColors.background]
                        : const [Color(0x73070A08), Color(0x40070A08), VxColors.background],
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView(
          padding: EdgeInsets.only(bottom: pageBottomPadding(context)),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(layout.gutter, large ? layout.tv(48) : 8, layout.gutter, 0),
                child: const Align(alignment: Alignment.centerLeft, child: _BackButton(inline: true)),
              ),
            ),
            SizedBox(height: heroHeight - logoSize - (large ? layout.tv(220) : 150)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChannelLogo(channel: channel, size: logoSize),
                  SizedBox(height: layout.titleGap),
                  Text(channel.name, style: VxText.title(large ? layout.tv(56) : 28, weight: FontWeight.w800)),
                  SizedBox(height: large ? layout.tv(12) : 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const _LiveChip(),
                      if (category != null)
                        Text(category!, style: VxText.body(large ? layout.tv(24) : 14, color: VxColors.textSoft)),
                    ],
                  ),
                  SizedBox(height: layout.introGap),
                  Row(
                    children: [
                      VxButton(
                        label: 'Regarder',
                        icon: Icons.play_arrow_rounded,
                        autofocus: true,
                        onPressed: () => playLiveChannel(context, ref, channel),
                      ),
                    ],
                  ),
                  if (current != null) ...[
                    SizedBox(height: layout.sectionGap),
                    _NowCard(programme: current!, now: now),
                  ],
                  SizedBox(height: layout.sectionGap),
                  Text('Programme', style: VxText.title(large ? layout.tv(32) : 20)),
                  SizedBox(height: layout.titleGap),
                  guide,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The channel's logo on a light tile (logos are drawn for a light background), or an icon.
class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel, required this.size});

  final TvChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = channel.logo;
    return ExcludeSemantics(
      child: Container(
        width: size * 1.6,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: logo == null ? VxColors.surfaceHigh : VxColors.text.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(size * 0.16),
        ),
        child: logo == null
            ? Icon(Icons.live_tv_rounded, size: size * 0.5, color: VxColors.textSecondary)
            : Image.network(
                logo,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(Icons.live_tv_rounded, size: size * 0.5, color: VxColors.background),
              ),
      ),
    );
  }
}

/// « EN DIRECT » with a red dot.
class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
      decoration: BoxDecoration(color: VxColors.surfaceHigh, borderRadius: BorderRadius.circular(6 * s)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7 * s,
            height: 7 * s,
            decoration: const BoxDecoration(color: VxColors.dangerText, shape: BoxShape.circle),
          ),
          SizedBox(width: 5 * s),
          Text('EN DIRECT', style: VxText.body(11 * s, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// « En ce moment »: the programme on now, its hours and progress.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.programme, required this.now});

  final TvProgramme programme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final large = layout.isLarge;
    final left = programme.end.difference(now).inMinutes;
    return VxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En ce moment',
            style: VxText.body(large ? layout.tv(22) : 13, color: VxColors.accent, weight: FontWeight.w600),
          ),
          SizedBox(height: large ? layout.tv(8) : 4),
          Text(programme.title, style: VxText.title(large ? layout.tv(34) : 20)),
          if (programme.subtitle != null)
            Text(programme.subtitle!, style: VxText.body(large ? layout.tv(24) : 14, color: VxColors.textSoft)),
          SizedBox(height: large ? layout.tv(14) : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: programme.progressAt(now),
              minHeight: large ? layout.tv(8) : 4,
              color: VxColors.accent,
              backgroundColor: VxColors.line,
            ),
          ),
          SizedBox(height: large ? layout.tv(8) : 6),
          Text(
            '${programmeTime(programme.start, now)} – ${programmeTime(programme.end, now)} · '
            '${left <= 1 ? 'se termine' : 'encore $left min'}',
            style: VxText.body(large ? layout.tv(22) : 13, color: VxColors.textMuted),
          ),
          if (programme.description != null) ...[
            SizedBox(height: large ? layout.tv(14) : 10),
            Text(
              programme.description!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(large ? layout.tv(24) : 14, color: VxColors.textSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// The programme list: the one on now, then the next ones. A press shows the whole description.
class _Guide extends StatelessWidget {
  const _Guide({required this.value, required this.programmes, required this.now, required this.onRetry});

  final AsyncValue<TvGuide> value;
  final List<TvProgramme> programmes;
  final DateTime now;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    String? note;
    if (value.hasError && !value.hasValue) {
      return Align(
        alignment: Alignment.centerLeft,
        child: VxButton(
          label: 'Réessayer',
          kind: VxButtonKind.secondary,
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
      );
    } else if (!value.hasValue) {
      note = 'Chargement du programme…';
    } else if (!value.value!.available) {
      note = 'Le programme n’est pas disponible pour le moment.';
    } else if (programmes.isEmpty) {
      note = 'Aucun programme connu pour cette chaîne.';
    }
    if (note != null) {
      return Text(note, style: VxText.body(layout.size(15, tv: 24), color: VxColors.textMuted));
    }

    return FocusTraversalGroup(
      child: Column(
        children: [
          for (final (i, p) in programmes.indexed) ...[
            if (i > 0) SizedBox(height: layout.listGap),
            _ProgrammeRow(programme: p, now: now),
          ],
        ],
      ),
    );
  }
}

class _ProgrammeRow extends StatelessWidget {
  const _ProgrammeRow({required this.programme, required this.now});

  final TvProgramme programme;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final large = layout.isLarge;
    final on = programme.isOnAt(now);
    final time = programmeTime(programme.start, now);
    final details = [?programme.subtitle, ?programme.category].join(' · ');

    return VxFocusable(
      borderRadius: 12,
      semanticLabel: [time, programme.title, if (on) 'en cours', if (details.isNotEmpty) details].join(', '),
      onPressed: () => _showProgramme(context, programme, now),
      child: Container(
        padding: EdgeInsets.all(large ? layout.tv(20) : 12),
        decoration: BoxDecoration(
          color: on ? VxColors.accent.withValues(alpha: 0.10) : VxColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? VxColors.accent.withValues(alpha: 0.4) : VxColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: large ? layout.tv(150) : 84,
              child: ExcludeSemantics(
                child: Text(
                  time,
                  style: VxText.body(
                    large ? layout.tv(24) : 14,
                    weight: FontWeight.w600,
                    color: on ? VxColors.accent : VxColors.textSoft,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      programme.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(large ? layout.tv(26) : 15, weight: FontWeight.w600),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(large ? layout.tv(22) : 13, color: VxColors.textMuted),
                      ),
                  ],
                ),
              ),
            ),
            if (on)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'En cours',
                  style: VxText.body(large ? layout.tv(20) : 12, color: VxColors.accent, weight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The whole programme: hours, title, details, description.
Future<void> _showProgramme(BuildContext context, TvProgramme p, DateTime now) {
  final details = [?p.subtitle, ?p.category].join(' · ');
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: VxColors.surface,
      title: Text(p.title, style: VxText.title(20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${programmeTime(p.start, now)} – ${programmeTime(p.end, now)}',
              style: VxText.body(14, color: VxColors.textMuted),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(details, style: VxText.body(14, color: VxColors.textSoft)),
            ],
            const SizedBox(height: 12),
            Text(p.description ?? 'Pas de description.', style: VxText.body(15, color: VxColors.textSoft)),
          ],
        ),
      ),
      actions: [VxButton(label: 'Fermer', autofocus: true, onPressed: () => Navigator.of(context).pop())],
    ),
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({this.inline = false});

  /// In the page (not floating over an error).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final button = VxFocusable(
      borderRadius: 22,
      semanticLabel: 'Retour',
      onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: Color(0x99070A08), shape: BoxShape.circle),
        child: const Icon(Icons.arrow_back_rounded, color: VxColors.text),
      ),
    );
    return inline
        ? button
        : SafeArea(
            child: Padding(padding: const EdgeInsets.all(12), child: button),
          );
  }
}
