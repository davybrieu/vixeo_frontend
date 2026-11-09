import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import 'avatars.dart';
import 'parental_pin.dart';
import 'profiles_screen.dart';

/// Age limits offered for a profile (null = none, or 10 for a kid profile).
const _ageOptions = <int?>[null, 0, 7, 10, 12, 16, 18];

String _ageLabel(int? age, {required bool kid}) => switch (age) {
  null => kid ? 'Par défaut (10 ans)' : 'Aucune limite',
  0 => 'Tous publics',
  final a => '$a ans',
};

/// "Contrôle parental" (`/profil/controle-parental`): each profile's restrictions (kid profile,
/// maximum age, unrated titles). The parental PIN itself is on its own page, "Code PIN"
/// (`/profil/code-pin`). When a PIN is set, it is asked on arrival and sent with every change.
class ParentalControlScreen extends StatelessWidget {
  const ParentalControlScreen({super.key});

  @override
  Widget build(BuildContext context) => ParentalPinPage(
    title: 'Contrôle parental',
    builder: (context, pin, _) => _Restrictions(pin: pin),
  );
}

class _Restrictions extends ConsumerWidget {
  const _Restrictions({required this.pin});

  final String? pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final profiles = ref.watch(profilesProvider);
    final protected = ref.watch(sessionProvider.select((s) => s.user?.parentalControl ?? false));

    return ListView(
      padding: EdgeInsets.fromLTRB(layout.gutter, 8 * s, layout.gutter, 40 * s),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!protected) ...[
                  ParentalCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 24 * s, color: VxColors.textMuted),
                            SizedBox(width: 10 * s),
                            Expanded(child: Text('Aucun code PIN parental', style: VxText.title(18 * s))),
                          ],
                        ),
                        SizedBox(height: 10 * s),
                        Text(
                          'N’importe qui peut modifier ces restrictions. Définissez un code pour les protéger.',
                          style: VxText.body(14 * s, color: VxColors.textSecondary),
                        ),
                        SizedBox(height: 16 * s),
                        VxButton(
                          label: 'Définir un code PIN',
                          icon: Icons.password_rounded,
                          kind: VxButtonKind.secondary,
                          autofocus: true,
                          onPressed: () => context.push('/profil/code-pin'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 28 * s),
                ],
                Text('Restrictions des profils', style: VxText.title(18 * s)),
                SizedBox(height: 6 * s),
                Text(
                  'Les titres au-dessus de l’âge choisi sont masqués du catalogue et de la recherche.',
                  style: VxText.body(14 * s, color: VxColors.textSecondary),
                ),
                SizedBox(height: 14 * s),
                AsyncView(
                  value: profiles,
                  onRetry: () => ref.invalidate(profilesProvider),
                  data: (list) => Column(
                    children: [
                      for (final (i, profile) in list.indexed)
                        Padding(
                          padding: EdgeInsets.only(bottom: 14 * s),
                          // TV: the first switch has the focus when there is no button above.
                          child: _ProfileRestrictions(profile: profile, pin: pin, autofocus: protected && i == 0),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileRestrictions extends ConsumerStatefulWidget {
  const _ProfileRestrictions({required this.profile, required this.pin, this.autofocus = false});

  final Profile profile;
  final String? pin;
  final bool autofocus;

  @override
  ConsumerState<_ProfileRestrictions> createState() => _ProfileRestrictionsState();
}

class _ProfileRestrictionsState extends ConsumerState<_ProfileRestrictions> {
  late Profile _profile = widget.profile;
  bool _saving = false;

  @override
  void didUpdateWidget(_ProfileRestrictions old) {
    super.didUpdateWidget(old);
    if (!_saving) _profile = widget.profile;
  }

  Future<void> _save(Map<String, Object?> fields, String done) async {
    setState(() => _saving = true);
    try {
      final updated = await ref.read(authRepositoryProvider).updateProfile(_profile.id, {
        ...fields,
        'parental_pin': ?widget.pin,
      });
      if (!mounted) return;
      setState(() => _profile = updated);
      ref.read(sessionProvider.notifier).updateProfile(updated);
      ref.invalidate(profilesProvider);
      // The catalog is filtered with the active profile's limits: reload it.
      ref.invalidate(homeProvider);
      showVxSnack(context, done, icon: Icons.shield_rounded);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.field('parental_pin') ?? e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final restricted = p.isKid || p.maxAgeRating != null;
    final s = uiScale(context);
    return ParentalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(profile: p, size: 44 * s),
              SizedBox(width: 12 * s),
              Expanded(child: Text(p.name, style: VxText.title(18 * s))),
              if (_saving) SizedBox.square(dimension: 20 * s, child: const CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
          SizedBox(height: 8 * s),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            autofocus: widget.autofocus,
            value: p.isKid,
            onChanged: _saving
                ? null
                : (v) => _save({'is_kid': v}, v ? '${p.name} : profil enfant' : '${p.name} : profil adulte'),
            title: Text('Profil enfant', style: VxText.body(16 * s, weight: FontWeight.w500)),
            subtitle: Text(
              'Sans âge choisi, limité aux titres pour les 10 ans et moins.',
              style: VxText.body(13 * s, color: VxColors.textSecondary),
            ),
          ),
          SizedBox(height: 6 * s),
          Text(
            'Âge maximum',
            style: VxText.body(14 * s, weight: FontWeight.w600, color: VxColors.textSoft),
          ),
          SizedBox(height: 10 * s),
          FocusTraversalGroup(
            child: Wrap(
              spacing: 8 * s,
              runSpacing: 8 * s,
              children: [
                for (final age in _ageOptions)
                  _Chip(
                    label: _ageLabel(age, kid: p.isKid),
                    selected: p.maxAgeRating == age,
                    scale: s,
                    // The selected chip stays a (no-op) button: same role for screen readers, same focus on TV.
                    onPressed: _saving
                        ? null
                        : () {
                            if (p.maxAgeRating == age) return;
                            _save({'max_age_rating': age}, '${p.name} : ${_ageLabel(age, kid: p.isKid).toLowerCase()}');
                          },
                  ),
              ],
            ),
          ),
          SizedBox(height: 6 * s),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.allowUnrated,
            onChanged: _saving || !restricted
                ? null
                : (v) => _save({
                    'allow_unrated': v,
                  }, v ? 'Titres sans classification affichés' : 'Titres sans classification masqués'),
            title: Text('Titres sans classification', style: VxText.body(16 * s, weight: FontWeight.w500)),
            subtitle: Text(
              restricted
                  ? 'Afficher aussi les titres dont l’âge conseillé est inconnu.'
                  : 'Seulement avec une limite d’âge.',
              style: VxText.body(13 * s, color: VxColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onPressed, this.scale = 1});

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final double scale;

  @override
  Widget build(BuildContext context) => VxFocusable(
    borderRadius: 18 * scale,
    semanticLabel: '$label${selected ? ', sélectionné' : ''}',
    onPressed: onPressed,
    child: Container(
      height: 36 * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      decoration: BoxDecoration(
        color: selected ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
        border: selected ? null : Border.all(color: VxColors.lineStrong),
        borderRadius: BorderRadius.circular(18 * scale),
      ),
      // widthFactor 1: as wide as the label (a plain `alignment` would fill the whole row).
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: VxText.body(14 * scale, weight: FontWeight.w600, color: selected ? VxColors.accent : VxColors.text),
        ),
      ),
    ),
  );
}
