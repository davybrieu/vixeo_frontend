/// Languages a profile can prefer, with their French names. Same codes as the API
/// (`App\Support\Languages` in vixeo_backend): add a language on both sides.
library;

/// Preferred audio track; null (not in the map) = original version.
const audioLanguages = {
  'fr': 'Français',
  'en': 'Anglais',
  'es': 'Espagnol',
  'de': 'Allemand',
  'it': 'Italien',
  'pt': 'Portugais',
  'nl': 'Néerlandais',
  'ar': 'Arabe',
  'ja': 'Japonais',
  'ko': 'Coréen',
  'zh': 'Chinois',
  'ru': 'Russe',
  'pl': 'Polonais',
  'tr': 'Turc',
  'hi': 'Hindi',
};

/// Subtitles; null = none.
const subtitleLanguages = {
  'fr': 'Français',
  'en': 'Anglais',
  'es': 'Espagnol',
  'de': 'Allemand',
  'it': 'Italien',
  'pt-PT': 'Portugais (Portugal)',
  'pt-BR': 'Portugais (Brésil)',
  'nl': 'Néerlandais',
  'ar': 'Arabe',
  'ja': 'Japonais',
  'ko': 'Coréen',
  'zh-CN': 'Chinois simplifié',
  'zh-TW': 'Chinois traditionnel',
  'ru': 'Russe',
  'pl': 'Polonais',
  'tr': 'Turc',
  'hi': 'Hindi',
};

String audioLanguageLabel(String? code) => code == null ? 'Version originale' : audioLanguages[code] ?? code;

String subtitleLanguageLabel(String? code) => code == null ? 'Désactivés' : subtitleLanguages[code] ?? code;
