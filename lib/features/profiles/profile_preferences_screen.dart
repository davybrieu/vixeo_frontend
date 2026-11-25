import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/choice.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'languages.dart';
import 'no_spoiler.dart';
import 'profile_settings_screen.dart';
import 'settings_rows.dart';

/// General profile preferences: appearance, no-spoil, languages, automatic skips and the rating
/// proposed at the end of a movie or an episode. Values are saved on the profile and synchronized
/// between its devices.
class ProfilePreferencesScreen extends ConsumerWidget {
  const ProfilePreferencesScreen({super.key, this.setting});

  static const location = '/profil/parametres';

  /// « Désactiver dans les paramètres » of the rating proposed after watching: this page, with
  /// the focus on « Proposer de noter à la fin ».
  static const rateAfterWatchingLocation = '$location?reglage=noter';

  /// The setting to put forward (`?reglage=noter`): it has the focus on arrival.
  final String? setting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final s = uiScale(context);
    final noSpoiler = ref.watch(noSpoilerProvider);
    if (profile == null) return const SizedBox();

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
          'Personnalisez l’affichage et la lecture de votre profil. Ces préférences sont synchronisées entre vos appareils.',
        ),
        SettingsSection(
          'No spoil',
          scale: s,
          children: [
            SettingsSwitchRow(
              label: 'Activer No spoil',
              autofocus: setting != 'noter',
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
          'Après la lecture',
          scale: s,
          children: [
            SettingsSwitchRow(
              label: 'Proposer de noter à la fin',
              detail: 'À la fin d’un film ou d’un épisode, Vixeo propose de le noter et d’écrire un avis.',
              value: profile.rateAfterWatching,
              autofocus: setting == 'noter',
              onChanged: (value) => saveProfile(
                context,
                {'rate_after_watching': value},
                done: value ? 'Note proposée à la fin de la lecture' : 'Note plus proposée à la fin de la lecture',
                icon: Icons.star_outline_rounded,
              ),
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
