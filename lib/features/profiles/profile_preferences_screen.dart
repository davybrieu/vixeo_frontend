import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'languages.dart';
import 'no_spoiler.dart';
import 'profile_settings_screen.dart';

/// General profile preferences: appearance, no-spoil, languages and automatic skips.
/// Values are saved on the profile and synchronized between its devices.
class ProfilePreferencesScreen extends ConsumerWidget {
  const ProfilePreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final s = uiScale(context);
    final noSpoiler = ref.watch(noSpoilerProvider);
    if (profile == null) return const SizedBox();

    Future<void> pickAppearance() async {
      final choice = await showVxChoice<PosterFormat>(
        context,
        title: 'Format des affiches',
        selected: profile.posterFormat,
        options: const [
          (PosterFormat.portrait, 'Vertical'),
          (PosterFormat.landscape, 'Horizontal'),
        ],
      );
      if (choice == null || !context.mounted || choice.$1 == profile.posterFormat) return;
      await saveProfile(
        context,
        {'poster_format': choice.$1!.name},
        done: 'Affiches au format ${choice.$1!.label.toLowerCase()}',
        icon: Icons.palette_outlined,
      );
    }

    Future<void> pickAudio() async {
      final choice = await showVxChoice<String>(
        context,
        title: 'Langue audio',
        selected: profile.audioLanguage,
        options: [(null, 'Version originale'), for (final e in audioLanguages.entries) (e.key, e.value)],
      );
      if (choice == null || !context.mounted || choice.$1 == profile.audioLanguage) return;
      await saveProfile(
        context,
        {'audio_language': choice.$1},
        done: 'Langue audio : ${audioLanguageLabel(choice.$1).toLowerCase()}',
        icon: Icons.record_voice_over_outlined,
      );
    }

    Future<void> pickSubtitles() async {
      final choice = await showVxChoice<String>(
        context,
        title: 'Sous-titres',
        selected: profile.subtitleLanguage,
        options: [(null, 'Désactivés'), for (final e in subtitleLanguages.entries) (e.key, e.value)],
      );
      if (choice == null || !context.mounted || choice.$1 == profile.subtitleLanguage) return;
      await saveProfile(
        context,
        {'subtitle_language': choice.$1},
        done: choice.$1 == null ? 'Sous-titres désactivés' : 'Sous-titres : ${subtitleLanguageLabel(choice.$1)}',
        icon: Icons.subtitles_outlined,
      );
    }

    Future<void> toggle(String field, bool value, String label) => saveProfile(
      context,
      {field: value},
      done: value ? '$label : passé automatiquement' : '$label : bouton « Passer »',
      icon: Icons.fast_forward_rounded,
    );

    return InfoPage(
      title: 'Paramètres',
      fallback: '/profil',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 4 * s, 12 * s, 20 * s),
          child: Text(
            'Personnalisez l’apparence et la lecture de votre profil. Ces préférences sont synchronisées entre vos appareils.',
            style: VxText.body(14 * s, color: VxColors.textSecondary),
          ),
        ),
        _Heading('Apparence', scale: s),
        _ChoiceRow(
          icon: Icons.palette_outlined,
          label: 'Format des affiches',
          value: profile.posterFormat.label,
          autofocus: true,
          onPressed: pickAppearance,
        ),
        _Heading('No spoil', scale: s),
        _SwitchRow(
          label: 'Activer No spoil',
          detail: 'Masquer les informations et images des épisodes avant leur sélection.',
          value: noSpoiler,
          onChanged: (value) => saveProfile(
            context,
            {'no_spoiler': value},
            done: value ? 'No spoil activé' : 'No spoil désactivé',
            icon: Icons.visibility_off_outlined,
          ),
        ),
        SizedBox(height: 24 * s),
        _Heading('Langues', scale: s),
        _ChoiceRow(
          icon: Icons.record_voice_over_outlined,
          label: 'Langue audio préférée',
          value: audioLanguageLabel(profile.audioLanguage),
          onPressed: pickAudio,
        ),
        _ChoiceRow(
          icon: Icons.subtitles_outlined,
          label: 'Sous-titres',
          value: subtitleLanguageLabel(profile.subtitleLanguage),
          onPressed: pickSubtitles,
        ),
        SizedBox(height: 24 * s),
        _Heading('Passer automatiquement', scale: s),
        SizedBox(height: 8 * s),
        for (final (field, label, detail, value) in _skips(profile))
          _SwitchRow(label: label, detail: detail, value: value, onChanged: (v) => toggle(field, v, label)),
      ],
    );
  }

  static List<(String, String, String, bool)> _skips(Profile p) => [
    ('skip_intro', 'Générique de début', 'Le générique au début d’un film ou d’un épisode.', p.skipIntro),
    ('skip_recap', 'Résumé', 'Le « Précédemment… » au début d’un épisode.', p.skipRecap),
    ('skip_credits', 'Générique de fin', 'Pour une série, l’épisode suivant démarre.', p.skipCredits),
    ('skip_preview', 'Aperçu de la suite', 'Les images de l’épisode suivant, après le générique.', p.skipPreview),
  ];
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 10 * scale),
    child: Text(text, style: VxText.title(18 * scale)),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(12 * scale, 6 * scale, 12 * scale, 0),
    child: Text(text, style: VxText.body(13 * scale, color: VxColors.textMuted)),
  );
}

/// A setting whose value is picked in a list.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: VxFocusable(
        autofocus: autofocus,
        borderRadius: 14 * s,
        focusScale: 1.02,
        semanticLabel: '$label : $value',
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
            decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
            child: Row(
              children: [
                Icon(icon, size: 22 * s, color: VxColors.textSoft),
                SizedBox(width: 14 * s),
                Expanded(
                  child: Text(label, style: VxText.body(15 * s, weight: FontWeight.w600)),
                ),
                Text(
                  value,
                  style: VxText.body(15 * s, color: VxColors.accent, weight: FontWeight.w600),
                ),
                SizedBox(width: 6 * s),
                Icon(Icons.chevron_right_rounded, size: 22 * s, color: VxColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An on / off setting: the whole row is the switch (remote: OK toggles it).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.detail, required this.value, required this.onChanged});

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Semantics(
        toggled: value,
        child: VxFocusable(
          borderRadius: 14 * s,
          focusScale: 1.02,
          semanticLabel: '$label, ${value ? 'passé automatiquement' : 'bouton Passer'}',
          onPressed: () => onChanged(!value),
          child: ExcludeSemantics(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
              decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: VxText.body(15 * s, weight: FontWeight.w600)),
                        SizedBox(height: 2 * s),
                        Text(detail, style: VxText.body(13 * s, color: VxColors.textSecondary)),
                      ],
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  // The row handles taps and the remote: the switch only shows the state.
                  IgnorePointer(
                    child: ExcludeFocus(
                      child: Transform.scale(
                        scale: s,
                        child: Switch(value: value, onChanged: (_) {}, activeThumbColor: VxColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
