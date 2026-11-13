import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/session.dart';

/// A page made of rows the profile can sort and hide (« Paramètres »).
enum RowsPage {
  /// The rows of the home page (« Films du moment »…), by `Section.key`.
  home('home'),

  /// The categories of the « Chaînes TV » page, by category id.
  channels('channels');

  const RowsPage(this.storageName);

  final String storageName;
}

/// The order of the rows of a page and the rows left out, chosen in the settings.
///
/// Rows are named by a key (a home section's key, a channel category's id). A row the profile
/// never placed (a new list of the API, a new category) keeps its usual place, after the placed
/// ones, and is shown.
@immutable
class RowPreferences {
  const RowPreferences({this.order = const [], this.hidden = const {}});

  /// Nothing chosen: the usual order, every row shown.
  static const none = RowPreferences();

  /// Reads what [toJson] wrote; anything else is [none].
  factory RowPreferences.fromJson(String? text) {
    if (text == null || text.isEmpty) return none;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return none;
      List<String> strings(Object? value) => value is List ? value.whereType<String>().toList() : const [];
      return RowPreferences(order: strings(json['order']), hidden: strings(json['hidden']).toSet());
    } on FormatException {
      return none;
    }
  }

  final List<String> order;
  final Set<String> hidden;

  bool get isDefault => order.isEmpty && hidden.isEmpty;

  String toJson() => jsonEncode({'order': order, 'hidden': hidden.toList()});

  bool isHidden(String key) => hidden.contains(key);

  /// Every row in the chosen order, hidden ones included (the settings page).
  List<T> sorted<T>(List<T> rows, String Function(T row) keyOf) {
    if (order.isEmpty) return rows;
    final rank = {for (final (index, key) in order.indexed) key: index};
    final indexed = rows.indexed.toList()
      ..sort((a, b) {
        final ra = rank[keyOf(a.$2)];
        final rb = rank[keyOf(b.$2)];
        if (ra != null && rb != null) return ra.compareTo(rb);
        if (ra != null) return -1;
        if (rb != null) return 1;
        // Neither was placed: the order they came in.
        return a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  /// The rows to show, in the chosen order.
  List<T> visible<T>(List<T> rows, String Function(T row) keyOf) {
    if (isDefault) return rows;
    return sorted(rows, keyOf).where((row) => !hidden.contains(keyOf(row))).toList();
  }
}

/// Where the row preferences are kept: on the device, per profile.
abstract class RowPreferencesStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// The device's protected storage (the one that keeps the session).
class SecureRowPreferencesStorage implements RowPreferencesStorage {
  SecureRowPreferencesStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

/// For tests.
class MemoryRowPreferencesStorage implements RowPreferencesStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

final rowPreferencesStorageProvider = Provider<RowPreferencesStorage>((ref) => SecureRowPreferencesStorage());

/// The row preferences of one page, for the active profile. Read once per profile; a page shows
/// its usual rows until they are read (and if the storage can't be read).
abstract class RowPreferencesController extends AsyncNotifier<RowPreferences> {
  RowPreferencesController(this.page);

  final RowsPage page;

  String _key(int? profileId) => 'vixeo.rows.${page.storageName}.${profileId ?? 0}';

  @override
  Future<RowPreferences> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    try {
      return RowPreferences.fromJson(await ref.read(rowPreferencesStorageProvider).read(_key(profileId)));
    } catch (_) {
      // No storage (private browsing, tests…): the usual rows.
      return RowPreferences.none;
    }
  }

  /// Applies [value] at once, then keeps it on the device.
  Future<void> save(RowPreferences value) async {
    state = AsyncData(value);
    final profileId = ref.read(sessionProvider).profile?.id;
    try {
      await ref.read(rowPreferencesStorageProvider).write(_key(profileId), value.isDefault ? null : value.toJson());
    } catch (_) {
      // Kept for this session only.
    }
  }
}

class HomeRowPreferences extends RowPreferencesController {
  HomeRowPreferences() : super(RowsPage.home);
}

class ChannelRowPreferences extends RowPreferencesController {
  ChannelRowPreferences() : super(RowsPage.channels);
}

/// Order and visibility of the home rows.
final homeRowPreferencesProvider = AsyncNotifierProvider<HomeRowPreferences, RowPreferences>(HomeRowPreferences.new);

/// Order and visibility of the categories of the « Chaînes TV » page.
final channelRowPreferencesProvider = AsyncNotifierProvider<ChannelRowPreferences, RowPreferences>(
  ChannelRowPreferences.new,
);
