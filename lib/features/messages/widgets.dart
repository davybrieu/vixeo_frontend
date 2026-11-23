import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import '../notifications/inbox.dart' show dayLabel;
import '../profiles/avatars.dart';
import '../social/profile_view.dart' show ProfileHeader;
import '../social/social_repository.dart';
import 'messages.dart';

/// The avatar of a member (catalog avatar, else its initial), or a group's icon.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, this.member, this.group = false, required this.size});

  final ChatMember? member;
  final bool group;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (group) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: VxColors.surfaceHigh, shape: BoxShape.circle),
        child: Icon(Icons.groups_rounded, size: size * 0.55, color: VxColors.textSecondary),
      );
    }
    return AvatarTile(
      avatarId: member?.avatar,
      initial: ProfileHeader.initialOf(member?.name ?? ''),
      size: size,
      radius: size / 2,
    );
  }
}

/// A member in a list of the messaging (search, group members): avatar, name, @username, and what
/// is on the right ([trailing]: buttons, a badge). Pressable when [onPressed] is given.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.member,
    this.subtitle,
    this.trailing,
    this.onPressed,
    this.semanticLabel,
    this.autofocus = false,
  });

  final ChatMember member;

  /// Under the name, instead of « @pseudo ».
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(44, tv: 72);
    final row = Padding(
      padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
      child: Row(
        children: [
          ChatAvatar(member: member, size: avatar),
          SizedBox(width: layout.space(VxSpace.s)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                ),
                Text(
                  subtitle ?? '@${member.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: layout.space(VxSpace.xs)), trailing!],
        ],
      ),
    );
    if (onPressed == null) return row;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: semanticLabel ?? '${member.displayName}, @${member.username}',
      autofocus: autofocus,
      onPressed: onPressed,
      child: row,
    );
  }
}

/// A member found by the account search, as the messaging shows it.
ChatMember memberOf(SocialProfile profile) =>
    ChatMember(id: profile.id, username: profile.username, name: profile.name, avatar: profile.avatar);

/// The members whose @username contains [query] (2 letters at least), but those in [exclude]:
/// a press on one calls [onPick]. The search is the one of the « Comptes » (never the active profile).
class MemberSearchResults extends ConsumerWidget {
  const MemberSearchResults({
    super.key,
    required this.query,
    required this.onPick,
    this.exclude = const {},
    this.pickIcon,
    this.pickLabel = 'Écrire à',
  });

  final String query;
  final ValueChanged<ChatMember> onPick;

  /// Ids of the profiles not to show (already chosen, already in the group).
  final Set<int> exclude;

  /// Shown on the right of each member (« ajouter »).
  final IconData? pickIcon;

  /// Read before the member's name by screen readers (« Écrire à Léa »).
  final String pickLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = query.trim();
    if (text.length < 2) return const SizedBox.shrink();
    final layout = Layout.of(context);
    Widget note(String message) => Padding(
      padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xs)),
      child: Text(message, style: VxText.body(layout.bodySize, color: VxColors.textSecondary)),
    );
    return switch (ref.watch(socialSearchProvider(text))) {
      AsyncValue(value: final profiles?) => () {
        final members = [
          for (final profile in profiles)
            if (!exclude.contains(profile.id)) memberOf(profile),
        ];
        if (members.isEmpty) return note('Aucun membre trouvé.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, member) in members.indexed) ...[
              if (i > 0) SizedBox(height: layout.space(VxSpace.xxs)),
              MemberRow(
                member: member,
                semanticLabel: '$pickLabel ${member.displayName}, @${member.username}',
                trailing: pickIcon == null
                    ? null
                    : Icon(pickIcon, size: layout.size(24, tv: 36), color: VxColors.textSecondary),
                onPressed: () => onPick(member),
              ),
            ],
          ],
        );
      }(),
      AsyncValue(hasError: true) => note('Impossible de rechercher les membres.'),
      _ => Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.m)),
        child: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// « 14:05 » (today), « Hier », « lun. », then « 24/11 »: the date of a conversation in the list.
String conversationTime(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inHours ~/ 24;
  if (days <= 0) return hourMinute(at);
  if (days == 1) return 'Hier';
  if (days < 7) return const ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'][at.weekday - 1];
  final date = '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
  return at.year == now.year ? date : '$date/${at.year}';
}

/// « 14:05 ».
String hourMinute(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// « Aujourd’hui », « Hier », « Lundi 24 novembre »: above the first message of a day.
String messageDay(DateTime at, DateTime now) {
  final day = dayLabel(at, now);
  return '${day[0].toUpperCase()}${day.substring(1)}';
}

/// « 12 Mo », « 850 Ko »: the size of an attachment.
String fileSize(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes >= 10 * 1024 * 1024 ? 0 : 1).replaceAll('.', ',')} Mo';
  return '${(bytes / 1024).ceil()} Ko';
}

/// The number of unread messages of a conversation: a green pill (« 9+ » above 9).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.size(20, tv: 32);
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.symmetric(horizontal: size * 0.3),
      decoration: BoxDecoration(color: VxColors.accent, borderRadius: BorderRadius.circular(size / 2)),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: VxText.body(size * 0.6, weight: FontWeight.w700, color: VxColors.onAccent, height: 1),
      ),
    );
  }
}

/// The text of an action that failed, for an alert.
String errorText(Object error, String fallback) => error is ApiException ? error.message : fallback;
