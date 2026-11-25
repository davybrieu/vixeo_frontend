import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/theme.dart';
import 'catalog_repository.dart';
import 'models.dart';

/// JustWatch availability surfaced through TMDB's watch-provider endpoint.
class WhereToWatchSection extends ConsumerStatefulWidget {
  const WhereToWatchSection({super.key, required this.type, required this.id});

  final MediaType type;
  final int id;

  @override
  ConsumerState<WhereToWatchSection> createState() => _WhereToWatchSectionState();
}

class _WhereToWatchSectionState extends ConsumerState<WhereToWatchSection> {
  static const _countries = <String, String>{
    'FR': '🇫🇷  France',
    'BE': '🇧🇪  Belgique',
    'CH': '🇨🇭  Suisse',
    'CA': '🇨🇦  Canada',
    'GB': '🇬🇧  Royaume-Uni',
    'US': '🇺🇸  États-Unis',
    'ES': '🇪🇸  Espagne',
    'DE': '🇩🇪  Allemagne',
    'IT': '🇮🇹  Italie',
  };

  String _country = 'FR';
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() => ref
      .read(catalogRepositoryProvider)
      .watchProviders(widget.type, widget.id, country: _country);

  void _changeCountry(String? value) {
    if (value == null || value == _country) return;
    setState(() {
      _country = value;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Où regarder', style: VxText.title(layout.size(20, tv: 30), weight: FontWeight.w700)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: VxColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: VxColors.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _country,
                      dropdownColor: VxColors.surface,
                      icon: const Icon(Icons.expand_more_rounded, color: VxColors.textSoft),
                      style: VxText.body(14, weight: FontWeight.w600),
                      items: _countries.entries
                          .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                          .toList(),
                      onChanged: _changeCountry,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _message('Les disponibilités ne sont pas accessibles pour le moment.');
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              final groups = <(String, String)>[
                ('flatrate', 'ABONNEMENT'),
                ('free', 'GRATUIT'),
                ('ads', 'AVEC PUBLICITÉ'),
                ('rent', 'LOCATION'),
                ('buy', 'ACHAT'),
              ];
              final available = groups.where((group) => (data[group.$1] as List? ?? []).isNotEmpty).toList();
              if (available.isEmpty) {
                return _message('Aucune disponibilité référencée pour ce titre dans ce pays.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in available) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Text(
                        group.$2,
                        style: VxText.body(12, color: VxColors.textSoft, weight: FontWeight.w600),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: VxColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: VxColors.line),
                      ),
                      child: Column(
                        children: [
                          for (final provider in (data[group.$1] as List).whereType<Map<String, dynamic>>())
                            _ProviderRow(provider: provider),
                        ],
                      ),
                    ),
                  ],
                  if (data['link'] is String && (data['link'] as String).isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => launchUrl(Uri.parse(data['link'] as String), mode: LaunchMode.externalApplication),
                        child: Text('Données fournies par JustWatch', style: VxText.body(12, color: VxColors.textSoft)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _message(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: VxColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: VxColors.line),
    ),
    child: Text(message, style: VxText.body(14, color: VxColors.textSoft)),
  );
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider});

  final Map<String, dynamic> provider;

  @override
  Widget build(BuildContext context) {
    final path = provider['logo_path'] as String?;
    final name = provider['provider_name'] as String? ?? 'Plateforme';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 46,
              child: path == null
                  ? const ColoredBox(color: Color(0xFF292929), child: Icon(Icons.tv_rounded))
                  : Image.network(
                      'https://image.tmdb.org/t/p/w92$path',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFF292929),
                        child: Icon(Icons.tv_rounded),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(name, style: VxText.body(15, weight: FontWeight.w600))),
          if (provider['display_priority'] is int)
            const Icon(Icons.chevron_right_rounded, color: VxColors.textSoft),
        ],
      ),
    );
  }
}
