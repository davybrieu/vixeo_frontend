import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'focusable.dart';

class DescriptionLink extends StatelessWidget {
  const DescriptionLink({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => VxFocusable(
    borderRadius: 6,
    semanticLabel: 'Lire la suite',
    onPressed: () => context.push(
      '/description',
      extra: {'title': title, 'description': description},
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text('Lire la suite', style: VxText.body(14, color: VxColors.accent)),
    ),
  );
}
