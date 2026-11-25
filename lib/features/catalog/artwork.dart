import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'catalog_repository.dart';
import 'models.dart';

/// « Affiches, arrière-plans, logos » (developer's request, 25/11/2026; API:
/// vixeo_backend/docs/images-des-titres.md): a profile chooses the images of a title among
/// TMDb's, and the API then gives them to this profile wherever the title appears.
enum ArtworkKind {
  poster('Affiches', 'poster', 'posters', 'Affiche', 'affiche'),
  backdrop('Arrière-plans', 'backdrop', 'backdrops', 'Arrière-plan', 'arriere-plan'),
  logo('Logos', 'logo', 'logos', 'Logo', 'logo');

  const ArtworkKind(this.label, this.field, this.listKey, this.one, this.slug);

  /// In the page's address: `/titre/movie/550/images?sorte=arriere-plan`.
  final String slug;

  static ArtworkKind fromSlug(String? slug) =>
      ArtworkKind.values.firstWhere((kind) => kind.slug == slug, orElse: () => ArtworkKind.poster);

  /// The tab: « Affiches ».
  final String label;

  /// The key of the choice (`poster`) and of TMDb's list (`posters`).
  final String field;
  final String listKey;

  /// One of them, for the screen readers: « Affiche 3 ».
  final String one;
}

/// One image of TMDb (a thumbnail for the choice page).
class TitleImage {
  const TitleImage({required this.path, this.url, this.language, this.aspectRatio});

  factory TitleImage.fromJson(Map<String, dynamic> json) => TitleImage(
    path: json['path'] as String,
    url: json['url'] as String?,
    language: json['language'] as String?,
    aspectRatio: (json['aspect_ratio'] as num?)?.toDouble(),
  );

  /// TMDb's path ("/abc.jpg"): what the choice keeps.
  final String path;
  final String? url;
  final String? language;
  final double? aspectRatio;
}

/// The images of a title: TMDb's choice, the profile's, and what it can choose from.
class TitleImages {
  const TitleImages({required this.defaults, required this.chosen, required this.images});

  factory TitleImages.fromJson(Map<String, dynamic> json) {
    final defaults = json['default'] as Map<String, dynamic>? ?? const {};
    final chosen = json['chosen'] as Map<String, dynamic>? ?? const {};
    return TitleImages(
      defaults: {
        for (final kind in ArtworkKind.values)
          kind: defaults[kind.field] == null
              ? null
              : TitleImage(path: defaults[kind.field] as String, url: defaults['${kind.field}_url'] as String?),
      },
      chosen: {for (final kind in ArtworkKind.values) kind: chosen[kind.field] as String?},
      images: {
        for (final kind in ArtworkKind.values)
          kind: [
            for (final image in (json[kind.listKey] as List? ?? const []).whereType<Map<String, dynamic>>())
              TitleImage.fromJson(image),
          ],
      },
    );
  }

  /// TMDb's (« Par défaut »); null when TMDb has none.
  final Map<ArtworkKind, TitleImage?> defaults;

  /// The profile's choice: a path, or null for TMDb's.
  final Map<ArtworkKind, String?> chosen;
  final Map<ArtworkKind, List<TitleImage>> images;
}

/// The images of a title (type, id), for the active profile.
final titleImagesProvider = FutureProvider.autoDispose.family<TitleImages, (MediaType, int)>((ref, key) {
  ref.watch(sessionProvider.select((s) => s.profile?.id));
  return ref.read(catalogRepositoryProvider).images(key.$1, key.$2);
});

/// Keeps the choice of the active profile, then the catalog is read again: every list, search and
/// title page shows the new image.
Future<void> chooseTitleImage(WidgetRef ref, MediaType type, int id, ArtworkKind kind, String? path) async {
  final profileId = ref.read(sessionProvider).profile?.id;
  if (profileId == null) return;
  await ref.read(catalogRepositoryProvider).chooseImage(profileId, type, id, kind, path);
  ref.read(catalogEpochProvider.notifier).bump();
}
