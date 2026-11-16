import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'profile_view.dart';
import 'social_repository.dart';

/// Search type « Comptes »: the members matching the text, with their avatar, name and @username
/// (`AccountTile`; no follower count, developer's request).
class SocialSearchResults extends ConsumerWidget {
  const SocialSearchResults({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().length < 2) return const SizedBox.shrink();
    final layout = Layout.of(context);
    final result = ref.watch(socialSearchProvider(query.trim()));
    Widget note(String text) => ProfileColumn(
      child: Text(text, style: VxText.body(layout.bodySize, color: VxColors.textSecondary)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Comptes'),
        ...switch (result) {
          AsyncValue(value: final profiles?) when profiles.isEmpty => [note('Aucun compte trouvé.')],
          AsyncValue(value: final profiles?) => [
            for (final (i, profile) in profiles.indexed) ...[
              if (i > 0) SizedBox(height: layout.listGap),
              ProfileColumn(child: AccountTile(profile: profile)),
            ],
          ],
          AsyncValue(hasError: true) => [note('Impossible de rechercher les comptes.')],
          _ => [
            Padding(
              padding: EdgeInsets.all(layout.space(VxSpace.m)),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],
        },
      ],
    );
  }
}
