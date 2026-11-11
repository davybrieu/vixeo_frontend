import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'avatars.dart';

final profilesProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.read(authRepositoryProvider).profiles();
});

/// Avatar colors, by position.
const _tileColors = [
  (VxColors.accent, VxColors.onAccent),
  (Color(0xFF15524A), Color(0xFFE7F7F0)),
  (Color(0xFFC9B98F), Color(0xFF1A1710)),
  (Color(0xFF334039), VxColors.accent),
  (Color(0xFF3A2A30), Color(0xFFF4E3EA)),
];

/// "Qui regarde ?"
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profiles = ref.watch(profilesProvider);
    final tile = layout.isLarge ? layout.tv(220) : 120.0;

    Future<void> open(Profile profile) async {
      if (profile.hasPin) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _PinDialog(profile: profile),
        );
        if (ok != true) return;
      }
      await ref.read(sessionProvider.notifier).selectProfile(profile);
    }

    // Right after the start-up loading: the same one until the profiles are there.
    if (!profiles.hasValue && !profiles.hasError) return const Scaffold(body: AppLoading());

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.isPhone ? 8 : layout.gutter, 0),
              child: Row(
                children: [
                  VxLogo(size: layout.isLarge ? layout.tv(36).clamp(22, 40).toDouble() : 22),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(sessionProvider.notifier).logout();
                      if (context.mounted) context.go('/accueil');
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Se déconnecter'),
                    style: TextButton.styleFrom(foregroundColor: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AsyncView(
                value: profiles,
                onRetry: () => ref.invalidate(profilesProvider),
                data: (list) => Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.l), horizontal: layout.gutter),
                    child: Column(
                      children: [
                        Text('Qui regarde ?', style: VxText.title(layout.isLarge ? layout.tv(64) : 28)),
                        SizedBox(height: layout.space(VxSpace.xxl)),
                        FocusTraversalGroup(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: layout.space(VxSpace.xl),
                            runSpacing: layout.space(VxSpace.xl),
                            children: [
                              for (var i = 0; i < list.length; i++)
                                _ProfileTile(
                                  profile: list[i],
                                  colors: _tileColors[i % _tileColors.length],
                                  size: tile,
                                  autofocus: i == 0,
                                  onPressed: () => open(list[i]),
                                ),
                              if (list.length < 5)
                                _AddTile(
                                  size: tile,
                                  onPressed: () async {
                                    final created = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => const _AddProfileDialog(),
                                    );
                                    if (created == true) ref.invalidate(profilesProvider);
                                  },
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: layout.space(VxSpace.xl)),
                        Text(
                          'Les profils protégés par un code demandent le PIN à l’ouverture.',
                          textAlign: TextAlign.center,
                          style: VxText.body(layout.isLarge ? layout.tv(19) : 13, color: VxColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.colors,
    required this.size,
    required this.onPressed,
    this.autofocus = false,
  });

  final Profile profile;
  final (Color, Color) colors;
  final double size;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.2;
    final label = [
      profile.name,
      if (profile.isKid) 'profil enfant',
      if (profile.hasPin) 'protégé par un code',
    ].join(', ');
    return SizedBox(
      width: size + 16,
      child: Column(
        children: [
          VxFocusable(
            autofocus: autofocus,
            onPressed: onPressed,
            borderRadius: radius,
            onAccent: profile.avatar == null && colors.$1 == VxColors.accent,
            focusScale: 1.08,
            semanticLabel: label,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  AvatarTile(
                    avatarId: profile.avatar,
                    initial: profile.initial,
                    size: size,
                    radius: radius,
                    fallbackColor: colors.$1,
                    fallbackInk: colors.$2,
                  ),
                  if (profile.isKid)
                    Positioned(
                      left: size * 0.07,
                      top: size * 0.07,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: size * 0.07, vertical: size * 0.02),
                        decoration: BoxDecoration(
                          color: VxColors.background,
                          borderRadius: BorderRadius.circular(size),
                        ),
                        child: Text('Enfant', style: VxText.body(size * 0.09, weight: FontWeight.w600)),
                      ),
                    ),
                  if (profile.hasPin)
                    Positioned(
                      right: size * 0.07,
                      bottom: size * 0.07,
                      child: Container(
                        width: size * 0.23,
                        height: size * 0.23,
                        decoration: const BoxDecoration(color: Color(0xB8070A08), shape: BoxShape.circle),
                        child: Icon(Icons.lock_outline_rounded, size: size * 0.13, color: VxColors.text),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: size * 0.1),
          ExcludeSemantics(
            child: Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(size * 0.125, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onPressed});

  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 16,
    child: Column(
      children: [
        VxFocusable(
          onPressed: onPressed,
          borderRadius: size * 0.2,
          semanticLabel: 'Ajouter un profil',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.2),
              border: Border.all(color: VxColors.lineStrong, width: 2),
            ),
            child: Icon(Icons.add_rounded, size: size * 0.3, color: VxColors.textSecondary),
          ),
        ),
        SizedBox(height: size * 0.1),
        ExcludeSemantics(
          child: Text(
            'Ajouter',
            style: VxText.body(size * 0.125, weight: FontWeight.w500, color: VxColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// Asks a profile's PIN and checks it with the API. Pops `true` when correct.
class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_pin.text.length != 4) {
      setState(() => _error = 'Saisissez les 4 chiffres.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyProfilePin(widget.profile.id, _pin.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.field('pin') ?? e.message;
          _pin.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Code de ${widget.profile.name}'),
    content: SizedBox(
      width: 320,
      child: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        style: VxText.title(28).copyWith(letterSpacing: 16),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _check(),
        onChanged: (v) {
          if (v.length == 4) _check();
        },
        decoration: InputDecoration(counterText: '', hintText: '••••', errorText: _error),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
      VxButton(label: 'Valider', onPressed: _check, loading: _loading),
    ],
  );
}

/// Creates a profile. The parental PIN is asked when parental control is on.
class _AddProfileDialog extends ConsumerStatefulWidget {
  const _AddProfileDialog();

  @override
  ConsumerState<_AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends ConsumerState<_AddProfileDialog> {
  final _name = TextEditingController();
  final _parentalPin = TextEditingController();
  bool _isKid = false;
  bool _loading = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _parentalPin.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .createProfile(name: _name.text.trim(), isKid: _isKid, parentalPin: _parentalPin.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parental = ref.watch(sessionProvider).user?.parentalControl ?? false;
    final error = _error;
    return AlertDialog(
      title: const Text('Nouveau profil'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Prénom', errorText: error?.field('name')),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isKid,
              onChanged: (v) => setState(() => _isKid = v),
              contentPadding: EdgeInsets.zero,
              title: Text('Profil enfant', style: VxText.body(16, weight: FontWeight.w500)),
              subtitle: Text(
                'Titres adaptés aux 10 ans et moins',
                style: VxText.body(13, color: VxColors.textSecondary),
              ),
            ),
            if (parental) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _parentalPin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Code PIN parental',
                  counterText: '',
                  errorText: error?.field('parental_pin'),
                ),
              ),
            ],
            if (error != null && error.fieldErrors.isEmpty) ...[
              const SizedBox(height: 8),
              Text(error.message, style: VxText.body(14, color: VxColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        VxButton(label: 'Créer', onPressed: _create, loading: _loading),
      ],
    );
  }
}
