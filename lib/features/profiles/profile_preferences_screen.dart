import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/choice.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../ratings/rating_source.dart';
import 'languages.dart';
import 'no_spoiler.dart';
import 'profile_settings_screen.dart';
import 'settings_rows.dart';

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
        options: const [(PosterFormat.portrait, 'Vertical'), (PosterFormat.landscape, 'Horizontal')],
      );
      if (choice == null || !context.mounted || choice.$1 == profile.posterFormat) return;
      await saveProfile(
        context,
        {'poster_format': choice.$1!.name},
        done: 'Affiches au format ${choice.$1!.label.toLowerCase()}',
        icon: Icons.palette_outlined,
      );
    }

    Future<void> pickRatingSource() async {
      final choice = await showVxChoice<RatingSource>(
        context,
        title: 'Source des notes',
        selected: profile.ratingSource,
        options: [for (final source in RatingSource.values) (source, source.label)],
      );
      if (choice == null || choice.$1 == null || !context.mounted || choice.$1 == profile.ratingSource) return;
      await saveProfile(
        context,
        {'rating_source': choice.$1!.name},
        done: 'Notes : ${choice.$1!.label}',
        icon: Icons.star_outline_rounded,
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
        const InfoIntro(
          'Personnalisez l’apparence et la lecture de votre profil. Ces préférences sont synchronisées entre vos appareils.',
        ),
        SettingsSection(
          'Apparence',
          scale: s,
          children: [
            SettingsChoiceRow(
              icon: Icons.palette_outlined,
              label: 'Format des affiches',
              value: profile.posterFormat.label,
              autofocus: true,
              onPressed: pickAppearance,
            ),
            // The site whose rating the titles show (MDBList through the API; IMDb by default).
            SettingsChoiceRow(
              icon: Icons.star_outline_rounded,
              label: 'Source des notes',
              value: profile.ratingSource.label,
              onPressed: pickRatingSource,
            ),
          ],
        ),
        SettingsSection(
          'No spoil',
          scale: s,
          children: [
            SettingsSwitchRow(
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
          ],
        ),
        SettingsSection(
          'Langues',
          scale: s,
          children: [
            SettingsChoiceRow(
              icon: Icons.record_voice_over_outlined,
              label: 'Langue audio préférée',
              value: audioLanguageLabel(profile.audioLanguage),
              onPressed: pickAudio,
            ),
            SettingsChoiceRow(
              icon: Icons.subtitles_outlined,
              label: 'Sous-titres',
              value: subtitleLanguageLabel(profile.subtitleLanguage),
              onPressed: pickSubtitles,
            ),
          ],
        ),
        SettingsSection(
          'Passer automatiquement',
          scale: s,
          last: true,
          children: [
            for (final (field, label, detail, value) in _skips(profile))
              SettingsSwitchRow(
                label: label,
                detail: detail,
                value: value,
                onLabel: 'passé automatiquement',
                offLabel: 'bouton Passer',
                onChanged: (v) => toggle(field, v, label),
              ),
          ],
        ),
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
